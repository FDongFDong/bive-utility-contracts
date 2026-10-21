// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MainVoting} from "../src/vote/MainVoting.sol";

/**
 * HIGH-1 PoC: votingAmt 상한 부재로 인한 집계 오버플로우 DoS
 *
 * 공격자가 자기 주소로 votingAmt = type(uint256).max 레코드를 정상 서명·제출하면
 * artistStats.total 이 max 로 고정되고, 이후 그 아티스트에 대한 모든 투표가
 * checked 산술 오버플로우로 revert → 배치 전체가 마비되는지 검증한다.
 *
 * 서명/도메인 헬퍼는 MainVoting.t.sol 과 동일 로직을 복제한다 (독립 실행용).
 */
contract MainVotingOverflowDoSTest is Test {
    MainVoting public voting;

    address public owner;
    uint256 public executorPrivateKey = 0x4444;
    address public executorSigner;

    // 공격자 / 정상 유저
    uint256 public attackerPk = 0xA11CE;
    uint256 public victimPk = 0xB0B;
    address public attacker;
    address public victim;

    bytes32 private constant VOTE_RECORD_TYPEHASH =
        keccak256(
            "VoteRecord(uint256 timestamp,uint256 missionId,uint256 votingId,uint256 optionId,uint8 voteType,uint256 votingAmt,address user)"
        );
    bytes32 private constant USER_BATCH_TYPEHASH =
        keccak256("UserBatch(address user,uint256 userNonce,bytes32 recordsHash)");
    bytes32 private constant BATCH_TYPEHASH =
        keccak256("Batch(uint256 batchNonce)");

    function setUp() public {
        owner = address(this);
        executorSigner = vm.addr(executorPrivateKey);
        attacker = vm.addr(attackerPk);
        victim = vm.addr(victimPk);

        voting = new MainVoting(owner);
        voting.setExecutorSigner(executorSigner);
        voting.setArtist(1, 1, "Artist1", true);
        voting.setVoteTypeName(0, "Forget");
        voting.setVoteTypeName(1, "Remember");
    }

    // ── 서명 헬퍼 (MainVoting.t.sol 과 동일) ─────────────────────────────

    function _domainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes("MainVoting")),
                    keccak256(bytes("1")),
                    block.chainid,
                    address(voting)
                )
            );
    }

    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19\x01", _domainSeparator(), structHash)
            );
    }

    function _record(
        uint256 optionId,
        uint256 votingAmt,
        uint256 salt
    ) internal view returns (MainVoting.VoteRecord memory) {
        return
            MainVoting.VoteRecord({
                recordId: salt,
                timestamp: block.timestamp,
                missionId: 1,
                votingId: 1,
                optionId: optionId,
                voteType: 1, // Remember
                userId: "poc",
                votingAmt: votingAmt
            });
    }

    function _hashRecord(
        MainVoting.VoteRecord memory r,
        address user
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    VOTE_RECORD_TYPEHASH,
                    r.timestamp,
                    r.missionId,
                    r.votingId,
                    r.optionId,
                    r.voteType,
                    r.votingAmt,
                    user
                )
            );
    }

    function _signUser(
        uint256 pk,
        MainVoting.VoteRecord[] memory records,
        uint256 nonce
    ) internal view returns (bytes memory) {
        address user = vm.addr(pk);
        bytes32[] memory digests = new bytes32[](records.length);
        for (uint256 i; i < records.length; i++) {
            digests[i] = _hashRecord(records[i], user);
        }
        bytes32 recordsHash = keccak256(abi.encodePacked(digests));
        bytes32 structHash = keccak256(
            abi.encode(USER_BATCH_TYPEHASH, user, nonce, recordsHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _hashTypedDataV4(structHash));
        return abi.encodePacked(r, s, v);
    }

    function _signBatch(uint256 pk, uint256 nonce) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(BATCH_TYPEHASH, nonce));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _hashTypedDataV4(structHash));
        return abi.encodePacked(r, s, v);
    }

    function _oneUserBatch(
        MainVoting.VoteRecord memory record,
        address user,
        uint256 nonce,
        uint256 pk
    ) internal view returns (MainVoting.UserVoteBatch[] memory) {
        MainVoting.VoteRecord[] memory records = new MainVoting.VoteRecord[](1);
        records[0] = record;
        MainVoting.UserVoteBatch[] memory batches = new MainVoting.UserVoteBatch[](1);
        batches[0] = MainVoting.UserVoteBatch({
            records: records,
            userBatchSig: MainVoting.UserBatchSig({
                user: user,
                userNonce: nonce,
                signature: _signUser(pk, records, nonce)
            })
        });
        return batches;
    }

    // ── 회귀 테스트 (HIGH-1 수정 후: 공격 차단 확인) ────────────────────────

    /// @notice 수정 후: max 금액 레코드는 soft-fail(REASON_AMOUNT_TOO_LARGE)로 거부되어야 한다.
    ///         공격 배치는 성공 유저 0명 → NoSuccessfulUser revert, 집계는 오염되지 않음.
    ///         이후 정상 유저 투표는 정상 처리되어 DoS 가 없음을 확인.
    function test_Fixed_MaxVotingAmtRejectedNoDoS() public {
        // === 1. 공격 시도: votingAmt = type(uint256).max → soft-fail → 전체 revert ===
        MainVoting.UserVoteBatch[] memory attackBatch = _oneUserBatch(
            _record(1, type(uint256).max, 1),
            attacker,
            1,
            attackerPk
        );
        vm.expectRevert(MainVoting.NoSuccessfulUser.selector);
        voting.submitMultiUserBatch(attackBatch, 1, _signBatch(executorPrivateKey, 1));

        // 집계가 오염되지 않았는지 확인 (여전히 0)
        (, , uint256 totalAfterAttack) = voting.getArtistAggregates(1, 1);
        assertEq(totalAfterAttack, 0, unicode"공격 레코드는 저장되지 않아야 함");

        // === 2. 정상 유저 투표는 DoS 없이 성공 ===
        MainVoting.UserVoteBatch[] memory victimBatch = _oneUserBatch(
            _record(1, 100, 2),
            victim,
            1,
            victimPk
        );
        voting.submitMultiUserBatch(victimBatch, 2, _signBatch(executorPrivateKey, 2));

        (, , uint256 total) = voting.getArtistAggregates(1, 1);
        assertEq(total, 100, unicode"정상 투표는 DoS 없이 처리되어야 함");
    }

    // ── HIGH-2 회귀: 제출 권한 제한 (front-run 차단) ──────────────────────

    /// @notice 제3자가 유효한 executorSig + 유저 배치를 갖고 있어도
    ///         executor/owner 가 아니면 제출 불가 → front-run/batchNonce 선점 차단
    function test_Fixed_ThirdPartyCannotFrontRun() public {
        MainVoting.UserVoteBatch[] memory batch = _oneUserBatch(
            _record(1, 100, 1),
            victim,
            1,
            victimPk
        );
        bytes memory validExecutorSig = _signBatch(executorPrivateKey, 1);

        // 제3자(공격자)가 유효한 서명 세트를 그대로 복사해 front-run 시도
        vm.prank(attacker);
        vm.expectRevert(MainVoting.NotOwnerOrExecutor.selector);
        voting.submitMultiUserBatch(batch, 1, validExecutorSig);

        // executor 본인은 정상 제출 가능
        vm.prank(executorSigner);
        voting.submitMultiUserBatch(batch, 1, validExecutorSig);
        (, , uint256 total) = voting.getArtistAggregates(1, 1);
        assertEq(total, 100, unicode"executor 제출은 정상 처리되어야 함");
    }

    // ── MEDIUM-1 회귀: atomic 실패 유저의 nonce 미소비 & 재시도 가능 ─────────

    /// @notice 다중 유저 배치에서 atomic 검증 실패 유저의 nonce는 소비되지 않고,
    ///         동일 nonce로 (올바른 입력으로) 재시도하면 성공해야 한다.
    function test_Fixed_NonceSurvivesAtomicFailureAndRetryWorks() public {
        // attacker: 미등록 아티스트(optionId 99) → atomic 실패
        // victim: 유효 → 성공 (배치가 revert되지 않도록 성공 유저 동반)
        MainVoting.VoteRecord[] memory aRec = new MainVoting.VoteRecord[](1);
        aRec[0] = _record(99, 100, 1); // optionId 99 미등록
        MainVoting.VoteRecord[] memory vRec = new MainVoting.VoteRecord[](1);
        vRec[0] = _record(1, 100, 2);

        MainVoting.UserVoteBatch[] memory batches = new MainVoting.UserVoteBatch[](2);
        batches[0] = MainVoting.UserVoteBatch({
            records: aRec,
            userBatchSig: MainVoting.UserBatchSig({
                user: attacker,
                userNonce: 7,
                signature: _signUser(attackerPk, aRec, 7)
            })
        });
        batches[1] = MainVoting.UserVoteBatch({
            records: vRec,
            userBatchSig: MainVoting.UserBatchSig({
                user: victim,
                userNonce: 7,
                signature: _signUser(victimPk, vRec, 7)
            })
        });

        voting.submitMultiUserBatch(batches, 1, _signBatch(executorPrivateKey, 1));

        // atomic 실패한 attacker의 nonce 7은 소비되지 않음
        assertFalse(
            voting.usedUserNonces(attacker, 7),
            unicode"atomic 실패 유저의 nonce는 소비되지 않아야 함"
        );
        // 성공한 victim의 nonce 7은 소비됨
        assertTrue(voting.usedUserNonces(victim, 7));

        // attacker가 동일 nonce 7로 올바른 아티스트에 재시도 → 성공
        MainVoting.UserVoteBatch[] memory retry = _oneUserBatch(
            _record(1, 100, 3),
            attacker,
            7,
            attackerPk
        );
        voting.submitMultiUserBatch(retry, 2, _signBatch(executorPrivateKey, 2));

        assertTrue(
            voting.usedUserNonces(attacker, 7),
            unicode"재시도 성공 후 nonce가 소비되어야 함"
        );
    }

    /// @notice 경계값: 상한(MAX_VOTING_AMT)은 허용, 초과분은 거부
    function test_Fixed_BoundaryMaxVotingAmt() public {
        // 상한 정확히: 허용되어 저장
        MainVoting.UserVoteBatch[] memory atCap = _oneUserBatch(
            _record(1, voting.MAX_VOTING_AMT(), 1),
            attacker,
            1,
            attackerPk
        );
        voting.submitMultiUserBatch(atCap, 1, _signBatch(executorPrivateKey, 1));
        (, , uint256 total) = voting.getArtistAggregates(1, 1);
        assertEq(total, voting.MAX_VOTING_AMT(), unicode"상한값은 허용되어야 함");

        // 상한 + 1: soft-fail → 성공 유저 0 → revert, 집계 불변
        MainVoting.UserVoteBatch[] memory overCap = _oneUserBatch(
            _record(1, voting.MAX_VOTING_AMT() + 1, 2),
            victim,
            1,
            victimPk
        );
        vm.expectRevert(MainVoting.NoSuccessfulUser.selector);
        voting.submitMultiUserBatch(overCap, 2, _signBatch(executorPrivateKey, 2));
    }

    /// @notice 대조군: max 가 아니면(예: 정상 금액 2건) 문제 없이 누적된다
    function test_Control_NormalAmountsAccumulate() public {
        MainVoting.UserVoteBatch[] memory b1 = _oneUserBatch(
            _record(1, 100, 1),
            attacker,
            1,
            attackerPk
        );
        voting.submitMultiUserBatch(b1, 1, _signBatch(executorPrivateKey, 1));

        MainVoting.UserVoteBatch[] memory b2 = _oneUserBatch(
            _record(1, 50, 2),
            victim,
            1,
            victimPk
        );
        voting.submitMultiUserBatch(b2, 2, _signBatch(executorPrivateKey, 2));

        (, , uint256 total) = voting.getArtistAggregates(1, 1);
        assertEq(total, 150, unicode"정상 금액은 누적되어야 함");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SubVoting} from "../src/vote/SubVoting.sol";

/**
 * SubVoting 보안 회귀 테스트
 * - HIGH-1: votingAmt 상한(MAX_VOTING_AMT)으로 집계 오버플로우 DoS 차단
 * - HIGH-2: submitMultiUserBatch 제출 권한을 executor/owner로 제한 (front-run 차단)
 *
 * 서명 헬퍼는 SubVoting.t.sol 과 동일 로직을 복제한다 (독립 실행용).
 * 등록: mission 1 / question 1 / option 1 (setUp).
 */
contract SubVotingSecurityTest is Test {
    SubVoting public voting;

    address public owner;
    uint256 public executorPrivateKey = 0x4444;
    address public executorSigner;

    uint256 public attackerPk = 0xA11CE;
    uint256 public victimPk = 0xB0B;
    address public attacker;
    address public victim;

    bytes32 private constant VOTE_RECORD_TYPEHASH =
        keccak256(
            "VoteRecord(uint256 timestamp,uint256 missionId,uint256 votingId,uint256 questionId,uint256 optionId,uint256 votingAmt,address user)"
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

        voting = new SubVoting(owner);
        voting.setExecutorSigner(executorSigner);
        voting.setQuestion(1, 1, "Question1", true);
        voting.setOption(1, 1, 1, "OptionA", true);
    }

    // ── 서명 헬퍼 ────────────────────────────────────────────────────────

    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19\x01", voting.domainSeparator(), structHash)
            );
    }

    function _record(
        uint256 optionId,
        uint256 votingAmt,
        uint256 recordId
    ) internal view returns (SubVoting.VoteRecord memory) {
        return
            SubVoting.VoteRecord({
                recordId: recordId,
                timestamp: block.timestamp,
                missionId: 1,
                votingId: 1,
                userId: "poc",
                questionId: 1,
                optionId: optionId,
                votingAmt: votingAmt
            });
    }

    function _hashRecord(
        SubVoting.VoteRecord memory r,
        address user
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    VOTE_RECORD_TYPEHASH,
                    r.timestamp,
                    r.missionId,
                    r.votingId,
                    r.questionId,
                    r.optionId,
                    r.votingAmt,
                    user
                )
            );
    }

    function _signUser(
        uint256 pk,
        SubVoting.VoteRecord[] memory records,
        uint256 nonce
    ) internal view returns (bytes memory) {
        bytes32[] memory digests = new bytes32[](records.length);
        for (uint256 i; i < records.length; i++) {
            digests[i] = _hashRecord(records[i], vm.addr(pk));
        }
        bytes32 recordsHash = keccak256(abi.encodePacked(digests));
        bytes32 structHash = keccak256(
            abi.encode(USER_BATCH_TYPEHASH, vm.addr(pk), nonce, recordsHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _hashTypedDataV4(structHash));
        return abi.encodePacked(r, s, v);
    }

    function _signBatch(uint256 pk, uint256 nonce) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(BATCH_TYPEHASH, nonce));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _hashTypedDataV4(structHash));
        return abi.encodePacked(r, s, v);
    }

    function _batch(
        SubVoting.VoteRecord memory record,
        address user,
        uint256 nonce,
        uint256 pk
    ) internal view returns (SubVoting.UserVoteBatch[] memory) {
        SubVoting.VoteRecord[] memory records = new SubVoting.VoteRecord[](1);
        records[0] = record;
        SubVoting.UserVoteBatch[] memory batches = new SubVoting.UserVoteBatch[](1);
        batches[0] = SubVoting.UserVoteBatch({
            records: records,
            userBatchSig: SubVoting.UserBatchSig({
                user: user,
                userNonce: nonce,
                signature: _signUser(pk, records, nonce)
            })
        });
        return batches;
    }

    // ── HIGH-1: votingAmt 상한 ───────────────────────────────────────────

    function test_Fixed_MaxVotingAmtRejectedNoDoS() public {
        SubVoting.UserVoteBatch[] memory attackBatch = _batch(
            _record(1, type(uint256).max, 1),
            attacker,
            1,
            attackerPk
        );
        // 서명을 미리 계산: expectRevert 직후 domainSeparator staticcall이 잡히는 것 방지
        bytes memory attackSig = _signBatch(executorPrivateKey, 1);
        vm.expectRevert(SubVoting.NoSuccessfulUser.selector);
        voting.submitMultiUserBatch(attackBatch, 1, attackSig);

        assertEq(voting.getQuestionTotalVotes(1, 1), 0, unicode"공격 레코드는 저장되지 않아야 함");

        SubVoting.UserVoteBatch[] memory ok = _batch(
            _record(1, 100, 2),
            victim,
            1,
            victimPk
        );
        voting.submitMultiUserBatch(ok, 2, _signBatch(executorPrivateKey, 2));
        assertEq(voting.getQuestionTotalVotes(1, 1), 100, unicode"정상 투표는 처리되어야 함");
    }

    function test_Fixed_BoundaryMaxVotingAmt() public {
        SubVoting.UserVoteBatch[] memory atCap = _batch(
            _record(1, voting.MAX_VOTING_AMT(), 1),
            attacker,
            1,
            attackerPk
        );
        voting.submitMultiUserBatch(atCap, 1, _signBatch(executorPrivateKey, 1));
        assertEq(voting.getQuestionTotalVotes(1, 1), voting.MAX_VOTING_AMT());

        SubVoting.UserVoteBatch[] memory overCap = _batch(
            _record(1, voting.MAX_VOTING_AMT() + 1, 2),
            victim,
            1,
            victimPk
        );
        bytes memory overSig = _signBatch(executorPrivateKey, 2);
        vm.expectRevert(SubVoting.NoSuccessfulUser.selector);
        voting.submitMultiUserBatch(overCap, 2, overSig);
    }

    // ── HIGH-2: 제출 권한 제한 ───────────────────────────────────────────

    function test_Fixed_ThirdPartyCannotFrontRun() public {
        SubVoting.UserVoteBatch[] memory batch = _batch(
            _record(1, 100, 1),
            victim,
            1,
            victimPk
        );
        bytes memory sig = _signBatch(executorPrivateKey, 1);

        vm.prank(attacker);
        vm.expectRevert(SubVoting.NotOwnerOrExecutor.selector);
        voting.submitMultiUserBatch(batch, 1, sig);

        vm.prank(executorSigner);
        voting.submitMultiUserBatch(batch, 1, sig);
        assertEq(voting.getQuestionTotalVotes(1, 1), 100);
    }
}

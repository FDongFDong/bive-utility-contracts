// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Boosting} from "../src/vote/Boosting.sol";

/**
 * Boosting 보안 회귀 테스트
 * - HIGH-1: amt 상한(MAX_BOOST_AMT)으로 집계 오버플로우 DoS 차단
 * - HIGH-2: submitBoostBatch 제출 권한을 executor/owner로 제한 (front-run 차단)
 *
 * 서명 헬퍼는 Boosting.t.sol 과 동일 로직을 복제한다 (독립 실행용).
 */
contract BoostingSecurityTest is Test {
    Boosting public boosting;

    address public owner;
    uint256 public executorPrivateKey = 0x4444;
    address public executorSigner;

    uint256 public attackerPk = 0xA11CE;
    uint256 public victimPk = 0xB0B;
    address public attacker;
    address public victim;

    bytes32 private constant BOOST_RECORD_TYPEHASH =
        keccak256(
            "BoostRecord(uint256 timestamp,uint256 missionId,uint256 boostingId,uint256 optionId,uint8 boostingWith,uint256 amt,address user)"
        );
    bytes32 private constant USER_SIG_TYPEHASH =
        keccak256("UserSig(address user,uint256 userNonce,bytes32 recordHash)");
    bytes32 private constant BATCH_TYPEHASH =
        keccak256("Batch(uint256 batchNonce)");

    function setUp() public {
        owner = address(this);
        executorSigner = vm.addr(executorPrivateKey);
        attacker = vm.addr(attackerPk);
        victim = vm.addr(victimPk);

        boosting = new Boosting(owner);
        boosting.setExecutorSigner(executorSigner);
        boosting.setArtist(1, 1, "Artist1", true);
    }

    // ── 서명 헬퍼 ────────────────────────────────────────────────────────

    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19\x01", boosting.domainSeparator(), structHash)
            );
    }

    function _record(
        uint256 optionId,
        uint8 boostingWith,
        uint256 amt,
        uint256 recordId
    ) internal view returns (Boosting.BoostRecord memory) {
        return
            Boosting.BoostRecord({
                recordId: recordId,
                timestamp: block.timestamp,
                missionId: 1,
                boostingId: 1,
                userId: "poc",
                optionId: optionId,
                boostingWith: boostingWith,
                amt: amt
            });
    }

    function _hashRecord(
        Boosting.BoostRecord memory r,
        address user
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    BOOST_RECORD_TYPEHASH,
                    r.timestamp,
                    r.missionId,
                    r.boostingId,
                    r.optionId,
                    r.boostingWith,
                    r.amt,
                    user
                )
            );
    }

    function _signUser(
        uint256 pk,
        Boosting.BoostRecord memory record,
        uint256 nonce
    ) internal view returns (bytes memory) {
        bytes32 recordHash = _hashRecord(record, vm.addr(pk));
        bytes32 structHash = keccak256(
            abi.encode(USER_SIG_TYPEHASH, vm.addr(pk), nonce, recordHash)
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
        Boosting.BoostRecord memory record,
        address user,
        uint256 nonce,
        uint256 pk
    ) internal view returns (Boosting.UserBoostBatch[] memory) {
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = Boosting.UserBoostBatch({
            record: record,
            userSig: Boosting.UserSig({
                user: user,
                userNonce: nonce,
                signature: _signUser(pk, record, nonce)
            })
        });
        return batches;
    }

    // ── HIGH-1: amt 상한 ─────────────────────────────────────────────────

    /// @notice max amt 부스팅은 soft-fail(REASON_AMOUNT_TOO_LARGE)로 거부되고,
    ///         집계가 오염되지 않으며, 이후 정상 부스팅이 DoS 없이 처리된다.
    function test_Fixed_MaxAmtRejectedNoDoS() public {
        // 공격 시도: amt = max (단일 유저 배치 → 성공자 0 → NoSuccessfulUser revert)
        Boosting.UserBoostBatch[] memory attackBatch = _batch(
            _record(1, 0, type(uint256).max, 1),
            attacker,
            1,
            attackerPk
        );
        // 서명을 미리 계산: expectRevert 직후 domainSeparator staticcall이 잡히는 것 방지
        bytes memory attackSig = _signBatch(executorPrivateKey, 1);
        vm.expectRevert(Boosting.NoSuccessfulUser.selector);
        boosting.submitBoostBatch(attackBatch, 1, attackSig);

        // 집계 오염 없음
        assertEq(boosting.artistTotalAmt(1, 1), 0, unicode"공격 레코드는 저장되지 않아야 함");

        // 정상 부스팅은 DoS 없이 성공
        Boosting.UserBoostBatch[] memory ok = _batch(
            _record(1, 0, 100, 2),
            victim,
            1,
            victimPk
        );
        boosting.submitBoostBatch(ok, 2, _signBatch(executorPrivateKey, 2));
        assertEq(boosting.artistTotalAmt(1, 1), 100, unicode"정상 부스팅은 처리되어야 함");
    }

    /// @notice 경계값: 상한(MAX_BOOST_AMT)은 허용, 초과분은 거부
    function test_Fixed_BoundaryMaxBoostAmt() public {
        Boosting.UserBoostBatch[] memory atCap = _batch(
            _record(1, 0, boosting.MAX_BOOST_AMT(), 1),
            attacker,
            1,
            attackerPk
        );
        boosting.submitBoostBatch(atCap, 1, _signBatch(executorPrivateKey, 1));
        assertEq(boosting.artistTotalAmt(1, 1), boosting.MAX_BOOST_AMT());

        Boosting.UserBoostBatch[] memory overCap = _batch(
            _record(1, 0, boosting.MAX_BOOST_AMT() + 1, 2),
            victim,
            1,
            victimPk
        );
        bytes memory overSig = _signBatch(executorPrivateKey, 2);
        vm.expectRevert(Boosting.NoSuccessfulUser.selector);
        boosting.submitBoostBatch(overCap, 2, overSig);
    }

    // ── HIGH-2: 제출 권한 제한 ───────────────────────────────────────────

    /// @notice 제3자가 유효한 executorSig를 복사해도 executor/owner 가 아니면 제출 불가
    function test_Fixed_ThirdPartyCannotFrontRun() public {
        Boosting.UserBoostBatch[] memory batch = _batch(
            _record(1, 0, 100, 1),
            victim,
            1,
            victimPk
        );
        bytes memory sig = _signBatch(executorPrivateKey, 1);

        vm.prank(attacker);
        vm.expectRevert(Boosting.NotOwnerOrExecutor.selector);
        boosting.submitBoostBatch(batch, 1, sig);

        // executor 본인은 정상 제출
        vm.prank(executorSigner);
        boosting.submitBoostBatch(batch, 1, sig);
        assertEq(boosting.artistTotalAmt(1, 1), 100);
    }
}

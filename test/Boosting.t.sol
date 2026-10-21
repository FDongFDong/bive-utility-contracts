// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Boosting} from "../src/vote/Boosting.sol";

contract BoostingTest is Test {
    Boosting public boosting;

    address public owner;
    address public executorSigner;
    address public user1;
    address public user2;
    address public user3;

    uint256 public user1PrivateKey;
    uint256 public user2PrivateKey;
    uint256 public user3PrivateKey;
    uint256 public executorPrivateKey;

    // EIP-712 해시 계산용 상수 (컨트랙트에서 제거된 프리뷰 함수 대체)
    bytes32 private constant BOOST_RECORD_TYPEHASH =
        keccak256("BoostRecord(uint256 timestamp,uint256 missionId,uint256 boostingId,uint256 optionId,uint8 boostingWith,uint256 amt,address user)");
    bytes32 private constant USER_SIG_TYPEHASH =
        keccak256("UserSig(address user,uint256 userNonce,bytes32 recordHash)");
    bytes32 private constant BATCH_TYPEHASH =
        keccak256("Batch(uint256 batchNonce)");

    function _isHeavyBoundaryEnabled() internal view returns (bool) {
        return vm.envOr("RUN_HEAVY_BOUNDARY_TESTS", false);
    }

    function setUp() public {
        owner = address(this);

        user1PrivateKey = 0x1111;
        user2PrivateKey = 0x2222;
        user3PrivateKey = 0x3333;
        executorPrivateKey = 0x4444;

        user1 = vm.addr(user1PrivateKey);
        user2 = vm.addr(user2PrivateKey);
        user3 = vm.addr(user3PrivateKey);
        executorSigner = vm.addr(executorPrivateKey);

        boosting = new Boosting(owner);
        boosting.setExecutorSigner(executorSigner);

        // 아티스트 설정 (missionId=1)
        boosting.setArtist(1, 1, "Artist1", true);
        boosting.setArtist(1, 2, "Artist2", true);
        boosting.setArtist(1, 3, "Artist3", true);

        // 부스팅 타입 설정 (0=BP, 1=CELB)
        boosting.setBoostingTypeName(0, "BP");
        boosting.setBoostingTypeName(1, "CELB");
    }

    function _createBoostRecord(
        string memory userId,
        uint256 missionId,
        uint256 boostingId,
        uint256 optionId,
        uint8 boostingWith,
        uint256 amt
    ) internal view returns (Boosting.BoostRecord memory) {
        return Boosting.BoostRecord({
            recordId: 1, // 테스트용 기본값
            timestamp: block.timestamp,
            missionId: missionId,
            boostingId: boostingId,
            userId: userId,
            optionId: optionId,
            boostingWith: boostingWith,
            amt: amt
        });
    }

    // 테스트용 해시 함수들 (컨트랙트에서 제거된 프리뷰 함수 대체)
    function _hashBoostRecord(Boosting.BoostRecord memory record, address user) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            BOOST_RECORD_TYPEHASH,
            record.timestamp,
            record.missionId,
            record.boostingId,
            record.optionId,
            record.boostingWith,
            record.amt,
            user
        ));
    }

    function _hashUserSig(address user, uint256 nonce_, bytes32 recordHash) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(USER_SIG_TYPEHASH, user, nonce_, recordHash));
        return _hashTypedDataV4(structHash);
    }

    function _hashBatch(uint256 batchNonce) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(BATCH_TYPEHASH, batchNonce));
        return _hashTypedDataV4(structHash);
    }

    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", boosting.domainSeparator(), structHash));
    }

    function _signUserSig(
        uint256 privateKey,
        Boosting.BoostRecord memory record,
        uint256 userNonce
    ) internal view returns (bytes memory) {
        address user = vm.addr(privateKey);
        bytes32 recordHash = _hashBoostRecord(record, user);
        bytes32 digest = _hashUserSig(user, userNonce, recordHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signBatchSig(
        uint256 privateKey,
        uint256 batchNonce
    ) internal view returns (bytes memory) {
        bytes32 digest = _hashBatch(batchNonce);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _createUserBoostBatch(
        uint256 privateKey,
        address userAddress,
        string memory userId,
        uint256 missionId,
        uint256 boostingId,
        uint256 optionId,
        uint8 boostingWith,
        uint256 amt,
        uint256 userNonce
    ) internal view returns (Boosting.UserBoostBatch memory) {
        Boosting.BoostRecord memory record = _createBoostRecord(
            userId, missionId, boostingId, optionId, boostingWith, amt
        );
        return Boosting.UserBoostBatch({
            record: record,
            userSig: Boosting.UserSig({
                user: userAddress,
                userNonce: userNonce,
                signature: _signUserSig(privateKey, record, userNonce)
            })
        });
    }

    // ========================================
    // 기본 기능 테스트
    // ========================================

    function test_Deployment() public view {
        assertEq(boosting.owner(), owner);
        assertEq(boosting.executorSigner(), executorSigner);
        assertEq(boosting.CHAIN_ID(), block.chainid);
    }

    function test_MaxRecordsPerBatch_Constant() public view {
        assertEq(boosting.MAX_RECORDS_PER_BATCH(), 2000);
    }

    function test_SetExecutorSigner() public {
        address newExecutor = address(0x5555);
        boosting.setExecutorSigner(newExecutor);
        assertEq(boosting.executorSigner(), newExecutor);
    }

    function test_RevertWhen_SetExecutorSignerZeroAddress() public {
        vm.expectRevert(Boosting.ZeroAddress.selector);
        boosting.setExecutorSigner(address(0));
    }

    function test_RevertWhen_SetExecutorSignerNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        boosting.setExecutorSigner(address(0x5555));
    }

    // ========================================
    // 아티스트/부스팅 타입 설정 테스트
    // ========================================

    function test_SetArtist() public {
        boosting.setArtist(2, 1, "NewArtist", true);
        assertEq(boosting.artistName(2, 1), "NewArtist");
        assertTrue(boosting.allowedArtist(2, 1));
    }

    function test_SetBoostingTypeName() public {
        boosting.setBoostingTypeName(0, "NewType");
        assertEq(boosting.boostingTypeName(0), "NewType");
    }

    function test_RevertWhen_SetBoostingTypeNameInvalid() public {
        vm.expectRevert(abi.encodeWithSelector(Boosting.InvalidBoostType.selector, 2));
        boosting.setBoostingTypeName(2, "Invalid");
    }

    // ========================================
    // 부스팅 제출 성공 케이스
    // ========================================

    function test_SubmitSingleUserBoost() public {
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = _createUserBoostBatch(user1PrivateKey, user1, "user1", 1, 1, 1, 0, 100, 0);

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);

        boosting.submitBoostBatch(batches, 0, executorSig);

        // 검증
        assertEq(boosting.boostCount(1, 1), 1);
        assertEq(boosting.boostCountByMission(1), 1);
        assertTrue(boosting.usedUserNonces(user1, 0));  // nonce 0이 사용됨
        assertTrue(boosting.usedBatchNonces(executorSigner, 0));

        // 아티스트 집계 검증
        assertEq(boosting.artistTotalAmt(1, 1), 100);
    }

    function test_SubmitMultipleUsersBoosts() public {
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](3);
        batches[0] = _createUserBoostBatch(user1PrivateKey, user1, "user1", 1, 1, 1, 0, 100, 0);
        batches[1] = _createUserBoostBatch(user2PrivateKey, user2, "user2", 1, 2, 2, 1, 200, 0);
        batches[2] = _createUserBoostBatch(user3PrivateKey, user3, "user3", 1, 3, 3, 0, 150, 0);

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);

        boosting.submitBoostBatch(batches, 0, executorSig);

        // 검증
        assertEq(boosting.boostCountByMission(1), 3);
        assertTrue(boosting.usedUserNonces(user1, 0));  // 각 유저 nonce 0이 사용됨
        assertTrue(boosting.usedUserNonces(user2, 0));
        assertTrue(boosting.usedUserNonces(user3, 0));
        assertTrue(boosting.usedBatchNonces(executorSigner, 0));

        // 아티스트별 집계 검증
        assertEq(boosting.artistTotalAmt(1, 1), 100);
        assertEq(boosting.artistTotalAmt(1, 2), 200);
        assertEq(boosting.artistTotalAmt(1, 3), 150);
    }

    function test_NonceNotConsumedWhenRecordFailsButOthersSucceed() public {
        // user1: amt=0 이라 저장 실패, user2: 정상 저장
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](2);
        batches[0] = _createUserBoostBatch(user1PrivateKey, user1, "user1", 1, 1, 1, 0, 0, 0);
        batches[1] = _createUserBoostBatch(user2PrivateKey, user2, "user2", 1, 2, 2, 0, 200, 0);

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);
        boosting.submitBoostBatch(batches, 0, executorSig);

        // user1은 저장 실패했으므로 nonce 미소비, user2만 nonce 소비
        assertFalse(boosting.usedUserNonces(user1, 0));
        assertTrue(boosting.usedUserNonces(user2, 0));

        // 집계는 user2만 반영
        assertEq(boosting.artistTotalAmt(1, 1), 0);
        assertEq(boosting.artistTotalAmt(1, 2), 200);
    }

    function test_SubmitMixedUsersAndBoosts() public {
        // 실제 시나리오: 다양한 사용자의 다양한 부스팅
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](5);
        batches[0] = _createUserBoostBatch(user1PrivateKey, user1, "alice", 1, 1, 1, 0, 100, 0);
        batches[1] = _createUserBoostBatch(user2PrivateKey, user2, "bob", 1, 2, 2, 1, 200, 0);
        batches[2] = _createUserBoostBatch(user3PrivateKey, user3, "charlie", 1, 3, 3, 0, 150, 0);
        batches[3] = _createUserBoostBatch(user1PrivateKey, user1, "alice", 1, 4, 1, 1, 80, 1);
        batches[4] = _createUserBoostBatch(user2PrivateKey, user2, "bob", 1, 5, 2, 0, 120, 1);

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);

        boosting.submitBoostBatch(batches, 0, executorSig);

        // 검증
        assertEq(boosting.boostCountByMission(1), 5);
        assertTrue(boosting.usedUserNonces(user1, 0));  // user1은 nonce 0, 1 사용
        assertTrue(boosting.usedUserNonces(user1, 1));
        assertTrue(boosting.usedUserNonces(user2, 0));  // user2도 nonce 0, 1 사용
        assertTrue(boosting.usedUserNonces(user2, 1));
        assertTrue(boosting.usedUserNonces(user3, 0));  // user3는 nonce 0만 사용

        // 아티스트별 집계 (user1: 100+80=180, user2: 200+120=320, user3: 150)
        assertEq(boosting.artistTotalAmt(1, 1), 180); // artist1
        assertEq(boosting.artistTotalAmt(1, 2), 320); // artist2
        assertEq(boosting.artistTotalAmt(1, 3), 150); // artist3
    }

    // ========================================
    // 서명 검증 실패 케이스
    // ========================================

    function test_RevertWhen_InvalidExecutorSignature() public {
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = _createUserBoostBatch(user1PrivateKey, user1, "user1", 1, 1, 1, 0, 100, 0);

        // 잘못된 private key로 서명
        bytes memory wrongExecutorSig = _signBatchSig(user1PrivateKey, 0);

        vm.expectRevert(Boosting.InvalidSignature.selector);
        boosting.submitBoostBatch(batches, 0, wrongExecutorSig);
    }

    function test_RevertWhen_MalformedExecutorSignature_DoesNotConsumeNonces()
        public
    {
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = _createUserBoostBatch(
            user1PrivateKey,
            user1,
            "user1",
            1,
            1,
            1,
            0,
            100,
            0
        );

        vm.expectRevert(Boosting.InvalidSignature.selector);
        boosting.submitBoostBatch(batches, 777, hex"1234");

        assertFalse(boosting.usedBatchNonces(executorSigner, 777));
        assertFalse(boosting.usedUserNonces(user1, 0));
    }

    function test_RevertWhen_InvalidUserSignature() public {
        // 잘못된 서명으로 배치 생성 (user2 private key로 user1의 레코드 서명)
        Boosting.BoostRecord memory record = _createBoostRecord("user1", 1, 1, 1, 0, 100);
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = Boosting.UserBoostBatch({
            record: record,
            userSig: Boosting.UserSig({
                user: user1,
                userNonce: 0,
                signature: _signUserSig(user2PrivateKey, record, 0) // 잘못된 private key
            })
        });

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);

        // Soft-fail: 유저 서명 검증 실패 → 해당 유저만 실패 → 모든 유저 실패 시 NoSuccessfulUser
        vm.expectRevert(Boosting.NoSuccessfulUser.selector);
        boosting.submitBoostBatch(batches, 0, executorSig);
    }

    function test_SoftFailWhen_MalformedUserSignature() public {
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](2);
        batches[0] = _createUserBoostBatch(
            user1PrivateKey,
            user1,
            "user1",
            1,
            1,
            1,
            0,
            100,
            0
        );
        batches[0].userSig.signature = hex"1234";
        batches[1] = _createUserBoostBatch(
            user2PrivateKey,
            user2,
            "user2",
            1,
            2,
            2,
            0,
            200,
            0
        );

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);
        boosting.submitBoostBatch(batches, 0, executorSig);

        assertFalse(boosting.usedUserNonces(user1, 0));
        assertTrue(boosting.usedUserNonces(user2, 0));
        assertEq(boosting.artistTotalAmt(1, 1), 0);
        assertEq(boosting.artistTotalAmt(1, 2), 200);
    }

    function testFuzz_SoftFailWhen_MalformedUserSignatureLength(
        uint8 badLen
    ) public {
        vm.assume(badLen != 65);

        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](2);
        batches[0] = _createUserBoostBatch(
            user1PrivateKey,
            user1,
            "user1",
            1,
            1,
            1,
            0,
            100,
            0
        );
        batches[0].userSig.signature = new bytes(badLen);
        batches[1] = _createUserBoostBatch(
            user2PrivateKey,
            user2,
            "user2",
            1,
            2,
            2,
            0,
            200,
            0
        );

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);
        boosting.submitBoostBatch(batches, 0, executorSig);

        assertFalse(boosting.usedUserNonces(user1, 0));
        assertTrue(boosting.usedUserNonces(user2, 0));
        assertEq(boosting.artistTotalAmt(1, 1), 0);
        assertEq(boosting.artistTotalAmt(1, 2), 200);
    }

    function test_RevertWhen_AllUsersMalformedSignature_BatchNonceRollsBack()
        public
    {
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = _createUserBoostBatch(
            user1PrivateKey,
            user1,
            "user1",
            1,
            1,
            1,
            0,
            100,
            0
        );
        batches[0].userSig.signature = hex"1234";

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 333);
        vm.expectRevert(Boosting.NoSuccessfulUser.selector);
        boosting.submitBoostBatch(batches, 333, executorSig);

        assertFalse(boosting.usedBatchNonces(executorSigner, 333));
        assertFalse(boosting.usedUserNonces(user1, 0));
    }

    function test_RevertWhen_UserNonceReused_NoSuccessfulUser() public {
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = _createUserBoostBatch(user1PrivateKey, user1, "user1", 1, 1, 1, 0, 100, 0);

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);

        // 첫 번째 제출 성공
        boosting.submitBoostBatch(batches, 0, executorSig);

        // 두 번째 제출 실패 (같은 user nonce - 순차 방식에서는 nonce 0은 이미 사용되어 expected는 1)
        batches[0] = _createUserBoostBatch(user1PrivateKey, user1, "user1", 1, 2, 2, 1, 150, 0); // nonce 0 재사용 시도
        bytes memory executorSig2 = _signBatchSig(executorPrivateKey, 1);

        // Soft-fail로 인해 해당 유저만 실패, 모든 유저 실패 시 NoSuccessfulUser
        vm.expectRevert(Boosting.NoSuccessfulUser.selector);
        boosting.submitBoostBatch(batches, 1, executorSig2);
    }

    function test_RevertWhen_BatchNonceAlreadyUsed() public {
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = _createUserBoostBatch(user1PrivateKey, user1, "user1", 1, 1, 1, 0, 100, 0);

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);

        // 첫 번째 제출 성공
        boosting.submitBoostBatch(batches, 0, executorSig);

        // 두 번째 제출 실패 (같은 batch nonce)
        batches[0] = _createUserBoostBatch(user1PrivateKey, user1, "user1", 1, 2, 2, 1, 150, 1);
        bytes memory executorSig2 = _signBatchSig(executorPrivateKey, 0); // 같은 batch nonce

        vm.expectRevert(Boosting.BatchNonceAlreadyUsed.selector);
        boosting.submitBoostBatch(batches, 0, executorSig2);
    }

    // ========================================
    // 데이터 검증 실패 케이스
    // ========================================

    function test_RevertWhen_ArtistNotAllowed_NoSuccessfulUser() public {
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = _createUserBoostBatch(user1PrivateKey, user1, "user1", 1, 1, 99, 0, 100, 0); // optionId 99 not allowed

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);

        // Soft-fail: per-record 검증 실패 → 해당 레코드만 실패 → 모든 유저 실패 시 NoSuccessfulUser
        vm.expectRevert(Boosting.NoSuccessfulUser.selector);
        boosting.submitBoostBatch(batches, 0, executorSig);
    }

    function test_RevertWhen_InvalidBoostType() public {
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = _createUserBoostBatch(user1PrivateKey, user1, "user1", 1, 1, 1, 5, 100, 0); // boostingWith 5 invalid

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);

        // Soft-fail: per-record 검증 실패 → 해당 레코드만 실패 → 모든 유저 실패 시 NoSuccessfulUser
        vm.expectRevert(Boosting.NoSuccessfulUser.selector);
        boosting.submitBoostBatch(batches, 0, executorSig);
    }

    function test_TwoUsersSameRecordHash_BothStored() public {
        // recordHash가 user를 포함하므로, 두 유저가 동일한 입력값을 제출해도 둘 다 저장되어야 한다.
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](2);

        // 동일한 timestamp를 만들기 위해 같은 블록 타임에서 생성
        batches[0] = _createUserBoostBatch(user1PrivateKey, user1, "user1", 1, 1, 1, 0, 100, 0);
        batches[1] = _createUserBoostBatch(user2PrivateKey, user2, "user2", 1, 1, 1, 0, 100, 0);

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);
        boosting.submitBoostBatch(batches, 0, executorSig);

        // 둘 다 반영되어 총 200
        assertEq(boosting.artistTotalAmt(1, 1), 200);
        assertEq(boosting.boostCountByMission(1), 2);
    }

    // LengthMismatch 테스트 제거 - 새로운 구조에서는 record와 userSig가 구조체로 묶여있어 불일치 불가능

    // ========================================
    // 0 포인트 부스팅 스킵 테스트
    // ========================================

    function test_SkipZeroAmountBoost() public {
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](2);
        batches[0] = _createUserBoostBatch(user1PrivateKey, user1, "user1", 1, 1, 1, 0, 0, 0); // 0 포인트 - 스킵됨
        batches[1] = _createUserBoostBatch(user2PrivateKey, user2, "user2", 1, 2, 1, 0, 100, 0);

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);

        boosting.submitBoostBatch(batches, 0, executorSig);

        // 집계 검증 - 0 포인트 부스팅은 스킵되어 100만 집계됨
        assertEq(boosting.artistTotalAmt(1, 1), 100);
        assertEq(boosting.boostCountByMission(1), 1); // 0 포인트는 카운트 안됨
    }

    // ========================================
    // View 함수 테스트
    // ========================================

    function test_ArtistTotalAmt() public {
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](3);
        batches[0] = _createUserBoostBatch(user1PrivateKey, user1, "user1", 1, 1, 1, 0, 100, 0);
        batches[1] = _createUserBoostBatch(user2PrivateKey, user2, "user2", 1, 2, 1, 1, 200, 0);
        batches[2] = _createUserBoostBatch(user3PrivateKey, user3, "user3", 1, 3, 2, 0, 150, 0);

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);
        boosting.submitBoostBatch(batches, 0, executorSig);

        // 아티스트별 총 amt 확인 (public 매핑 직접 접근)
        assertEq(boosting.artistTotalAmt(1, 1), 300); // user1 + user2
        assertEq(boosting.artistTotalAmt(1, 2), 150); // user3
    }

    function test_ArtistInfo() public {
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = _createUserBoostBatch(user1PrivateKey, user1, "user1", 1, 1, 1, 0, 100, 0);

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);
        boosting.submitBoostBatch(batches, 0, executorSig);

        // 아티스트 정보 조회 (public 매핑 직접 접근)
        assertEq(boosting.artistName(1, 1), "Artist1");
        assertTrue(boosting.allowedArtist(1, 1));
        assertEq(boosting.artistTotalAmt(1, 1), 100);
    }

    function test_GetBoostSummariesByBoostingId() public {
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](2);
        batches[0] = _createUserBoostBatch(user1PrivateKey, user1, "user1", 1, 1, 1, 0, 100, 0);
        batches[1] = _createUserBoostBatch(user2PrivateKey, user2, "user2", 1, 1, 2, 1, 200, 0); // 같은 boostingId

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);
        boosting.submitBoostBatch(batches, 0, executorSig);

        // boostingId 1로 조회
        Boosting.BoostRecordSummary[] memory summaries = boosting.getBoostSummariesByBoostingId(1, 1);
        assertEq(summaries.length, 2);
        assertEq(summaries[0].userId, "user1");
        assertEq(summaries[0].boostingFor, "Artist1");
        assertEq(summaries[0].boostingWith, "BP");
        assertEq(summaries[1].userId, "user2");
        assertEq(summaries[1].boostingFor, "Artist2");
        assertEq(summaries[1].boostingWith, "CELB");
    }

    function test_DomainSeparator() public view {
        bytes32 separator = boosting.domainSeparator();
        assertTrue(separator != bytes32(0));
    }

    function test_GetBoostAggregates() public {
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](3);
        // BP 타입 부스팅 (boostingWith = 0)
        batches[0] = _createUserBoostBatch(user1PrivateKey, user1, "user1", 1, 1, 1, 0, 100, 0);
        batches[1] = _createUserBoostBatch(user2PrivateKey, user2, "user2", 1, 2, 1, 0, 200, 0);
        // CELB 타입 부스팅 (boostingWith = 1)
        batches[2] = _createUserBoostBatch(user3PrivateKey, user3, "user3", 1, 3, 1, 1, 150, 0);

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);
        boosting.submitBoostBatch(batches, 0, executorSig);

        // 집계 확인
        (uint256 bpAmt, uint256 celbAmt, uint256 total) = boosting.getBoostAggregates(1, 1);
        assertEq(bpAmt, 300); // user1 + user2
        assertEq(celbAmt, 150); // user3
        assertEq(total, 450);
    }

    // ========================================
    // 순차 배치 테스트
    // ========================================

    function test_SequentialBatches() public {
        // 순차적인 여러 배치 제출
        for (uint256 batchIdx = 0; batchIdx < 3; batchIdx++) {
            Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](2);
            batches[0] = _createUserBoostBatch(
                user1PrivateKey, user1, "user1", 1, batchIdx * 2 + 1, 1, 0, 100, batchIdx
            );
            batches[1] = _createUserBoostBatch(
                user2PrivateKey, user2, "user2", 1, batchIdx * 2 + 2, 2, 1, 200, batchIdx
            );

            bytes memory executorSig = _signBatchSig(executorPrivateKey, batchIdx);
            boosting.submitBoostBatch(batches, batchIdx, executorSig);
        }

        // 총 6건 (3배치 * 2건)
        assertEq(boosting.boostCountByMission(1), 6);

        // 아티스트별 집계
        assertEq(boosting.artistTotalAmt(1, 1), 300); // user1: 100 * 3
        assertEq(boosting.artistTotalAmt(1, 2), 600); // user2: 200 * 3
    }

    // ========================================
    // 추가 권한 테스트
    // ========================================

    function test_RevertWhen_SetArtistNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        boosting.setArtist(1, 1, "Unauthorized", true);
    }

    function test_RevertWhen_SetBoostingTypeNameNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        boosting.setBoostingTypeName(0, "Unauthorized");
    }

    // ========================================
    // 경계값 테스트
    // ========================================

    /// @notice StringTooLong은 이제 soft-fail로 처리됨
    ///         단일 유저가 StringTooLong으로 실패하면 NoSuccessfulUser 발생
    function test_SoftFail_StringTooLong_AllUsersFail() public {
        // 101자 문자열 생성 (MAX_STRING_LENGTH = 100 초과)
        bytes memory longString = new bytes(101);
        for (uint256 i = 0; i < 101; i++) {
            longString[i] = "a";
        }
        string memory tooLongUserId = string(longString);

        // 레코드 직접 생성 (preview 함수 호출을 피하기 위해)
        Boosting.BoostRecord memory record = Boosting.BoostRecord({
            recordId: 1,
            timestamp: block.timestamp,
            missionId: 1,
            boostingId: 1,
            userId: tooLongUserId,
            optionId: 1,
            boostingWith: 0,
            amt: 100
        });

        // 더미 서명 생성
        bytes memory dummySig = new bytes(65);

        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = Boosting.UserBoostBatch({
            record: record,
            userSig: Boosting.UserSig({
                user: user1,
                userNonce: 0,
                signature: dummySig
            })
        });

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);

        // StringTooLong은 soft-fail이므로 유저가 실패하고, 다른 유저가 없으면 NoSuccessfulUser
        vm.expectRevert(Boosting.NoSuccessfulUser.selector);
        boosting.submitBoostBatch(batches, 0, executorSig);
    }

    // ========================================
    // 상태 전이 테스트
    // ========================================

    function test_ArtistDisabledAfterBoosting() public {
        // 먼저 성공적인 부스팅
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = _createUserBoostBatch(
            user1PrivateKey, user1, "user1", 1, 1, 1, 0, 100, 0
        );

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);
        boosting.submitBoostBatch(batches, 0, executorSig);

        // 아티스트 비활성화
        boosting.setArtist(1, 1, "Artist1", false);

        // 비활성화된 아티스트에 부스팅 시도
        Boosting.UserBoostBatch[] memory batches2 = new Boosting.UserBoostBatch[](1);
        batches2[0] = _createUserBoostBatch(
            user2PrivateKey, user2, "user2", 1, 2, 1, 0, 200, 0
        );

        bytes memory executorSig2 = _signBatchSig(executorPrivateKey, 1);

        // Soft-fail: 아티스트 비활성화로 per-record 검증 실패 → 모든 유저 실패 시 NoSuccessfulUser
        vm.expectRevert(Boosting.NoSuccessfulUser.selector);
        boosting.submitBoostBatch(batches2, 1, executorSig2);
    }

    function test_ArtistReEnabled() public {
        // 아티스트 비활성화
        boosting.setArtist(1, 1, "Artist1", false);

        // 아티스트 재활성화
        boosting.setArtist(1, 1, "Artist1", true);

        // 재활성화된 아티스트에 부스팅 성공
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = _createUserBoostBatch(
            user1PrivateKey, user1, "user1", 1, 1, 1, 0, 100, 0
        );

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);
        boosting.submitBoostBatch(batches, 0, executorSig);

        assertTrue(boosting.usedUserNonces(user1, 0));  // nonce 0이 사용됨
    }

    function test_UpdateArtistName() public {
        string memory newName = "UpdatedArtist";
        boosting.setArtist(1, 1, newName, true);
        assertEq(boosting.artistName(1, 1), newName);
    }

    // ========================================
    // ExecutorSigner 관리 테스트
    // ========================================

    function test_ExecutorSignerChangeInvalidatesOldNonces() public {
        // 이전 executor로 첫 부스팅
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = _createUserBoostBatch(
            user1PrivateKey, user1, "user1", 1, 1, 1, 0, 100, 0
        );

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);
        boosting.submitBoostBatch(batches, 0, executorSig);

        // executor 변경
        uint256 newExecutorPrivateKey = 0x5555;
        address newExecutor = vm.addr(newExecutorPrivateKey);
        boosting.setExecutorSigner(newExecutor);

        // 새 executor로 부스팅 성공 (batchNonce 0 사용 가능 - 새 executor이므로)
        Boosting.UserBoostBatch[] memory batches2 = new Boosting.UserBoostBatch[](1);
        batches2[0] = _createUserBoostBatch(
            user2PrivateKey, user2, "user2", 1, 2, 2, 0, 200, 0
        );

        bytes32 digest2 = _hashBatch(0);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(newExecutorPrivateKey, digest2);
        bytes memory newExecutorSig = abi.encodePacked(r2, s2, v2);

        boosting.submitBoostBatch(batches2, 0, newExecutorSig);
        assertTrue(boosting.usedUserNonces(user2, 0));  // nonce 0이 사용됨
    }

    // ========================================
    // 중복 레코드 테스트
    // ========================================

    function test_DuplicateRecordSkipped() public {
        // 첫 부스팅 성공
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = _createUserBoostBatch(
            user1PrivateKey, user1, "user1", 1, 1, 1, 0, 100, 0
        );

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);
        boosting.submitBoostBatch(batches, 0, executorSig);

        // 집계 확인
        assertEq(boosting.artistTotalAmt(1, 1), 100);

        // 동일한 user1이 nonce 0으로 다시 제출 시도 - 이미 사용됨
        Boosting.UserBoostBatch[] memory batches2 = new Boosting.UserBoostBatch[](1);
        batches2[0] = _createUserBoostBatch(
            user1PrivateKey, user1, "user1", 1, 2, 1, 0, 200, 0
        );

        bytes memory executorSig2 = _signBatchSig(executorPrivateKey, 1);

        // 중복 nonce 사용 시 모든 유저 실패 → NoSuccessfulUser
        vm.expectRevert(Boosting.NoSuccessfulUser.selector);
        boosting.submitBoostBatch(batches2, 1, executorSig2);
    }

    function test_RevertWhen_SetArtistInvalidId() public {
        vm.expectRevert(
            abi.encodeWithSelector(Boosting.InvalidOptionId.selector, 0)
        );
        boosting.setArtist(1, 0, "Invalid", true);
    }

    function test_RevertWhen_SetArtistEmptyName() public {
        vm.expectRevert(Boosting.EmptyText.selector);
        boosting.setArtist(1, 1, "", true);
    }

    function test_RevertWhen_SetBoostingTypeNameEmptyName() public {
        vm.expectRevert(Boosting.EmptyText.selector);
        boosting.setBoostingTypeName(0, "");
    }

    // ╔═══════════════════════════════════════════════════════════════════════════╗
    // ║              ERC-1271 스마트 컨트랙트 지갑 서명 테스트                         ║
    // ╚═══════════════════════════════════════════════════════════════════════════╝

    function test_ERC1271_SmartWalletSignature_Success() public {
        // ERC1271Mock 배포 (user1을 signer로 설정)
        ERC1271Mock smartWallet = new ERC1271Mock(user1);

        Boosting.BoostRecord memory record = _createBoostRecord(
            "smartWalletUser", 1, 1, 1, 0, 100
        );

        // 스마트 지갑 주소로 해시 계산 (기존 헬퍼 함수 사용)
        bytes32 recordHash = _hashBoostRecord(record, address(smartWallet));
        bytes32 digest = _hashUserSig(address(smartWallet), 0, recordHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = Boosting.UserBoostBatch({
            record: record,
            userSig: Boosting.UserSig({
                user: address(smartWallet),
                userNonce: 0,
                signature: signature
            })
        });

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);
        boosting.submitBoostBatch(batches, 0, executorSig);

        assertTrue(boosting.usedUserNonces(address(smartWallet), 0));
        assertEq(boosting.artistTotalAmt(1, 1), 100);
    }

    function test_ERC1271_SmartWalletSignature_Invalid_Fail() public {
        ERC1271Mock smartWallet = new ERC1271Mock(user1);
        smartWallet.setReturnValid(false);

        Boosting.BoostRecord memory record = _createBoostRecord(
            "smartWalletUser", 1, 1, 1, 0, 100
        );

        // 스마트 지갑 주소로 해시 계산 (기존 헬퍼 함수 사용)
        bytes32 recordHash = _hashBoostRecord(record, address(smartWallet));
        bytes32 digest = _hashUserSig(address(smartWallet), 0, recordHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 유효한 유저도 추가 (NoSuccessfulUser 방지)
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](2);
        batches[0] = Boosting.UserBoostBatch({
            record: record,
            userSig: Boosting.UserSig({
                user: address(smartWallet),
                userNonce: 0,
                signature: signature
            })
        });
        batches[1] = _createUserBoostBatch(
            user2PrivateKey, user2, "user2", 1, 2, 2, 1, 200, 0
        );

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);
        boosting.submitBoostBatch(batches, 0, executorSig);

        assertFalse(boosting.usedUserNonces(address(smartWallet), 0));
        assertTrue(boosting.usedUserNonces(user2, 0));
    }

    // ╔═══════════════════════════════════════════════════════════════════════════╗
    // ║              MAX_RECORDS_PER_BATCH (2000) 경계값 테스트                      ║
    // ╚═══════════════════════════════════════════════════════════════════════════╝

    function test_BatchExact2000Users_Success() public {
        if (!_isHeavyBoundaryEnabled()) return;

        // Boosting은 1:1 방식이므로 유저 수 = 레코드 수
        uint256 userCount = 2000;

        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](userCount);

        for (uint256 u = 0; u < userCount; u++) {
            uint256 userPrivateKey = 0x10000 + u;
            address userAddr = vm.addr(userPrivateKey);

            vm.warp(block.timestamp + 1);

            Boosting.BoostRecord memory record = Boosting.BoostRecord({
                recordId: u + 1,
                timestamp: block.timestamp,
                missionId: 1,
                boostingId: u + 1,
                userId: string(abi.encodePacked("user", vm.toString(u))),
                optionId: 1,
                boostingWith: 0,
                amt: 10
            });

            bytes32 recordHash = _hashBoostRecord(record, userAddr);
            bytes32 userSigDigest = _hashUserSig(userAddr, 0, recordHash);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, userSigDigest);
            bytes memory signature = abi.encodePacked(r, s, v);

            batches[u] = Boosting.UserBoostBatch({
                record: record,
                userSig: Boosting.UserSig({
                    user: userAddr,
                    userNonce: 0,
                    signature: signature
                })
            });
        }

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);
        boosting.submitBoostBatch(batches, 0, executorSig);

        // 집계 확인: 2000 * 10 = 20000
        assertEq(boosting.artistTotalAmt(1, 1), 20000);
    }

    function test_RevertWhen_BatchExceeds2000Users() public {
        if (!_isHeavyBoundaryEnabled()) return;

        uint256 userCount = 2001;

        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](userCount);

        for (uint256 u = 0; u < userCount; u++) {
            uint256 userPrivateKey = 0x10000 + u;
            address userAddr = vm.addr(userPrivateKey);

            vm.warp(block.timestamp + 1);

            Boosting.BoostRecord memory record = Boosting.BoostRecord({
                recordId: u + 1,
                timestamp: block.timestamp,
                missionId: 1,
                boostingId: u + 1,
                userId: string(abi.encodePacked("user", vm.toString(u))),
                optionId: 1,
                boostingWith: 0,
                amt: 10
            });

            bytes32 recordHash = _hashBoostRecord(record, userAddr);
            bytes32 userSigDigest = _hashUserSig(userAddr, 0, recordHash);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, userSigDigest);
            bytes memory signature = abi.encodePacked(r, s, v);

            batches[u] = Boosting.UserBoostBatch({
                record: record,
                userSig: Boosting.UserSig({
                    user: userAddr,
                    userNonce: 0,
                    signature: signature
                })
            });
        }

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);

        vm.expectRevert(Boosting.BatchTooLarge.selector);
        boosting.submitBoostBatch(batches, 0, executorSig);
    }

    // ╔═══════════════════════════════════════════════════════════════════════════╗
    // ║              크로스체인 리플레이 공격 방지 테스트 (BadChain)                   ║
    // ╚═══════════════════════════════════════════════════════════════════════════╝

    function test_RevertWhen_ChainIdMismatch_BadChain() public {
        vm.chainId(999);

        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = _createUserBoostBatch(
            user1PrivateKey, user1, "user1", 1, 1, 1, 0, 100, 0
        );

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);

        vm.expectRevert(Boosting.BadChain.selector);
        boosting.submitBoostBatch(batches, 0, executorSig);
    }

    // ╔═══════════════════════════════════════════════════════════════════════════╗
    // ║              Ownable2Step 2단계 소유권 이전 테스트                            ║
    // ╚═══════════════════════════════════════════════════════════════════════════╝

    function test_Ownable2Step_TransferOwnership() public {
        address newOwner = address(0x9999);

        boosting.transferOwnership(newOwner);
        assertEq(boosting.owner(), owner);
        assertEq(boosting.pendingOwner(), newOwner);

        vm.prank(newOwner);
        boosting.acceptOwnership();

        assertEq(boosting.owner(), newOwner);
        assertEq(boosting.pendingOwner(), address(0));
    }

    function test_Ownable2Step_PendingOwnerCannotCallOnlyOwner() public {
        address newOwner = address(0x9999);
        boosting.transferOwnership(newOwner);

        vm.prank(newOwner);
        vm.expectRevert();
        boosting.setExecutorSigner(address(0x8888));
    }

    function test_Ownable2Step_OnlyPendingOwnerCanAccept() public {
        address newOwner = address(0x9999);
        boosting.transferOwnership(newOwner);

        vm.prank(user1);
        vm.expectRevert();
        boosting.acceptOwnership();
    }

    // ╔═══════════════════════════════════════════════════════════════════════════╗
    // ║              중복 레코드 해시 테스트                                          ║
    // ╚═══════════════════════════════════════════════════════════════════════════╝

    function test_DuplicateRecordHashInSameBatch_SecondFails() public {
        // 동일한 recordHash를 두 번 제출 (두 번째는 실패)
        vm.warp(1000);

        // 동일한 레코드를 두 번 만들려면 timestamp와 기타 필드가 동일해야 함
        // 하지만 서로 다른 유저가 제출하면 recordHash는 다름 (user가 포함되므로)
        // 같은 유저가 같은 레코드를 배치 내에서 두 번 제출하는 케이스는
        // Boosting에서 1:1 방식이므로 배치당 한 레코드만 가능

        // 대신 같은 유저가 동일한 recordHash를 다른 배치에서 제출하는 경우 테스트
        Boosting.UserBoostBatch[] memory batches1 = new Boosting.UserBoostBatch[](1);
        batches1[0] = _createUserBoostBatch(
            user1PrivateKey, user1, "user1", 1, 1, 1, 0, 100, 0
        );

        bytes memory executorSig1 = _signBatchSig(executorPrivateKey, 0);
        boosting.submitBoostBatch(batches1, 0, executorSig1);

        // 같은 레코드 해시로 다시 제출 시도 (nonce는 다름)
        Boosting.BoostRecord memory sameRecord = _createBoostRecord(
            "user1", 1, 1, 1, 0, 100
        );
        vm.warp(1000); // timestamp 동일하게

        // 다른 유저 추가해서 NoSuccessfulUser 방지
        Boosting.UserBoostBatch[] memory batches2 = new Boosting.UserBoostBatch[](2);
        batches2[0] = Boosting.UserBoostBatch({
            record: sameRecord,
            userSig: Boosting.UserSig({
                user: user1,
                userNonce: 1,
                signature: _signUserSig(user1PrivateKey, sameRecord, 1)
            })
        });
        batches2[1] = _createUserBoostBatch(
            user2PrivateKey, user2, "user2", 1, 2, 2, 1, 200, 0
        );

        bytes memory executorSig2 = _signBatchSig(executorPrivateKey, 1);
        boosting.submitBoostBatch(batches2, 1, executorSig2);

        // user1의 중복 레코드는 실패, user2는 성공
        assertFalse(boosting.usedUserNonces(user1, 1)); // nonce는 소비되지 않음 (검증 실패로 soft-fail)
        assertTrue(boosting.usedUserNonces(user2, 0));

        // 집계: user1 첫 번째(100) + user2(200) = 300
        // user1의 두 번째는 중복으로 실패
        assertEq(boosting.artistTotalAmt(1, 1), 100);
        assertEq(boosting.artistTotalAmt(1, 2), 200);
    }

    // ╔═══════════════════════════════════════════════════════════════════════════╗
    // ║              InvalidBoostType 테스트                                        ║
    // ╚═══════════════════════════════════════════════════════════════════════════╝

    function test_RevertWhen_SetBoostingTypeNameInvalidType() public {
        vm.expectRevert(
            abi.encodeWithSelector(Boosting.InvalidBoostType.selector, 2)
        );
        boosting.setBoostingTypeName(2, "Invalid");
    }

    function test_SoftFail_InvalidBoostType_InRecord() public {
        Boosting.BoostRecord memory invalidRecord = Boosting.BoostRecord({
            recordId: 1,
            timestamp: block.timestamp,
            missionId: 1,
            boostingId: 1,
            userId: "user1",
            optionId: 1,
            boostingWith: 2, // invalid (max is 1)
            amt: 100
        });

        bytes32 recordHash = _hashBoostRecord(invalidRecord, user1);
        bytes32 userSigDigest = _hashUserSig(user1, 0, recordHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, userSigDigest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 유효한 유저도 추가
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](2);
        batches[0] = Boosting.UserBoostBatch({
            record: invalidRecord,
            userSig: Boosting.UserSig({
                user: user1,
                userNonce: 0,
                signature: signature
            })
        });
        batches[1] = _createUserBoostBatch(
            user2PrivateKey, user2, "user2", 1, 2, 2, 1, 200, 0
        );

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);
        boosting.submitBoostBatch(batches, 0, executorSig);

        // user1 실패, user2 성공
        assertFalse(boosting.usedUserNonces(user1, 0));
        assertTrue(boosting.usedUserNonces(user2, 0));
        assertEq(boosting.artistTotalAmt(1, 2), 200);
    }

    // ╔═══════════════════════════════════════════════════════════════════════════╗
    // ║              Zero Amount 테스트                                             ║
    // ╚═══════════════════════════════════════════════════════════════════════════╝

    function test_SoftFail_ZeroAmount_InRecord() public {
        Boosting.BoostRecord memory zeroRecord = Boosting.BoostRecord({
            recordId: 1,
            timestamp: block.timestamp,
            missionId: 1,
            boostingId: 1,
            userId: "user1",
            optionId: 1,
            boostingWith: 0,
            amt: 0 // zero amount
        });

        bytes32 recordHash = _hashBoostRecord(zeroRecord, user1);
        bytes32 userSigDigest = _hashUserSig(user1, 0, recordHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, userSigDigest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 유효한 유저도 추가
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](2);
        batches[0] = Boosting.UserBoostBatch({
            record: zeroRecord,
            userSig: Boosting.UserSig({
                user: user1,
                userNonce: 0,
                signature: signature
            })
        });
        batches[1] = _createUserBoostBatch(
            user2PrivateKey, user2, "user2", 1, 2, 2, 1, 200, 0
        );

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);
        boosting.submitBoostBatch(batches, 0, executorSig);

        // user1 실패 (zero amt), user2 성공
        assertFalse(boosting.usedUserNonces(user1, 0));
        assertTrue(boosting.usedUserNonces(user2, 0));
    }
}

// ERC1271Mock import for tests
import {ERC1271Mock} from "./mocks/ERC1271Mock.sol";

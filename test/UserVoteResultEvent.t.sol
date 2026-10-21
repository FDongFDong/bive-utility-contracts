// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MainVoting} from "../src/vote/MainVoting.sol";

/**
 * @title UserMissionResult 이벤트 테스트
 * @notice 컨트랙트의 실제 동작:
 *         - UserBatchFailed: 검증 단계에서 실패 시 발생 (서명 무효, nonce 무효, voteType 무효, artist 미허용)
 *         - UserMissionResult: 저장 단계에서 발생 (검증 실패한 유저도 포함)
 *           - success=true: 검증 통과 및 저장 성공
 *           - success=false: 검증 실패
 *
 *         이벤트 발생 순서:
 *         1. _validateAndProcess에서 UserBatchProcessed / UserBatchFailed 발생
 *         2. _storeVotes에서 모든 UserMissionResult 발생 (성공/실패 모두)
 */
contract UserMissionResultEventTest is Test {
    MainVoting public voting;

    address public owner;
    address public executorSigner;
    address public user1;
    address public user2;
    address public user3;

    uint256 public user1PrivateKey;
    uint256 public user2PrivateKey;
    uint256 public user3PrivateKey;
    uint256 public executorPrivateKey;

    // EIP-712 Type Hashes
    bytes32 private constant VOTE_RECORD_TYPEHASH =
        keccak256(
            "VoteRecord(uint256 timestamp,uint256 missionId,uint256 votingId,uint256 optionId,uint8 voteType,uint256 votingAmt,address user)"
        );
    bytes32 private constant USER_BATCH_TYPEHASH =
        keccak256("UserBatch(address user,uint256 userNonce,bytes32 recordsHash)");
    bytes32 private constant BATCH_TYPEHASH =
        keccak256("Batch(uint256 batchNonce)");

    // 실패 사유 코드
    uint8 private constant REASON_USER_BATCH_TOO_LARGE = 1;
    uint8 private constant REASON_INVALID_USER_SIGNATURE = 2;
    uint8 private constant REASON_USER_NONCE_INVALID = 3;
    uint8 private constant REASON_INVALID_VOTE_TYPE = 4;
    uint8 private constant REASON_ARTIST_NOT_ALLOWED = 5;

    // 이벤트 정의 (테스트용)
    event UserMissionResult(
        uint256 indexed votingId,
        bool success,
        uint256[] failedRecordIds,
        uint8 reasonCode
    );

    event UserBatchFailed(
        bytes32 indexed batchDigest,
        address indexed user,
        uint256 userNonce,
        uint8 reasonCode
    );

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

        voting = new MainVoting(owner);
        voting.setExecutorSigner(executorSigner);

        // 아티스트 설정 (missionId=1)
        voting.setArtist(1, 1, "BTS", true);
        voting.setArtist(1, 2, "BLACKPINK", true);
        voting.setArtist(1, 3, "TWICE", true);
        voting.setArtist(1, 4, "SEVENTEEN", true);
        voting.setArtist(1, 5, "STRAY KIDS", true);

        // 투표 타입 설정
        voting.setVoteTypeName(0, "Forget");
        voting.setVoteTypeName(1, "Remember");

        console.log("========================================");
        console.log("Test Setup Complete");
        console.log("========================================");
        console.log("Contract:", address(voting));
        console.log("Executor:", executorSigner);
        console.log("User1:", user1);
        console.log("User2:", user2);
        console.log("User3:", user3);
        console.log("========================================");
    }

    // =====================================================================
    //                           Helper Functions
    // =====================================================================

    function _buildDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("MainVoting")),
                keccak256(bytes("1")),
                block.chainid,
                address(voting)
            )
        );
    }

    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _buildDomainSeparator(), structHash));
    }

    function _createVoteRecord(
        string memory userId,
        uint256 missionId,
        uint256 votingId,
        uint256 optionId,
        uint8 voteType,
        uint256 votingAmt
    ) internal view returns (MainVoting.VoteRecord memory) {
        return MainVoting.VoteRecord({
            recordId: uint256(keccak256(abi.encodePacked(userId, missionId, votingId, optionId, block.timestamp))),
            timestamp: block.timestamp,
            missionId: missionId,
            votingId: votingId,
            optionId: optionId,
            voteType: voteType,
            userId: userId,
            votingAmt: votingAmt
        });
    }

    function _hashVoteRecord(MainVoting.VoteRecord memory record, address user) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                VOTE_RECORD_TYPEHASH,
                record.timestamp,
                record.missionId,
                record.votingId,
                record.optionId,
                record.voteType,
                record.votingAmt,
                user
            )
        );
    }

    function _signUserBatch(
        uint256 privateKey,
        MainVoting.VoteRecord[] memory records,
        uint256 userNonceVal
    ) internal view returns (bytes memory) {
        address user = vm.addr(privateKey);

        bytes32[] memory recordDigests = new bytes32[](records.length);
        for (uint256 i = 0; i < records.length; i++) {
            recordDigests[i] = _hashVoteRecord(records[i], user);
        }
        bytes32 recordsHash = keccak256(abi.encodePacked(recordDigests));

        bytes32 structHash = keccak256(
            abi.encode(USER_BATCH_TYPEHASH, user, userNonceVal, recordsHash)
        );
        bytes32 digest = _hashTypedDataV4(structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signBatchSig(uint256 privateKey, uint256 batchNonceVal) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(BATCH_TYPEHASH, batchNonceVal));
        bytes32 digest = _hashTypedDataV4(structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _createUserVoteBatch(
        MainVoting.VoteRecord[] memory records,
        address user,
        uint256 userNonceVal,
        uint256 privateKey
    ) internal view returns (MainVoting.UserVoteBatch memory) {
        return MainVoting.UserVoteBatch({
            records: records,
            userBatchSig: MainVoting.UserBatchSig({
                user: user,
                userNonce: userNonceVal,
                signature: _signUserBatch(privateKey, records, userNonceVal)
            })
        });
    }

    function _createUserVoteBatchWithWrongSig(
        MainVoting.VoteRecord[] memory records,
        address user,
        uint256 userNonceVal,
        uint256 wrongPrivateKey
    ) internal view returns (MainVoting.UserVoteBatch memory) {
        return MainVoting.UserVoteBatch({
            records: records,
            userBatchSig: MainVoting.UserBatchSig({
                user: user,
                userNonce: userNonceVal,
                signature: _signUserBatch(wrongPrivateKey, records, userNonceVal)
            })
        });
    }

    // =====================================================================
    //        테스트 1: 성공 케이스 - UserMissionResult(votingId, true, [], 0)
    // =====================================================================

    function test_UserMissionResult_Success_SingleUser() public {
        console.log("\n========================================");
        console.log("TEST: Success Case - Single User");
        console.log("========================================");

        // User1이 votingId=100에 투표
        MainVoting.VoteRecord[] memory records = new MainVoting.VoteRecord[](2);
        records[0] = _createVoteRecord("user1_uuid", 1, 100, 1, 1, 500);  // BTS에 Remember
        records[1] = _createVoteRecord("user1_uuid", 1, 100, 2, 0, 300);  // BLACKPINK에 Forget

        MainVoting.UserVoteBatch[] memory batches = new MainVoting.UserVoteBatch[](1);
        batches[0] = _createUserVoteBatch(records, user1, 0, user1PrivateKey);

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);

        console.log("Submitting vote...");
        console.log("  votingId: 100");
        console.log("  optionIds: [1 (BTS), 2 (BLACKPINK)]");
        console.log("  Expected: UserMissionResult(100, true, [], 0)");

        // 이벤트 기대
        uint256[] memory emptyArray = new uint256[](0);
        vm.expectEmit(true, false, false, true);
        emit UserMissionResult(100, true, emptyArray, 0);

        voting.submitMultiUserBatch(batches, 0, executorSig);

        console.log("SUCCESS: Event emitted correctly!");
        console.log("========================================\n");
    }

    function test_UserMissionResult_Success_MultipleUsers() public {
        console.log("\n========================================");
        console.log("TEST: Success Case - Multiple Users");
        console.log("========================================");

        MainVoting.UserVoteBatch[] memory batches = new MainVoting.UserVoteBatch[](3);

        // User1: votingId=200
        MainVoting.VoteRecord[] memory records1 = new MainVoting.VoteRecord[](1);
        records1[0] = _createVoteRecord("user1_uuid", 1, 200, 1, 1, 100);
        batches[0] = _createUserVoteBatch(records1, user1, 0, user1PrivateKey);

        // User2: votingId=201
        MainVoting.VoteRecord[] memory records2 = new MainVoting.VoteRecord[](1);
        records2[0] = _createVoteRecord("user2_uuid", 1, 201, 2, 0, 200);
        batches[1] = _createUserVoteBatch(records2, user2, 0, user2PrivateKey);

        // User3: votingId=202
        MainVoting.VoteRecord[] memory records3 = new MainVoting.VoteRecord[](1);
        records3[0] = _createVoteRecord("user3_uuid", 1, 202, 3, 1, 150);
        batches[2] = _createUserVoteBatch(records3, user3, 0, user3PrivateKey);

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);

        console.log("Submitting 3 users' votes...");
        console.log("  User1: votingId=200, optionId=1 (BTS)");
        console.log("  User2: votingId=201, optionId=2 (BLACKPINK)");
        console.log("  User3: votingId=202, optionId=3 (TWICE)");
        console.log("Expected events:");
        console.log("  UserMissionResult(200, true, [], 0)");
        console.log("  UserMissionResult(201, true, [], 0)");
        console.log("  UserMissionResult(202, true, [], 0)");

        // 3개의 성공 이벤트 기대
        uint256[] memory emptyArray = new uint256[](0);

        vm.expectEmit(true, false, false, true);
        emit UserMissionResult(200, true, emptyArray, 0);

        vm.expectEmit(true, false, false, true);
        emit UserMissionResult(201, true, emptyArray, 0);

        vm.expectEmit(true, false, false, true);
        emit UserMissionResult(202, true, emptyArray, 0);

        voting.submitMultiUserBatch(batches, 0, executorSig);

        console.log("SUCCESS: All 3 events emitted correctly!");
        console.log("========================================\n");
    }

    // =====================================================================
    //   테스트 2: 실패 케이스 - 이벤트 순서: UserBatchFailed -> UserMissionResult
    //   검증 단계에서 UserBatchFailed 발생 후, 저장 단계에서 UserMissionResult 발생
    // =====================================================================

    /// @notice 서명 무효 시 UserBatchFailed 먼저, 그 다음 UserMissionResult 발생
    function test_UserBatchFailed_InvalidSignature() public {
        console.log("\n========================================");
        console.log("TEST: Fail Case - Invalid Signature");
        console.log("========================================");

        MainVoting.UserVoteBatch[] memory batches = new MainVoting.UserVoteBatch[](2);

        // User1: 성공 (votingId=300)
        MainVoting.VoteRecord[] memory records1 = new MainVoting.VoteRecord[](1);
        records1[0] = _createVoteRecord("user1_uuid", 1, 300, 1, 1, 100);
        batches[0] = _createUserVoteBatch(records1, user1, 0, user1PrivateKey);

        // User2: 잘못된 서명 (votingId=301)
        MainVoting.VoteRecord[] memory records2 = new MainVoting.VoteRecord[](1);
        records2[0] = _createVoteRecord("user2_uuid", 1, 301, 2, 1, 200);
        batches[1] = _createUserVoteBatchWithWrongSig(records2, user2, 0, user3PrivateKey);

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);

        console.log("Submitting votes with invalid signature...");
        console.log("  User1: votingId=300 -> SUCCESS");
        console.log("  User2: votingId=301 -> FAIL");
        console.log("Event order: UserBatchFailed -> UserMissionResult(300, true) -> UserMissionResult(301, false)");

        uint256[] memory emptyArray = new uint256[](0);

        // 1. User2 실패 - UserBatchFailed 이벤트 (검증 단계에서 먼저 발생)
        vm.expectEmit(false, true, false, true);
        emit UserBatchFailed(bytes32(0), user2, 0, REASON_INVALID_USER_SIGNATURE);

        // 2. User1 성공 - UserMissionResult (저장 단계에서 발생)
        vm.expectEmit(true, false, false, true);
        emit UserMissionResult(300, true, emptyArray, 0);

        // 3. User2 실패 결과 - UserMissionResult(false) (저장 단계에서 발생)
        vm.expectEmit(true, false, false, false);
        emit UserMissionResult(301, false, emptyArray, REASON_INVALID_USER_SIGNATURE);

        voting.submitMultiUserBatch(batches, 0, executorSig);

        console.log("SUCCESS: Events emitted correctly!");
        console.log("========================================\n");
    }

    /// @notice Artist 미허용 시 - per-record 검증은 저장 단계에서 수행
    /// @dev artistNotAllowed는 저장 단계에서 검증되므로 UserBatchFailed 이벤트 없이
    ///      UserMissionResult에서 실패 처리됨. 서명/nonce 검증은 통과하므로 nonce 증가.
    function test_UserBatchFailed_ArtistNotAllowed() public {
        console.log("\n========================================");
        console.log("TEST: Fail Case - Artist Not Allowed");
        console.log("========================================");

        MainVoting.UserVoteBatch[] memory batches = new MainVoting.UserVoteBatch[](2);

        // User1: 성공 (votingId=400)
        MainVoting.VoteRecord[] memory records1 = new MainVoting.VoteRecord[](1);
        records1[0] = _createVoteRecord("user1_uuid", 1, 400, 1, 1, 100);
        batches[0] = _createUserVoteBatch(records1, user1, 0, user1PrivateKey);

        // User2: 허용되지 않은 아티스트 (optionId=99)
        MainVoting.VoteRecord[] memory records2 = new MainVoting.VoteRecord[](1);
        records2[0] = _createVoteRecord("user2_uuid", 1, 401, 99, 1, 200);  // 허용 안됨!
        batches[1] = _createUserVoteBatch(records2, user2, 0, user2PrivateKey);

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);

        console.log("Submitting votes with not-allowed artist...");
        console.log("  User1: votingId=400 -> SUCCESS");
        console.log("  User2: votingId=401, optionId=99 -> FAIL (at store phase)");

        uint256[] memory emptyArray = new uint256[](0);

        // artistNotAllowed 검증은 저장 단계에서 수행되므로 UserBatchFailed 이벤트 없음
        // User1 성공
        vm.expectEmit(true, false, false, true);
        emit UserMissionResult(400, true, emptyArray, 0);

        // User2 실패 결과 (저장 단계에서 검증 실패)
        vm.expectEmit(true, false, false, false);
        emit UserMissionResult(401, false, emptyArray, REASON_ARTIST_NOT_ALLOWED);

        voting.submitMultiUserBatch(batches, 0, executorSig);

        console.log("SUCCESS: Events emitted correctly!");
        console.log("========================================\n");
    }

    /// @notice voteType 무효 시 - per-record 검증은 저장 단계에서 수행
    /// @dev voteType 검증은 저장 단계에서 수행되므로 UserBatchFailed 이벤트 없이
    ///      UserMissionResult에서 실패 처리됨. 서명/nonce 검증은 통과하므로 nonce 증가.
    function test_UserBatchFailed_InvalidVoteType() public {
        console.log("\n========================================");
        console.log("TEST: Fail Case - Invalid Vote Type");
        console.log("========================================");

        MainVoting.UserVoteBatch[] memory batches = new MainVoting.UserVoteBatch[](2);

        // User1: 성공 (votingId=500)
        MainVoting.VoteRecord[] memory records1 = new MainVoting.VoteRecord[](1);
        records1[0] = _createVoteRecord("user1_uuid", 1, 500, 1, 1, 100);
        batches[0] = _createUserVoteBatch(records1, user1, 0, user1PrivateKey);

        // User2: 잘못된 voteType (5는 유효하지 않음)
        MainVoting.VoteRecord[] memory records2 = new MainVoting.VoteRecord[](1);
        records2[0] = _createVoteRecord("user2_uuid", 1, 501, 2, 5, 200);  // voteType=5 invalid!
        batches[1] = _createUserVoteBatch(records2, user2, 0, user2PrivateKey);

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);

        console.log("Submitting votes with invalid voteType...");
        console.log("  User1: votingId=500 -> SUCCESS");
        console.log("  User2: votingId=501, voteType=5 -> FAIL (at store phase)");

        uint256[] memory emptyArray = new uint256[](0);

        // voteType 검증은 저장 단계에서 수행되므로 UserBatchFailed 이벤트 없음
        // User1 성공
        vm.expectEmit(true, false, false, true);
        emit UserMissionResult(500, true, emptyArray, 0);

        // User2 실패 결과 (저장 단계에서 검증 실패)
        vm.expectEmit(true, false, false, false);
        emit UserMissionResult(501, false, emptyArray, REASON_INVALID_VOTE_TYPE);

        voting.submitMultiUserBatch(batches, 0, executorSig);

        console.log("SUCCESS: Events emitted correctly!");
        console.log("========================================\n");
    }

    /// @notice Nonce 중복 사용 시
    function test_UserBatchFailed_NonceAlreadyUsed() public {
        console.log("\n========================================");
        console.log("TEST: Fail Case - Nonce Already Used");
        console.log("========================================");

        // 먼저 User1이 nonce 0으로 성공적으로 제출
        MainVoting.UserVoteBatch[] memory firstBatches = new MainVoting.UserVoteBatch[](1);
        MainVoting.VoteRecord[] memory firstRecords = new MainVoting.VoteRecord[](1);
        firstRecords[0] = _createVoteRecord("user1_uuid", 1, 599, 1, 1, 50);
        firstBatches[0] = _createUserVoteBatch(firstRecords, user1, 0, user1PrivateKey);
        bytes memory firstExecutorSig = _signBatchSig(executorPrivateKey, 0);
        voting.submitMultiUserBatch(firstBatches, 0, firstExecutorSig);

        MainVoting.UserVoteBatch[] memory batches = new MainVoting.UserVoteBatch[](2);

        // User1: 이미 사용된 nonce 0으로 다시 시도
        MainVoting.VoteRecord[] memory records1 = new MainVoting.VoteRecord[](1);
        records1[0] = _createVoteRecord("user1_uuid", 1, 600, 1, 1, 100);
        batches[0] = _createUserVoteBatch(records1, user1, 0, user1PrivateKey);  // nonce=0 (already used!)

        // User2: 성공
        MainVoting.VoteRecord[] memory records2 = new MainVoting.VoteRecord[](1);
        records2[0] = _createVoteRecord("user2_uuid", 1, 601, 2, 1, 200);
        batches[1] = _createUserVoteBatch(records2, user2, 0, user2PrivateKey);

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 1);

        console.log("Submitting votes with already used nonce...");
        console.log("  User1: votingId=600, nonce=0 (already used) -> FAIL");
        console.log("  User2: votingId=601 -> SUCCESS");

        uint256[] memory emptyArray = new uint256[](0);

        // 1. User1 실패 - UserBatchFailed 이벤트
        vm.expectEmit(false, true, false, true);
        emit UserBatchFailed(bytes32(0), user1, 0, REASON_USER_NONCE_INVALID);

        // 2. User1 실패 결과 - UserMissionResult(false)
        vm.expectEmit(true, false, false, false);
        emit UserMissionResult(600, false, emptyArray, REASON_USER_NONCE_INVALID);

        // 3. User2 성공
        vm.expectEmit(true, false, false, true);
        emit UserMissionResult(601, true, emptyArray, 0);

        voting.submitMultiUserBatch(batches, 1, executorSig);

        console.log("SUCCESS: Events emitted correctly!");
        console.log("========================================\n");
    }

    // =====================================================================
    //                 테스트 3: 복합 케이스 - 성공/실패 혼합
    // =====================================================================

    function test_UserMissionResult_Mixed_MultipleUsersPartialFail() public {
        console.log("\n========================================");
        console.log("TEST: Mixed Case - Multiple Users, Partial Fail");
        console.log("========================================");

        MainVoting.UserVoteBatch[] memory batches = new MainVoting.UserVoteBatch[](3);

        // User1: 성공 (votingId=700)
        MainVoting.VoteRecord[] memory records1 = new MainVoting.VoteRecord[](2);
        records1[0] = _createVoteRecord("user1_uuid", 1, 700, 1, 1, 100);  // BTS Remember
        records1[1] = _createVoteRecord("user1_uuid", 1, 700, 2, 0, 50);   // BLACKPINK Forget
        batches[0] = _createUserVoteBatch(records1, user1, 0, user1PrivateKey);

        // User2: 실패 - 잘못된 서명 (votingId=701)
        MainVoting.VoteRecord[] memory records2 = new MainVoting.VoteRecord[](1);
        records2[0] = _createVoteRecord("user2_uuid", 1, 701, 3, 1, 200);  // TWICE
        batches[1] = _createUserVoteBatchWithWrongSig(records2, user2, 0, user1PrivateKey);

        // User3: 성공 (votingId=702)
        MainVoting.VoteRecord[] memory records3 = new MainVoting.VoteRecord[](1);
        records3[0] = _createVoteRecord("user3_uuid", 1, 702, 5, 1, 300);  // STRAY KIDS
        batches[2] = _createUserVoteBatch(records3, user3, 0, user3PrivateKey);

        bytes memory executorSig = _signBatchSig(executorPrivateKey, 0);

        console.log("Submitting mixed success/fail batch...");
        console.log("  User1 (votingId=700): 2 records -> SUCCESS");
        console.log("  User2 (votingId=701): wrong sig -> FAIL");
        console.log("  User3 (votingId=702): 1 record -> SUCCESS");

        uint256[] memory emptyArray = new uint256[](0);

        // 1. User2 실패 - UserBatchFailed (검증 단계)
        vm.expectEmit(false, true, false, true);
        emit UserBatchFailed(bytes32(0), user2, 0, REASON_INVALID_USER_SIGNATURE);

        // 2. User1 성공 (저장 단계)
        vm.expectEmit(true, false, false, true);
        emit UserMissionResult(700, true, emptyArray, 0);

        // 3. User2 실패 결과 (저장 단계)
        vm.expectEmit(true, false, false, false);
        emit UserMissionResult(701, false, emptyArray, REASON_INVALID_USER_SIGNATURE);

        // 4. User3 성공 (저장 단계)
        vm.expectEmit(true, false, false, true);
        emit UserMissionResult(702, true, emptyArray, 0);

        voting.submitMultiUserBatch(batches, 0, executorSig);

        console.log("");
        console.log("SUCCESS: All events emitted correctly!");
        console.log("");
        console.log("Final Stats:");
        (uint256 r1,, uint256 t1) = voting.getArtistAggregates(1, 1);
        console.log("  BTS: remember=%d, total=%d", r1, t1);
        (,uint256 f2, uint256 t2) = voting.getArtistAggregates(1, 2);
        console.log("  BLACKPINK: forget=%d, total=%d", f2, t2);
        (uint256 r5,, uint256 t5) = voting.getArtistAggregates(1, 5);
        console.log("  STRAY KIDS: remember=%d, total=%d", r5, t5);
        console.log("========================================\n");
    }

    // =====================================================================
    //                      실제 로그 출력 테스트 (verbose)
    // =====================================================================

    function test_UserMissionResult_PrintEventFormat() public pure {
        console.log("\n");
        console.log("================================================================");
        console.log("            Event Format Examples");
        console.log("================================================================");
        console.log("");
        console.log("SUCCESS case - UserMissionResult only:");
        console.log("  event UserMissionResult(");
        console.log("    votingId: 100,");
        console.log("    success: true,");
        console.log("    failedRecordIds: [],");
        console.log("    reasonCode: 0");
        console.log("  )");
        console.log("");
        console.log("FAIL case - UserBatchFailed THEN UserMissionResult(false):");
        console.log("  1. event UserBatchFailed(  // validation phase");
        console.log("       batchDigest: 0x...,");
        console.log("       user: 0x...,");
        console.log("       userNonce: 0,");
        console.log("       reasonCode: 2");
        console.log("     )");
        console.log("  2. event UserMissionResult(   // store phase");
        console.log("       votingId: 101,");
        console.log("       success: false,");
        console.log("       failedRecordIds: [recordId1, ...],");
        console.log("       reasonCode: 2");
        console.log("     )");
        console.log("");
        console.log("Reason Codes:");
        console.log("  1 = REASON_USER_BATCH_TOO_LARGE");
        console.log("  2 = REASON_INVALID_USER_SIGNATURE");
        console.log("  3 = REASON_USER_NONCE_INVALID");
        console.log("  4 = REASON_INVALID_VOTE_TYPE");
        console.log("  5 = REASON_ARTIST_NOT_ALLOWED");
        console.log("");
        console.log("================================================================");
        console.log("");
    }
}

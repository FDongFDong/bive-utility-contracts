// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SubVoting} from "../../../src/vote/SubVoting.sol";

contract SubVotingHandler is Test {
    SubVoting public voting;

    bytes32 private constant VOTE_RECORD_TYPEHASH =
        keccak256(
            "VoteRecord(uint256 timestamp,uint256 missionId,uint256 votingId,uint256 questionId,uint256 optionId,uint256 votingAmt,address user)"
        );
    bytes32 private constant USER_BATCH_TYPEHASH =
        keccak256("UserBatch(address user,uint256 userNonce,bytes32 recordsHash)");
    bytes32 private constant BATCH_TYPEHASH = keccak256("Batch(uint256 batchNonce)");

    uint256 private immutable _executorKey;
    address public immutable executorSigner;

    uint256[3] private _userKeys;
    address[3] private _users;

    uint256 private _nextBatchNonce;
    uint256[3] private _nextUserNonce;
    uint256 private _nextRecordId = 1;

    mapping(uint256 => mapping(uint256 => uint256)) public expectedOptionVotes;
    mapping(uint256 => uint256) public expectedQuestionTotals;

    uint256[] private _expectedConsumedBatchNonces;
    uint256[] private _expectedUnconsumedBatchNonces;
    uint256[][3] private _expectedConsumedUserNonces;
    uint256[][3] private _expectedUnconsumedUserNonces;

    constructor(SubVoting _voting, uint256 executorKey_) {
        voting = _voting;
        _executorKey = executorKey_;
        executorSigner = vm.addr(executorKey_);

        _userKeys[0] = 0x1111;
        _userKeys[1] = 0x2222;
        _userKeys[2] = 0x3333;

        _users[0] = vm.addr(_userKeys[0]);
        _users[1] = vm.addr(_userKeys[1]);
        _users[2] = vm.addr(_userKeys[2]);
    }

    function submitValid(
        uint256 userSeed,
        uint256 questionSeed,
        uint256 optionSeed,
        uint256 amtSeed
    ) external {
        uint256 userIdx = bound(userSeed, 0, 2);
        uint256 questionId = bound(questionSeed, 1, 2);
        uint256 optionId = bound(optionSeed, 1, 2);
        uint256 amount = bound(amtSeed, 1, 1_000_000);

        SubVoting.VoteRecord memory record = _newRecord(
            userIdx,
            questionId,
            optionId,
            amount
        );
        SubVoting.UserVoteBatch memory ub = _newBatch(userIdx, record, false, 0);
        SubVoting.UserVoteBatch[] memory batches = new SubVoting.UserVoteBatch[](1);
        batches[0] = ub;

        uint256 batchNonce = _nextBatchNonce;
        bytes memory executorSig = _signBatch(batchNonce);
        vm.prank(executorSigner);
        voting.submitMultiUserBatch(batches, batchNonce, executorSig);

        _expectedConsumedBatchNonces.push(batchNonce);
        _expectedConsumedUserNonces[userIdx].push(_nextUserNonce[userIdx]);

        expectedOptionVotes[questionId][optionId] += amount;
        expectedQuestionTotals[questionId] += amount;

        _nextBatchNonce++;
        _nextUserNonce[userIdx]++;
    }

    function submitInvalidRecordSoftFail(
        uint256 badUserSeed,
        uint256 goodUserSeed,
        uint256 goodQuestionSeed,
        uint256 goodOptionSeed,
        uint256 goodAmtSeed
    ) external {
        uint256 badUserIdx = bound(badUserSeed, 0, 2);
        uint256 goodUserIdx = bound(goodUserSeed, 0, 2);
        if (goodUserIdx == badUserIdx) goodUserIdx = (goodUserIdx + 1) % 3;

        uint256 goodQuestionId = bound(goodQuestionSeed, 1, 2);
        uint256 goodOptionId = bound(goodOptionSeed, 1, 2);
        uint256 goodAmount = bound(goodAmtSeed, 1, 1_000_000);

        SubVoting.VoteRecord memory badRecord = _newRecord(
            badUserIdx,
            99, // allowedQuestion=false
            1,
            100
        );
        SubVoting.VoteRecord memory goodRecord = _newRecord(
            goodUserIdx,
            goodQuestionId,
            goodOptionId,
            goodAmount
        );

        SubVoting.UserVoteBatch[] memory batches = new SubVoting.UserVoteBatch[](
            2
        );
        batches[0] = _newBatch(badUserIdx, badRecord, false, 0);
        batches[1] = _newBatch(goodUserIdx, goodRecord, false, 0);

        uint256 batchNonce = _nextBatchNonce;
        bytes memory executorSig = _signBatch(batchNonce);
        vm.prank(executorSigner);
        voting.submitMultiUserBatch(batches, batchNonce, executorSig);

        _expectedConsumedBatchNonces.push(batchNonce);
        _expectedUnconsumedUserNonces[badUserIdx].push(_nextUserNonce[badUserIdx]);
        _expectedConsumedUserNonces[goodUserIdx].push(
            _nextUserNonce[goodUserIdx]
        );

        expectedOptionVotes[goodQuestionId][goodOptionId] += goodAmount;
        expectedQuestionTotals[goodQuestionId] += goodAmount;

        _nextBatchNonce++;
        _nextUserNonce[badUserIdx]++;
        _nextUserNonce[goodUserIdx]++;
    }

    function submitMalformedUserSoftFail(
        uint256 badUserSeed,
        uint256 goodUserSeed,
        uint256 goodQuestionSeed,
        uint256 goodOptionSeed,
        uint256 goodAmtSeed,
        uint8 badSigLenSeed
    ) external {
        uint256 badUserIdx = bound(badUserSeed, 0, 2);
        uint256 goodUserIdx = bound(goodUserSeed, 0, 2);
        if (goodUserIdx == badUserIdx) goodUserIdx = (goodUserIdx + 1) % 3;

        uint256 goodQuestionId = bound(goodQuestionSeed, 1, 2);
        uint256 goodOptionId = bound(goodOptionSeed, 1, 2);
        uint256 goodAmount = bound(goodAmtSeed, 1, 1_000_000);
        uint256 badSigLen = _badSigLen(badSigLenSeed);

        SubVoting.VoteRecord memory badRecord = _newRecord(badUserIdx, 1, 1, 100);
        SubVoting.VoteRecord memory goodRecord = _newRecord(
            goodUserIdx,
            goodQuestionId,
            goodOptionId,
            goodAmount
        );

        SubVoting.UserVoteBatch[] memory batches = new SubVoting.UserVoteBatch[](
            2
        );
        batches[0] = _newBatch(badUserIdx, badRecord, true, badSigLen);
        batches[1] = _newBatch(goodUserIdx, goodRecord, false, 0);

        uint256 batchNonce = _nextBatchNonce;
        bytes memory executorSig = _signBatch(batchNonce);
        vm.prank(executorSigner);
        voting.submitMultiUserBatch(batches, batchNonce, executorSig);

        _expectedConsumedBatchNonces.push(batchNonce);
        _expectedUnconsumedUserNonces[badUserIdx].push(
            _nextUserNonce[badUserIdx]
        );
        _expectedConsumedUserNonces[goodUserIdx].push(
            _nextUserNonce[goodUserIdx]
        );

        expectedOptionVotes[goodQuestionId][goodOptionId] += goodAmount;
        expectedQuestionTotals[goodQuestionId] += goodAmount;

        _nextBatchNonce++;
        _nextUserNonce[badUserIdx]++;
        _nextUserNonce[goodUserIdx]++;
    }

    function submitAllMalformedUsers(
        uint256 userSeed,
        uint8 badSigLenSeed
    ) external {
        uint256 userIdx = bound(userSeed, 0, 2);
        uint256 badSigLen = _badSigLen(badSigLenSeed);

        SubVoting.VoteRecord memory record = _newRecord(userIdx, 1, 1, 100);
        SubVoting.UserVoteBatch[] memory batches = new SubVoting.UserVoteBatch[](1);
        batches[0] = _newBatch(userIdx, record, true, badSigLen);

        uint256 batchNonce = _nextBatchNonce;
        bytes memory executorSig = _signBatch(batchNonce);

        vm.expectRevert(SubVoting.NoSuccessfulUser.selector);
        vm.prank(executorSigner);
        voting.submitMultiUserBatch(batches, batchNonce, executorSig);

        _expectedUnconsumedBatchNonces.push(batchNonce);
        _expectedUnconsumedUserNonces[userIdx].push(_nextUserNonce[userIdx]);

        _nextBatchNonce++;
        _nextUserNonce[userIdx]++;
    }

    function submitMalformedExecutorSignature(uint256 userSeed) external {
        uint256 userIdx = bound(userSeed, 0, 2);

        SubVoting.VoteRecord memory record = _newRecord(userIdx, 1, 1, 100);
        SubVoting.UserVoteBatch[] memory batches = new SubVoting.UserVoteBatch[](1);
        batches[0] = _newBatch(userIdx, record, false, 0);

        uint256 batchNonce = _nextBatchNonce;

        vm.expectRevert(SubVoting.InvalidSignature.selector);
        vm.prank(executorSigner);
        voting.submitMultiUserBatch(batches, batchNonce, hex"1234");

        _expectedUnconsumedBatchNonces.push(batchNonce);
        _expectedUnconsumedUserNonces[userIdx].push(_nextUserNonce[userIdx]);

        _nextBatchNonce++;
        _nextUserNonce[userIdx]++;
    }

    function userAt(uint256 userIdx) external view returns (address) {
        return _users[userIdx];
    }

    function getExpectedConsumedBatchNonces()
        external
        view
        returns (uint256[] memory)
    {
        return _expectedConsumedBatchNonces;
    }

    function getExpectedUnconsumedBatchNonces()
        external
        view
        returns (uint256[] memory)
    {
        return _expectedUnconsumedBatchNonces;
    }

    function getExpectedConsumedUserNonces(
        uint256 userIdx
    ) external view returns (uint256[] memory) {
        return _expectedConsumedUserNonces[userIdx];
    }

    function getExpectedUnconsumedUserNonces(
        uint256 userIdx
    ) external view returns (uint256[] memory) {
        return _expectedUnconsumedUserNonces[userIdx];
    }

    function _newBatch(
        uint256 userIdx,
        SubVoting.VoteRecord memory record,
        bool malformedSignature,
        uint256 badSigLen
    ) internal view returns (SubVoting.UserVoteBatch memory) {
        SubVoting.VoteRecord[] memory records = new SubVoting.VoteRecord[](1);
        records[0] = record;

        bytes memory signature;
        if (malformedSignature) {
            signature = new bytes(badSigLen);
        } else {
            signature = _signUserBatch(
                _userKeys[userIdx],
                _users[userIdx],
                _nextUserNonce[userIdx],
                records
            );
        }

        return
            SubVoting.UserVoteBatch({
                records: records,
                userBatchSig: SubVoting.UserBatchSig({
                    user: _users[userIdx],
                    userNonce: _nextUserNonce[userIdx],
                    signature: signature
                })
            });
    }

    function _newRecord(
        uint256 userIdx,
        uint256 questionId,
        uint256 optionId,
        uint256 amount
    ) internal returns (SubVoting.VoteRecord memory) {
        uint256 recordId = _nextRecordId++;
        return
            SubVoting.VoteRecord({
                recordId: recordId,
                timestamp: block.timestamp + recordId,
                missionId: 1,
                votingId: recordId,
                userId: _userId(userIdx),
                questionId: questionId,
                optionId: optionId,
                votingAmt: amount
            });
    }

    function _userId(uint256 userIdx) internal pure returns (string memory) {
        if (userIdx == 0) return "user1";
        if (userIdx == 1) return "user2";
        return "user3";
    }

    function _signUserBatch(
        uint256 userKey,
        address user,
        uint256 userNonce,
        SubVoting.VoteRecord[] memory records
    ) internal view returns (bytes memory) {
        bytes32[] memory digests = new bytes32[](records.length);
        for (uint256 i = 0; i < records.length; i++) {
            digests[i] = _hashVoteRecord(records[i], user);
        }
        bytes32 recordsHash = keccak256(abi.encodePacked(digests));

        bytes32 structHash = keccak256(
            abi.encode(USER_BATCH_TYPEHASH, user, userNonce, recordsHash)
        );
        bytes32 digest = _hashTypedDataV4(structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signBatch(uint256 batchNonce) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(BATCH_TYPEHASH, batchNonce));
        bytes32 digest = _hashTypedDataV4(structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_executorKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _hashVoteRecord(
        SubVoting.VoteRecord memory record,
        address user
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    VOTE_RECORD_TYPEHASH,
                    record.timestamp,
                    record.missionId,
                    record.votingId,
                    record.questionId,
                    record.optionId,
                    record.votingAmt,
                    user
                )
            );
    }

    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19\x01", voting.domainSeparator(), structHash)
            );
    }

    function _badSigLen(uint8 seed) internal pure returns (uint256) {
        uint256 len = uint256(seed);
        if (len == 65) return 64;
        return len;
    }
}

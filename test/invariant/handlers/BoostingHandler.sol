// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Boosting} from "../../../src/vote/Boosting.sol";

contract BoostingHandler is Test {
    Boosting public boosting;

    bytes32 private constant BOOST_RECORD_TYPEHASH =
        keccak256(
            "BoostRecord(uint256 timestamp,uint256 missionId,uint256 boostingId,uint256 optionId,uint8 boostingWith,uint256 amt,address user)"
        );
    bytes32 private constant USER_SIG_TYPEHASH =
        keccak256("UserSig(address user,uint256 userNonce,bytes32 recordHash)");
    bytes32 private constant BATCH_TYPEHASH = keccak256("Batch(uint256 batchNonce)");

    uint256 private immutable _executorKey;
    address public immutable executorSigner;

    uint256[3] private _userKeys;
    address[3] private _users;

    uint256 private _nextBatchNonce;
    uint256[3] private _nextUserNonce;
    uint256 private _nextRecordId = 1;

    mapping(uint256 => uint256) public expectedBp;
    mapping(uint256 => uint256) public expectedCelb;
    mapping(uint256 => uint256) public expectedTotal;
    mapping(uint256 => uint256) public expectedCount;

    uint256[] private _expectedConsumedBatchNonces;
    uint256[] private _expectedUnconsumedBatchNonces;
    uint256[][3] private _expectedConsumedUserNonces;
    uint256[][3] private _expectedUnconsumedUserNonces;

    constructor(Boosting _boosting, uint256 executorKey_) {
        boosting = _boosting;
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
        uint256 optionSeed,
        uint256 boostTypeSeed,
        uint256 amtSeed
    ) external {
        uint256 userIdx = bound(userSeed, 0, 2);
        uint256 optionId = bound(optionSeed, 1, 3);
        uint8 boostType = uint8(bound(boostTypeSeed, 0, 1));
        uint256 amount = bound(amtSeed, 1, 1_000_000);

        Boosting.BoostRecord memory record = _newRecord(
            userIdx,
            optionId,
            boostType,
            amount
        );

        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = _newBatch(userIdx, record, false, 0);

        uint256 batchNonce = _nextBatchNonce;
        bytes memory executorSig = _signBatch(batchNonce);
        vm.prank(executorSigner);
        boosting.submitBoostBatch(batches, batchNonce, executorSig);

        _expectedConsumedBatchNonces.push(batchNonce);
        _expectedConsumedUserNonces[userIdx].push(_nextUserNonce[userIdx]);
        _accumulate(optionId, boostType, amount);

        _nextBatchNonce++;
        _nextUserNonce[userIdx]++;
    }

    function submitInvalidRecordSoftFail(
        uint256 badUserSeed,
        uint256 goodUserSeed,
        uint256 goodOptionSeed,
        uint256 goodBoostTypeSeed,
        uint256 goodAmtSeed
    ) external {
        uint256 badUserIdx = bound(badUserSeed, 0, 2);
        uint256 goodUserIdx = bound(goodUserSeed, 0, 2);
        if (goodUserIdx == badUserIdx) goodUserIdx = (goodUserIdx + 1) % 3;

        uint256 goodOptionId = bound(goodOptionSeed, 1, 3);
        uint8 goodBoostType = uint8(bound(goodBoostTypeSeed, 0, 1));
        uint256 goodAmount = bound(goodAmtSeed, 1, 1_000_000);

        Boosting.BoostRecord memory badRecord = _newRecord(
            badUserIdx,
            99, // allowedArtist=false
            0,
            100
        );
        Boosting.BoostRecord memory goodRecord = _newRecord(
            goodUserIdx,
            goodOptionId,
            goodBoostType,
            goodAmount
        );

        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](
            2
        );
        batches[0] = _newBatch(badUserIdx, badRecord, false, 0);
        batches[1] = _newBatch(goodUserIdx, goodRecord, false, 0);

        uint256 batchNonce = _nextBatchNonce;
        bytes memory executorSig = _signBatch(batchNonce);
        vm.prank(executorSigner);
        boosting.submitBoostBatch(batches, batchNonce, executorSig);

        _expectedConsumedBatchNonces.push(batchNonce);
        _expectedUnconsumedUserNonces[badUserIdx].push(_nextUserNonce[badUserIdx]);
        _expectedConsumedUserNonces[goodUserIdx].push(
            _nextUserNonce[goodUserIdx]
        );
        _accumulate(goodOptionId, goodBoostType, goodAmount);

        _nextBatchNonce++;
        _nextUserNonce[badUserIdx]++;
        _nextUserNonce[goodUserIdx]++;
    }

    function submitMalformedUserSoftFail(
        uint256 badUserSeed,
        uint256 goodUserSeed,
        uint256 goodOptionSeed,
        uint256 goodBoostTypeSeed,
        uint256 goodAmtSeed,
        uint8 badSigLenSeed
    ) external {
        uint256 badUserIdx = bound(badUserSeed, 0, 2);
        uint256 goodUserIdx = bound(goodUserSeed, 0, 2);
        if (goodUserIdx == badUserIdx) goodUserIdx = (goodUserIdx + 1) % 3;

        uint256 goodOptionId = bound(goodOptionSeed, 1, 3);
        uint8 goodBoostType = uint8(bound(goodBoostTypeSeed, 0, 1));
        uint256 goodAmount = bound(goodAmtSeed, 1, 1_000_000);
        uint256 badSigLen = _badSigLen(badSigLenSeed);

        Boosting.BoostRecord memory badRecord = _newRecord(badUserIdx, 1, 0, 100);
        Boosting.BoostRecord memory goodRecord = _newRecord(
            goodUserIdx,
            goodOptionId,
            goodBoostType,
            goodAmount
        );

        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](
            2
        );
        batches[0] = _newBatch(badUserIdx, badRecord, true, badSigLen);
        batches[1] = _newBatch(goodUserIdx, goodRecord, false, 0);

        uint256 batchNonce = _nextBatchNonce;
        bytes memory executorSig = _signBatch(batchNonce);
        vm.prank(executorSigner);
        boosting.submitBoostBatch(batches, batchNonce, executorSig);

        _expectedConsumedBatchNonces.push(batchNonce);
        _expectedUnconsumedUserNonces[badUserIdx].push(_nextUserNonce[badUserIdx]);
        _expectedConsumedUserNonces[goodUserIdx].push(
            _nextUserNonce[goodUserIdx]
        );
        _accumulate(goodOptionId, goodBoostType, goodAmount);

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

        Boosting.BoostRecord memory record = _newRecord(userIdx, 1, 0, 100);
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = _newBatch(userIdx, record, true, badSigLen);

        uint256 batchNonce = _nextBatchNonce;
        bytes memory executorSig = _signBatch(batchNonce);

        vm.expectRevert(Boosting.NoSuccessfulUser.selector);
        vm.prank(executorSigner);
        boosting.submitBoostBatch(batches, batchNonce, executorSig);

        _expectedUnconsumedBatchNonces.push(batchNonce);
        _expectedUnconsumedUserNonces[userIdx].push(_nextUserNonce[userIdx]);

        _nextBatchNonce++;
        _nextUserNonce[userIdx]++;
    }

    function submitMalformedExecutorSignature(uint256 userSeed) external {
        uint256 userIdx = bound(userSeed, 0, 2);

        Boosting.BoostRecord memory record = _newRecord(userIdx, 1, 0, 100);
        Boosting.UserBoostBatch[] memory batches = new Boosting.UserBoostBatch[](1);
        batches[0] = _newBatch(userIdx, record, false, 0);

        uint256 batchNonce = _nextBatchNonce;

        vm.expectRevert(Boosting.InvalidSignature.selector);
        vm.prank(executorSigner);
        boosting.submitBoostBatch(batches, batchNonce, hex"1234");

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
        Boosting.BoostRecord memory record,
        bool malformedSignature,
        uint256 badSigLen
    ) internal view returns (Boosting.UserBoostBatch memory) {
        bytes memory signature;
        if (malformedSignature) {
            signature = new bytes(badSigLen);
        } else {
            signature = _signUserSig(
                _userKeys[userIdx],
                _users[userIdx],
                _nextUserNonce[userIdx],
                record
            );
        }

        return
            Boosting.UserBoostBatch({
                record: record,
                userSig: Boosting.UserSig({
                    user: _users[userIdx],
                    userNonce: _nextUserNonce[userIdx],
                    signature: signature
                })
            });
    }

    function _newRecord(
        uint256 userIdx,
        uint256 optionId,
        uint8 boostType,
        uint256 amount
    ) internal returns (Boosting.BoostRecord memory) {
        uint256 recordId = _nextRecordId++;
        return
            Boosting.BoostRecord({
                recordId: recordId,
                timestamp: block.timestamp + recordId,
                missionId: 1,
                boostingId: recordId,
                userId: _userId(userIdx),
                optionId: optionId,
                boostingWith: boostType,
                amt: amount
            });
    }

    function _userId(uint256 userIdx) internal pure returns (string memory) {
        if (userIdx == 0) return "user1";
        if (userIdx == 1) return "user2";
        return "user3";
    }

    function _signUserSig(
        uint256 userKey,
        address user,
        uint256 userNonce,
        Boosting.BoostRecord memory record
    ) internal view returns (bytes memory) {
        bytes32 recordHash = _hashBoostRecord(record, user);
        bytes32 structHash = keccak256(
            abi.encode(USER_SIG_TYPEHASH, user, userNonce, recordHash)
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

    function _hashBoostRecord(
        Boosting.BoostRecord memory record,
        address user
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    BOOST_RECORD_TYPEHASH,
                    record.timestamp,
                    record.missionId,
                    record.boostingId,
                    record.optionId,
                    record.boostingWith,
                    record.amt,
                    user
                )
            );
    }

    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19\x01", boosting.domainSeparator(), structHash)
            );
    }

    function _accumulate(uint256 optionId, uint8 boostType, uint256 amount) internal {
        if (boostType == 0) {
            expectedBp[optionId] += amount;
        } else {
            expectedCelb[optionId] += amount;
        }
        expectedTotal[optionId] += amount;
        expectedCount[optionId] += 1;
    }

    function _badSigLen(uint8 seed) internal pure returns (uint256) {
        uint256 len = uint256(seed);
        if (len == 65) return 64;
        return len;
    }
}

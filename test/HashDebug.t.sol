// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MainVoting} from "../src/vote/MainVoting.sol";
import {console} from "forge-std/console.sol";

contract HashDebug is Test {
    //   슬롯 = 32 bytes
    //
    //   1 슬롯 = 32 bytes = 256 bits
    //
    //   EVM은 모든 데이터를 32바이트 단위로 처리합니다.
    //
    //   ---
    //   예시
    //
    //   uint8 voteType = 1;   // 실제 1 byte만 필요
    //
    //   하지만 EVM에서는:
    //   00000000 00000000 00000000 00000000
    //   00000000 00000000 00000000 00000000
    //   00000000 00000000 00000000 00000000
    //   00000000 00000000 00000000 00000001  ← 32 bytes (1슬롯) 사용
    //
    //   ---
    //   왜 이렇게?
    //
    //   - EVM 설계가 32바이트 워드 기반
    //   - keccak256, mstore, mload 모두 32바이트 단위로 동작
    //   - 그래서 abi.encode()도 모든 값을 32바이트로 패딩함
    //

    bytes32 private constant VOTE_RECORD_TYPEHASH =
        keccak256(
            "VoteRecord(uint256 timestamp,uint256 missionId,uint256 votingId,uint256 optionId,uint8 voteType,uint256 votingAmt,address user)"
        );

    function test_DebugHashValues() public pure {
        // 256bit == 32bytes
        uint256 timestamp_ = 1700000000;
        uint256 missionId_ = 1;
        uint256 votingId_ = 100;
        uint256 optionId_ = 2;
        uint8 voteType_ = 1;
        uint256 votingAmt_ = 500;
        address user = address(0x1234);

        console.log("=== Values ===");
        console.logBytes32(VOTE_RECORD_TYPEHASH);
        console.log(
            "timestamp:",
            timestamp_,
            abi.encode(timestamp_).length,
            "bytes"
        );
        console.log("missionId:", missionId_);
        console.log("votingId:", votingId_);
        console.log("optionId:", optionId_);
        console.log("voteType:", voteType_);
        console.log("votingAmt:", votingAmt_);
        console.log("user:", user);

        console.log("=== Memory Layout (0x100 = 256 bytes) ===");
        //function keccak256(bytes memory) returns (bytes32)
        // 인자를 딱 1개 (bytes)만 받음
    }

    function test_FreeMemoryPointer() public pure {
        uint256 ptr1;
        uint256 ptr2;
        uint256 ptr3;

        assembly {
            ptr1 := mload(0x40)

            // 32바이트 저장
            let p1 := mload(0x40)
            mstore(p1, 0x1234)
            mstore(0x40, add(p1, 0x20))
            ptr2 := mload(0x40)

            // 또 32바이트 저장
            let p2 := mload(0x40)
            mstore(p2, 0x5678)
            mstore(0x40, add(p2, 0x20))
            ptr3 := mload(0x40)
        }

        // console.log를 맨 마지막에 한번에
        console.log("1. initial:", ptr1);
        console.log("2. +32 bytes:", ptr2);
        console.log("3. +64 bytes:", ptr3);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {SubVoting} from "../../src/vote/SubVoting.sol";
import {SubVotingHandler} from "./handlers/SubVotingHandler.sol";

contract SubVotingInvariantTest is StdInvariant, Test {
    SubVoting public voting;
    SubVotingHandler public handler;

    function setUp() public {
        voting = new SubVoting(address(this));

        uint256 executorKey = 0x4444;
        address executorSigner = vm.addr(executorKey);
        voting.setExecutorSigner(executorSigner);

        voting.setQuestion(1, 1, "Question1", true);
        voting.setQuestion(1, 2, "Question2", true);
        voting.setOption(1, 1, 1, "Q1-A", true);
        voting.setOption(1, 1, 2, "Q1-B", true);
        voting.setOption(1, 2, 1, "Q2-A", true);
        voting.setOption(1, 2, 2, "Q2-B", true);

        handler = new SubVotingHandler(voting, executorKey);
        targetContract(address(handler));
    }

    function invariant_QuestionTotalsMatchExpected() public view {
        for (uint256 questionId = 1; questionId <= 2; questionId++) {
            uint256 optionSum;
            for (uint256 optionId = 1; optionId <= 2; optionId++) {
                uint256 onchainVotes = voting.getOptionVotes(1, questionId, optionId);
                assertEq(
                    onchainVotes,
                    handler.expectedOptionVotes(questionId, optionId),
                    "option votes mismatch"
                );
                optionSum += onchainVotes;
            }

            uint256 total = voting.getQuestionTotalVotes(1, questionId);
            assertEq(optionSum, total, "question total mismatch");
            assertEq(
                total,
                handler.expectedQuestionTotals(questionId),
                "expected question total mismatch"
            );
        }
    }

    function invariant_BatchNonceAccounting() public view {
        address executorSigner = handler.executorSigner();

        uint256[] memory consumed = handler.getExpectedConsumedBatchNonces();
        for (uint256 i = 0; i < consumed.length; i++) {
            assertTrue(
                voting.usedBatchNonces(executorSigner, consumed[i]),
                "expected consumed batch nonce not used"
            );
        }

        uint256[] memory unconsumed = handler.getExpectedUnconsumedBatchNonces();
        for (uint256 i = 0; i < unconsumed.length; i++) {
            assertFalse(
                voting.usedBatchNonces(executorSigner, unconsumed[i]),
                "expected unconsumed batch nonce was used"
            );
        }
    }

    function invariant_UserNonceAccounting() public view {
        for (uint256 userIdx = 0; userIdx < 3; userIdx++) {
            address user = handler.userAt(userIdx);

            uint256[] memory consumed = handler.getExpectedConsumedUserNonces(
                userIdx
            );
            for (uint256 i = 0; i < consumed.length; i++) {
                assertTrue(
                    voting.usedUserNonces(user, consumed[i]),
                    "expected consumed user nonce not used"
                );
            }

            uint256[] memory unconsumed = handler.getExpectedUnconsumedUserNonces(
                userIdx
            );
            for (uint256 i = 0; i < unconsumed.length; i++) {
                assertFalse(
                    voting.usedUserNonces(user, unconsumed[i]),
                    "expected unconsumed user nonce was used"
                );
            }
        }
    }
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {MainVoting} from "../../src/vote/MainVoting.sol";
import {MainVotingHandler} from "./handlers/MainVotingHandler.sol";

contract MainVotingInvariantTest is StdInvariant, Test {
    MainVoting public voting;
    MainVotingHandler public handler;

    function setUp() public {
        voting = new MainVoting(address(this));

        uint256 executorKey = 0x4444;
        address executorSigner = vm.addr(executorKey);
        voting.setExecutorSigner(executorSigner);

        voting.setArtist(1, 1, "Artist1", true);
        voting.setArtist(1, 2, "Artist2", true);
        voting.setArtist(1, 3, "Artist3", true);
        voting.setVoteTypeName(0, "Forget");
        voting.setVoteTypeName(1, "Remember");

        handler = new MainVotingHandler(voting, executorKey);
        targetContract(address(handler));
    }

    function invariant_ArtistStatsMatchExpected() public view {
        for (uint256 optionId = 1; optionId <= 3; optionId++) {
            (uint256 remember, uint256 forget, uint256 total) = voting
                .getArtistAggregates(1, optionId);
            assertEq(remember + forget, total, "stats mismatch");
            assertEq(remember, handler.expectedRemember(optionId), "remember mismatch");
            assertEq(forget, handler.expectedForget(optionId), "forget mismatch");
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


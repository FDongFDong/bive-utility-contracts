// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Boosting} from "../../src/vote/Boosting.sol";
import {BoostingHandler} from "./handlers/BoostingHandler.sol";

contract BoostingInvariantTest is StdInvariant, Test {
    Boosting public boosting;
    BoostingHandler public handler;

    function setUp() public {
        boosting = new Boosting(address(this));

        uint256 executorKey = 0x4444;
        address executorSigner = vm.addr(executorKey);
        boosting.setExecutorSigner(executorSigner);

        boosting.setArtist(1, 1, "Artist1", true);
        boosting.setArtist(1, 2, "Artist2", true);
        boosting.setArtist(1, 3, "Artist3", true);
        boosting.setBoostingTypeName(0, "BP");
        boosting.setBoostingTypeName(1, "CELB");

        handler = new BoostingHandler(boosting, executorKey);
        targetContract(address(handler));
    }

    function invariant_BoostAggregatesMatchExpected() public view {
        uint256 totalCount;

        for (uint256 optionId = 1; optionId <= 3; optionId++) {
            (uint256 bpAmt, uint256 celbAmt, uint256 total) = boosting
                .getBoostAggregates(1, optionId);

            assertEq(bpAmt + celbAmt, total, "aggregate mismatch");
            assertEq(bpAmt, handler.expectedBp(optionId), "bp mismatch");
            assertEq(celbAmt, handler.expectedCelb(optionId), "celb mismatch");
            assertEq(total, handler.expectedTotal(optionId), "total mismatch");

            totalCount += handler.expectedCount(optionId);
        }

        assertEq(
            boosting.boostCountByMission(1),
            totalCount,
            "boostCountByMission mismatch"
        );
    }

    function invariant_BatchNonceAccounting() public view {
        address executorSigner = handler.executorSigner();

        uint256[] memory consumed = handler.getExpectedConsumedBatchNonces();
        for (uint256 i = 0; i < consumed.length; i++) {
            assertTrue(
                boosting.usedBatchNonces(executorSigner, consumed[i]),
                "expected consumed batch nonce not used"
            );
        }

        uint256[] memory unconsumed = handler.getExpectedUnconsumedBatchNonces();
        for (uint256 i = 0; i < unconsumed.length; i++) {
            assertFalse(
                boosting.usedBatchNonces(executorSigner, unconsumed[i]),
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
                    boosting.usedUserNonces(user, consumed[i]),
                    "expected consumed user nonce not used"
                );
            }

            uint256[] memory unconsumed = handler.getExpectedUnconsumedUserNonces(
                userIdx
            );
            for (uint256 i = 0; i < unconsumed.length; i++) {
                assertFalse(
                    boosting.usedUserNonces(user, unconsumed[i]),
                    "expected unconsumed user nonce was used"
                );
            }
        }
    }
}


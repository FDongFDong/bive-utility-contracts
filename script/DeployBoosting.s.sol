// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Boosting} from "../src/vote/Boosting.sol";

contract DeployBoosting is Script {
    function run() external returns (Boosting) {
        // Forge CLI 옵션(--private-key, --ledger, --account) 또는 환경변수 사용
        address deployer = msg.sender;

        console.log("========================================");
        console.log("Deploying Boosting Contract");
        console.log("========================================");
        console.log("Deployer Address:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("========================================");

        vm.startBroadcast();

        Boosting boosting = new Boosting(deployer);

        console.log("");
        console.log("========================================");
        console.log("Deployment Successful!");
        console.log("========================================");
        console.log("Boosting Address:", address(boosting));
        console.log("Owner Address:", boosting.owner());
        console.log("Stored Chain ID:", boosting.CHAIN_ID());
        console.log("ExecutorSigner (not set):", boosting.executorSigner());
        console.log("========================================");

        vm.stopBroadcast();

        return boosting;
    }
}

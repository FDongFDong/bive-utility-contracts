// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {SubVoting} from "../src/vote/SubVoting.sol";

contract DeploySubVoting is Script {
    function run() external returns (SubVoting) {
        // msg.sender가 배포자 (CLI --private-key로 전달된 주소)
        address deployer = msg.sender;

        console.log("========================================");
        console.log("Deploying SubVoting Contract");
        console.log("========================================");
        console.log("Deployer Address:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("========================================");

        vm.startBroadcast();

        SubVoting voting = new SubVoting(deployer);

        console.log("");
        console.log("========================================");
        console.log("Deployment Successful!");
        console.log("========================================");
        console.log("SubVoting Address:", address(voting));
        console.log("Owner Address:", voting.owner());
        console.log("Stored Chain ID:", voting.CHAIN_ID());
        console.log("ExecutorSigner (not set):", voting.executorSigner());
        console.log("========================================");

        vm.stopBroadcast();

        return voting;
    }
}

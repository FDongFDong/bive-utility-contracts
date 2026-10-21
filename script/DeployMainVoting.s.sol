// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MainVoting} from "../src/vote/MainVoting.sol";

contract DeployMainVoting is Script {
    function run() external returns (MainVoting) {
        // Private key는 forge script 명령의 --private-key 옵션으로 전달됨
        // vm.getNonce를 사용해 현재 배포자 주소를 얻음
        address deployer = msg.sender;

        console.log("========================================");
        console.log("Deploying MainVoting Contract");
        console.log("========================================");
        console.log("Deployer Address:", deployer);
        console.log("Owner Address (same as deployer):", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("========================================");

        vm.startBroadcast();

        // MainVoting 배포 (deployer를 owner로 설정)
        MainVoting voting = new MainVoting(deployer);

        console.log("");
        console.log("========================================");
        console.log("Deployment Successful!");
        console.log("========================================");
        console.log("MainVoting Address:", address(voting));
        console.log("Owner Address:", voting.owner());
        console.log("Stored Chain ID:", voting.CHAIN_ID());
        console.log("========================================");

        vm.stopBroadcast();

        return voting;
    }
}

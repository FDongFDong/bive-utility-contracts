// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {MainVoting} from "../src/vote/MainVoting.sol";

/// @notice Loads pre-generated vote/signature payload from JSON and submits it on-chain.
/// @dev JSON 구조: UserVoteBatch[] 형식
/// [
///   {
///     "userVoteNo": 227186710,
///     "records": [{ "timestamp": ..., "missionId": ..., ... }],
///     "userBatchSig": { "user": "0x...", "userNonce": 4, "signature": "0x..." }
///   },
///   ...
/// ]
contract SubmitStressVoting is Script {
    MainVoting internal voting;

    function run() external {
        voting = MainVoting(_envOrAddress("VOTING_ADDRESS", 0x10Fb9C7BFec7d2059b65c9e70B4F58E2E6fd0eFE));
        uint256 executorKey = vm.envUint("PRIVATE_KEY");
        string memory filePath = _envOrString("STRESS_FILE", "stress-artifacts/stress-output.json");
        string memory json = vm.readFile(filePath);

        // UserVoteBatch[] 구조로 파싱
        MainVoting.UserVoteBatch[] memory batches =
            abi.decode(vm.parseJsonBytes(json, ".batches"), (MainVoting.UserVoteBatch[]));

        bytes memory executorSig = vm.parseJsonBytes(json, ".executorSig");
        uint256 batchNonce = vm.parseJsonUint(json, ".batchNonce");

        vm.startBroadcast(executorKey);
        voting.submitMultiUserBatch(batches, batchNonce, executorSig);
        vm.stopBroadcast();

        console2.log("Stress payload submitted from", filePath);
    }

    function _envOrString(string memory key, string memory defaultValue) internal returns (string memory) {
        if (vm.envExists(key)) return vm.envString(key);
        return defaultValue;
    }

    function _envOrAddress(string memory key, address defaultValue) internal returns (address) {
        if (vm.envExists(key)) return vm.envAddress(key);
        return defaultValue;
    }
}

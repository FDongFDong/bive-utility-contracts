// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {BIVENFT} from "../src/nft/BIVENFT.sol";

/**
 * @title MintBatch
 * @notice Script to mint 10,000 NFTs in batches of 500
 * @dev Usage:
 *   forge script script/MintBatch.s.sol:MintBatch \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --private-key $PRIVATE_KEY
 *
 * Environment variables:
 *   - NFT_ADDRESS: Deployed BIVENFT contract address
 *   - RECIPIENT: Address to receive the NFTs
 *   - BATCH_SIZE: (Optional) Number of NFTs per batch (default: 500, max: 500)
 *   - TOTAL_COUNT: (Optional) Total NFTs to mint (default: 10000)
 */
contract MintBatch is Script {
    function run() external {
        // Load environment variables
        address nftAddress = vm.envAddress("NFT_ADDRESS");
        address recipient = vm.envAddress("RECIPIENT");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        // Optional parameters with defaults
        uint256 batchSize = vm.envOr("BATCH_SIZE", uint256(500));
        uint256 totalCount = vm.envOr("TOTAL_COUNT", uint256(10000));

        // Validate parameters
        require(batchSize > 0 && batchSize <= 500, "Batch size must be 1-500");
        require(totalCount > 0, "Total count must be greater than 0");

        BIVENFT nft = BIVENFT(nftAddress);

        console.log("=== Batch Minting Configuration ===");
        console.log("NFT Contract:", nftAddress);
        console.log("Recipient:", recipient);
        console.log("Batch Size:", batchSize);
        console.log("Total Count:", totalCount);
        console.log("===================================\n");

        vm.startBroadcast(privateKey);

        uint256 numBatches = (totalCount + batchSize - 1) / batchSize;
        uint256 mintedCount = 0;

        console.log("Starting batch minting...");
        console.log("Total batches:", numBatches);
        console.log("");

        for (uint256 i = 0; i < numBatches; i++) {
            uint256 remainingCount = totalCount - mintedCount;
            uint256 currentBatchSize = remainingCount < batchSize
                ? remainingCount
                : batchSize;

            console.log("Batch", i + 1, "/", numBatches);

            // Mint batch (auto increment)
            uint256 mintedStartTokenId = nft.batchMint(recipient, currentBatchSize);

            console.log(
                "  Token IDs:",
                mintedStartTokenId,
                "-",
                mintedStartTokenId + currentBatchSize - 1
            );

            mintedCount += currentBatchSize;

            console.log("  Minted:", currentBatchSize, "NFTs");
            console.log("  Total minted:", mintedCount, "/", totalCount);
            console.log("  Progress:", (mintedCount * 100) / totalCount, "%");
            console.log("");
        }

        vm.stopBroadcast();

        console.log("=== Minting Complete ===");
        console.log("Total NFTs minted:", mintedCount);
        console.log("========================\n");
    }
}

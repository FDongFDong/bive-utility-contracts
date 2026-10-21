// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {BIVENFT} from "../src/nft/BIVENFT.sol";

/**
 * @title DeployNFT
 * @notice Deploy BIVENFT contract to any network
 * @dev Usage:
 *   forge script script/DeployNFT.s.sol:DeployNFT \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --private-key $PRIVATE_KEY \
 *     -vvv
 *
 * Notes:
 *   - Private key is passed via --private-key flag
 *   - NFT_NAME, NFT_SYMBOL, NFT_BASE_URI env로 초기값을 덮어쓸 수 있음
 *   - OWNER_ADDRESS env가 없으면 deployer 주소를 owner로 사용
 *
 * Networks:
 *   - Local: http://localhost:8545 (anvil)
 *   - opBNB Testnet: https://opbnb-testnet-rpc.bnbchain.org
 */
contract DeployNFT is Script {
    function run() external {
        // msg.sender는 --private-key로 전달된 주소
        address deployer = msg.sender;
        address owner = vm.envOr("OWNER_ADDRESS", deployer);
        string memory tokenName = vm.envOr("NFT_NAME", string("BIVENFT"));
        string memory tokenSymbol = vm.envOr("NFT_SYMBOL", string("BIVE"));
        string memory initialBaseURI = vm.envOr("NFT_BASE_URI", string(""));

        console.log("=== BIVENFT Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Owner:", owner);
        console.log("Name:", tokenName);
        console.log("Symbol:", tokenSymbol);
        console.log("Base URI:", initialBaseURI);
        console.log("Chain ID:", block.chainid);
        console.log("=============================\n");

        vm.startBroadcast();

        // Deploy BIVENFT
        BIVENFT nft = new BIVENFT(tokenName, tokenSymbol, initialBaseURI, owner);

        vm.stopBroadcast();

        console.log("\n=== Deployment Successful ===");
        console.log("BIVENFT Address:", address(nft));
        console.log("Owner:", nft.owner());
        console.log("Name:", nft.name());
        console.log("Symbol:", nft.symbol());
        console.log("=============================\n");

        console.log("Next steps:");
        console.log("1. Save the NFT address:");
        console.log("   export NFT_ADDRESS=%s", address(nft));
        console.log("\n2. Mint NFTs using MintBatch script:");
        console.log(
            "   forge script script/MintBatch.s.sol:MintBatch --rpc-url $RPC_URL --broadcast -vvv"
        );
        console.log("\n3. Verify on explorer (if on testnet/mainnet):");
        console.log("   - opBNB Testnet: https://testnet.opbnbscan.com/address/%s", address(nft));
    }
}

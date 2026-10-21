// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {BIVETicketNFT} from "../src/nft/BIVETicketNFT.sol";

/**
 * @title DeployTicketNFT
 * @notice BIVETicketNFT를 선택한 네트워크에 배포한다.
 * @dev TICKET_NFT_NAME, TICKET_NFT_SYMBOL, TICKET_NFT_BASE_URI,
 *      OWNER_ADDRESS 환경 변수로 생성자 값을 설정할 수 있다.
 * @dev foundry.toml의 compilation restriction이 이 컨트랙트를 Solidity 0.8.35로
 *      고정한다. 별도 ticket artifact 경로를 사용할 때는 FOUNDRY_PROFILE=ticket으로 실행한다.
 */
contract DeployTicketNFT is Script {
    function run() external {
        address deployer = msg.sender;
        address owner = vm.envOr("OWNER_ADDRESS", deployer);
        string memory tokenName = vm.envOr("TICKET_NFT_NAME", string("BIVE Ticket"));
        string memory tokenSymbol = vm.envOr("TICKET_NFT_SYMBOL", string("BIVET"));
        string memory initialBaseURI = vm.envOr("TICKET_NFT_BASE_URI", string(""));

        console.log("=== BIVETicketNFT Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Owner:", owner);
        console.log("Name:", tokenName);
        console.log("Symbol:", tokenSymbol);
        console.log("Base URI:", initialBaseURI);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast();
        BIVETicketNFT ticket = new BIVETicketNFT(tokenName, tokenSymbol, initialBaseURI, owner);
        vm.stopBroadcast();

        console.log("BIVETicketNFT Address:", address(ticket));
        console.log("Owner:", ticket.owner());
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {BIVETicketNFT} from "../src/nft/BIVETicketNFT.sol";

contract LockedTransferAttemptReceiver is IERC721Receiver {
    BIVETicketNFT private immutable _ticket;
    address private immutable _transferTarget;

    bool public transferSucceeded;

    constructor(BIVETicketNFT ticket_, address transferTarget_) {
        _ticket = ticket_;
        _transferTarget = transferTarget_;
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external override returns (bytes4) {
        (transferSucceeded,) =
            address(_ticket).call(abi.encodeCall(_ticket.transferFrom, (address(this), _transferTarget, tokenId)));
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract RejectSecondTicketReceiver is IERC721Receiver {
    uint256 private _received;

    function onERC721Received(address, address, uint256, bytes calldata) external override returns (bytes4) {
        ++_received;
        if (_received == 2) revert("second ticket rejected");
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract BIVETicketNFTTest is Test {
    BIVETicketNFT private ticket;

    address private owner = makeAddr("owner");
    address private user1 = makeAddr("user1");
    address private user2 = makeAddr("user2");
    address private operator = makeAddr("operator");

    function setUp() public {
        vm.prank(owner);
        ticket = new BIVETicketNFT("BIVE Ticket", "BIVET", "https://api.bive.com/tickets/", owner);
    }

    function test_SafeMint_RemainsUnlocked() public {
        vm.prank(owner);
        uint256 tokenId = ticket.safeMint(user1);

        assertEq(tokenId, 0);
        assertEq(ticket.ownerOf(tokenId), user1);
        assertFalse(ticket.isLocked(tokenId));
    }

    function test_Constructor_PreservesMetadataBaseURIAndOwner() public view {
        assertEq(ticket.name(), "BIVE Ticket");
        assertEq(ticket.symbol(), "BIVET");
        assertEq(ticket.owner(), owner);
    }

    function test_SupportsStandardErcInterfaces() public view {
        assertTrue(ticket.supportsInterface(type(IERC721).interfaceId));
        assertTrue(ticket.supportsInterface(type(IERC165).interfaceId));
        assertFalse(ticket.supportsInterface(0xffffffff));
    }

    function test_Constructor_RevertWhen_NameIsEmpty() public {
        vm.expectRevert(BIVETicketNFT.EmptyTokenName.selector);
        new BIVETicketNFT("", "BIVET", "", owner);
    }

    function test_Constructor_RevertWhen_SymbolIsEmpty() public {
        vm.expectRevert(BIVETicketNFT.EmptyTokenSymbol.selector);
        new BIVETicketNFT("BIVE Ticket", "", "", owner);
    }

    function test_SafeMint_RevertWhen_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        ticket.safeMint(user1);
    }

    function test_BatchMint_MintsUnlockedTokensAndReturnsStartId() public {
        vm.startPrank(owner);
        uint256 firstStartTokenId = ticket.batchMint(user1, 3);
        uint256 secondStartTokenId = ticket.batchMint(user2, 2);
        vm.stopPrank();

        assertEq(firstStartTokenId, 0);
        assertEq(secondStartTokenId, 3);
        assertEq(ticket.balanceOf(user1), 3);
        assertEq(ticket.balanceOf(user2), 2);

        for (uint256 tokenId; tokenId < 5; ++tokenId) {
            assertFalse(ticket.isLocked(tokenId));
        }
    }

    function test_BatchMint_RevertWhen_Empty() public {
        vm.prank(owner);
        vm.expectRevert(BIVETicketNFT.EmptyBatch.selector);
        ticket.batchMint(user1, 0);
    }

    function test_BatchMint_RevertWhen_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        ticket.batchMint(user1, 2);
    }

    function test_BatchMint_RevertWhen_Paused() public {
        vm.startPrank(owner);
        ticket.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        ticket.batchMint(user1, 2);
        vm.stopPrank();
    }

    function test_SetBaseURI_UpdatesExistingTokenURI() public {
        vm.startPrank(owner);
        uint256 tokenId = ticket.safeMint(user1);
        ticket.setBaseURI("ipfs://tickets/");
        vm.stopPrank();

        assertEq(ticket.tokenURI(tokenId), "ipfs://tickets/0");
    }

    function test_SetBaseURI_RevertWhen_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        ticket.setBaseURI("ipfs://unauthorized/");
    }

    function test_LockToken_LocksRegularMintAndUnlockRestoresTransfer() public {
        vm.startPrank(owner);
        uint256 tokenId = ticket.safeMint(user1);
        ticket.lockToken(tokenId);
        vm.stopPrank();

        assertTrue(ticket.isLocked(tokenId));

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(BIVETicketNFT.TokenIsLocked.selector, tokenId));
        ticket.transferFrom(user1, user2, tokenId);

        vm.prank(owner);
        ticket.unlockToken(tokenId);

        vm.prank(user1);
        ticket.transferFrom(user1, user2, tokenId);

        assertEq(ticket.ownerOf(tokenId), user2);
        assertFalse(ticket.isLocked(tokenId));
    }

    function test_LockAndUnlockToken_RevertWhen_TokenDoesNotExist() public {
        uint256 nonexistentTokenId = 999;

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(BIVETicketNFT.TokenDoesNotExist.selector, nonexistentTokenId));
        ticket.lockToken(nonexistentTokenId);

        vm.expectRevert(abi.encodeWithSelector(BIVETicketNFT.TokenDoesNotExist.selector, nonexistentTokenId));
        ticket.unlockToken(nonexistentTokenId);
        vm.stopPrank();
    }

    function test_LockAndUnlockToken_RevertWhen_NotOwner() public {
        vm.prank(owner);
        uint256 tokenId = ticket.safeMint(user1);

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        ticket.lockToken(tokenId);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        ticket.unlockToken(tokenId);
        vm.stopPrank();
    }

    function test_BatchLockAndUnlockTokens_UpdatesAllTokens() public {
        vm.prank(owner);
        ticket.batchMint(user1, 3);

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 0;
        tokenIds[1] = 1;
        tokenIds[2] = 2;

        vm.startPrank(owner);
        ticket.batchLockTokens(tokenIds);
        vm.stopPrank();

        for (uint256 i; i < tokenIds.length; ++i) {
            assertTrue(ticket.isLocked(tokenIds[i]));
        }

        vm.prank(owner);
        ticket.batchUnlockTokens(tokenIds);

        for (uint256 i; i < tokenIds.length; ++i) {
            assertFalse(ticket.isLocked(tokenIds[i]));
        }
    }

    function test_BatchLockTokens_IsAtomicWhen_TokenDoesNotExist() public {
        vm.prank(owner);
        ticket.safeMint(user1);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 999;

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(BIVETicketNFT.TokenDoesNotExist.selector, 999));
        ticket.batchLockTokens(tokenIds);

        assertFalse(ticket.isLocked(0));
    }

    function test_BatchUnlockTokens_IsAtomicWhen_TokenDoesNotExist() public {
        vm.prank(owner);
        ticket.safeMintLocked(user1);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 999;

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(BIVETicketNFT.TokenDoesNotExist.selector, 999));
        ticket.batchUnlockTokens(tokenIds);

        assertTrue(ticket.isLocked(0));
    }

    function test_BatchLockAndUnlockTokens_RevertWhen_Empty() public {
        uint256[] memory tokenIds = new uint256[](0);

        vm.startPrank(owner);
        vm.expectRevert(BIVETicketNFT.EmptyBatch.selector);
        ticket.batchLockTokens(tokenIds);

        vm.expectRevert(BIVETicketNFT.EmptyBatch.selector);
        ticket.batchUnlockTokens(tokenIds);
        vm.stopPrank();
    }

    function test_Pause_BlocksTransferAndBurnUntilUnpaused() public {
        vm.startPrank(owner);
        uint256 tokenId = ticket.safeMint(user1);
        ticket.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        ticket.burn(tokenId);
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        ticket.transferFrom(user1, user2, tokenId);

        vm.prank(owner);
        ticket.unpause();

        vm.prank(user1);
        ticket.transferFrom(user1, user2, tokenId);
        assertEq(ticket.ownerOf(tokenId), user2);
    }

    function test_TransferOwnership_MovesAdminPermissions() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        ticket.transferOwnership(newOwner);

        assertEq(ticket.owner(), newOwner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        ticket.safeMint(user1);

        vm.prank(newOwner);
        uint256 tokenId = ticket.safeMint(user1);
        assertEq(ticket.ownerOf(tokenId), user1);
    }

    function test_SafeMintLocked_MintsLockedToken() public {
        vm.prank(owner);
        uint256 tokenId = ticket.safeMintLocked(user1);

        assertEq(tokenId, 0);
        assertEq(ticket.ownerOf(tokenId), user1);
        assertTrue(ticket.isLocked(tokenId));
    }

    function test_SafeMintLocked_RevertWhen_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        ticket.safeMintLocked(user1);
    }

    function test_SafeMintLocked_BlocksHolderTransfer() public {
        vm.prank(owner);
        uint256 tokenId = ticket.safeMintLocked(user1);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(BIVETicketNFT.TokenIsLocked.selector, tokenId));
        ticket.transferFrom(user1, user2, tokenId);
    }

    function test_SafeMintLocked_BlocksApprovedOperatorTransfer() public {
        vm.prank(owner);
        uint256 tokenId = ticket.safeMintLocked(user1);

        vm.prank(user1);
        ticket.approve(operator, tokenId);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(BIVETicketNFT.TokenIsLocked.selector, tokenId));
        ticket.transferFrom(user1, user2, tokenId);
    }

    function test_SafeMintLocked_UnlockAllowsHolderTransfer() public {
        vm.prank(owner);
        uint256 tokenId = ticket.safeMintLocked(user1);

        vm.prank(owner);
        ticket.unlockToken(tokenId);

        vm.prank(user1);
        ticket.transferFrom(user1, user2, tokenId);

        assertEq(ticket.ownerOf(tokenId), user2);
        assertFalse(ticket.isLocked(tokenId));
    }

    function test_SafeMintLocked_BlocksTransferDuringReceiverCallback() public {
        LockedTransferAttemptReceiver receiver = new LockedTransferAttemptReceiver(ticket, user2);

        vm.prank(owner);
        uint256 tokenId = ticket.safeMintLocked(address(receiver));

        assertEq(ticket.ownerOf(tokenId), address(receiver));
        assertTrue(ticket.isLocked(tokenId));
        assertFalse(receiver.transferSucceeded());
    }

    function test_BatchMintLocked_MintsAllTokensLocked() public {
        vm.prank(owner);
        uint256 startTokenId = ticket.batchMintLocked(user1, 3);

        assertEq(startTokenId, 0);
        assertEq(ticket.balanceOf(user1), 3);
        for (uint256 tokenId; tokenId < 3; ++tokenId) {
            assertEq(ticket.ownerOf(tokenId), user1);
            assertTrue(ticket.isLocked(tokenId));
        }
    }

    function test_BatchMintLocked_RevertWhen_Empty() public {
        vm.prank(owner);
        vm.expectRevert(BIVETicketNFT.EmptyBatch.selector);
        ticket.batchMintLocked(user1, 0);
    }

    function test_MintModes_ShareSequentialTokenIds() public {
        vm.startPrank(owner);
        uint256 unlockedId = ticket.safeMint(user1);
        uint256 lockedStartId = ticket.batchMintLocked(user2, 2);
        uint256 lockedId = ticket.safeMintLocked(user1);
        vm.stopPrank();

        assertEq(unlockedId, 0);
        assertEq(lockedStartId, 1);
        assertEq(lockedId, 3);
        assertFalse(ticket.isLocked(0));
        assertTrue(ticket.isLocked(1));
        assertTrue(ticket.isLocked(2));
        assertTrue(ticket.isLocked(3));
    }

    function test_BatchMintLocked_IsAtomicWhenReceiverRejects() public {
        RejectSecondTicketReceiver receiver = new RejectSecondTicketReceiver();

        vm.prank(owner);
        vm.expectRevert("second ticket rejected");
        ticket.batchMintLocked(address(receiver), 3);

        assertEq(ticket.balanceOf(address(receiver)), 0);

        vm.prank(owner);
        uint256 tokenId = ticket.safeMintLocked(user1);
        assertEq(tokenId, 0);
    }

    function test_SafeMintLocked_PauseRevertsWithoutConsumingTokenId() public {
        vm.prank(owner);
        ticket.pause();

        vm.prank(owner);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        ticket.safeMintLocked(user1);

        vm.startPrank(owner);
        ticket.unpause();
        uint256 tokenId = ticket.safeMintLocked(user1);
        vm.stopPrank();

        assertEq(tokenId, 0);
        assertTrue(ticket.isLocked(tokenId));
    }

    function test_OwnerCanTransferLockedTicket() public {
        vm.prank(owner);
        uint256 tokenId = ticket.safeMintLocked(user1);

        vm.prank(user1);
        ticket.approve(owner, tokenId);

        vm.prank(owner);
        ticket.transferFrom(user1, user2, tokenId);

        assertEq(ticket.ownerOf(tokenId), user2);
        assertTrue(ticket.isLocked(tokenId));
    }

    function test_OwnerCanBurnLockedTicketAndLockIsCleared() public {
        vm.startPrank(owner);
        uint256 tokenId = ticket.safeMintLocked(user1);
        ticket.burn(tokenId);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(BIVETicketNFT.TokenDoesNotExist.selector, tokenId));
        ticket.isLocked(tokenId);
    }

    function test_HolderCannotBurnTicket() public {
        vm.prank(owner);
        uint256 tokenId = ticket.safeMintLocked(user1);

        vm.prank(user1);
        vm.expectRevert(BIVETicketNFT.OnlyOwnerCanBurn.selector);
        ticket.burn(tokenId);
    }

    function test_RenounceOwnership_PermanentlyFreezesLockedTicket() public {
        vm.startPrank(owner);
        uint256 tokenId = ticket.safeMintLocked(user1);
        ticket.renounceOwnership();
        vm.stopPrank();

        assertEq(ticket.owner(), address(0));

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(BIVETicketNFT.TokenIsLocked.selector, tokenId));
        ticket.transferFrom(user1, user2, tokenId);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        ticket.unlockToken(tokenId);

        vm.prank(owner);
        vm.expectRevert(BIVETicketNFT.OnlyOwnerCanBurn.selector);
        ticket.burn(tokenId);
    }

    function testFuzz_BatchMintModes_PreserveIdsOwnershipAndLockState(uint8 lockedCountSeed, uint8 unlockedCountSeed)
        public
    {
        uint256 lockedCount = bound(uint256(lockedCountSeed), 1, 24);
        uint256 unlockedCount = bound(uint256(unlockedCountSeed), 1, 24);

        vm.startPrank(owner);
        uint256 lockedStartTokenId = ticket.batchMintLocked(user1, lockedCount);
        uint256 unlockedStartTokenId = ticket.batchMint(user2, unlockedCount);
        uint256 finalLockedTokenId = ticket.safeMintLocked(user1);
        vm.stopPrank();

        assertEq(lockedStartTokenId, 0);
        assertEq(unlockedStartTokenId, lockedCount);
        assertEq(finalLockedTokenId, lockedCount + unlockedCount);
        assertEq(ticket.balanceOf(user1), lockedCount + 1);
        assertEq(ticket.balanceOf(user2), unlockedCount);

        for (uint256 tokenId; tokenId < lockedCount; ++tokenId) {
            assertEq(ticket.ownerOf(tokenId), user1);
            assertTrue(ticket.isLocked(tokenId));
        }

        uint256 unlockedEndTokenId = lockedCount + unlockedCount;
        for (uint256 tokenId = unlockedStartTokenId; tokenId < unlockedEndTokenId; ++tokenId) {
            assertEq(ticket.ownerOf(tokenId), user2);
            assertFalse(ticket.isLocked(tokenId));
        }

        assertEq(ticket.ownerOf(finalLockedTokenId), user1);
        assertTrue(ticket.isLocked(finalLockedTokenId));
    }

    function testFuzz_UnlockAllowsTransferForAnyLockedBatchToken(uint8 countSeed, uint8 indexSeed) public {
        uint256 count = bound(uint256(countSeed), 1, 24);
        uint256 selectedTokenId = bound(uint256(indexSeed), 0, count - 1);

        vm.prank(owner);
        ticket.batchMintLocked(user1, count);

        vm.prank(owner);
        ticket.unlockToken(selectedTokenId);

        vm.prank(user1);
        ticket.transferFrom(user1, user2, selectedTokenId);

        assertEq(ticket.ownerOf(selectedTokenId), user2);
        assertFalse(ticket.isLocked(selectedTokenId));

        for (uint256 tokenId; tokenId < count; ++tokenId) {
            if (tokenId != selectedTokenId) {
                assertEq(ticket.ownerOf(tokenId), user1);
                assertTrue(ticket.isLocked(tokenId));
            }
        }
    }
}

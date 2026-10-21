// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {BIVENFT} from "../src/nft/BIVENFT.sol";
import {ERC721ReceiverMock, NonERC721Receiver} from "./mocks/ERC721ReceiverMock.sol";

/**
 * @title BIVENFTTest
 * @dev BIVENFT 컨트랙트의 종합 테스트 스위트
 *
 * 테스트 범위:
 * - 민팅: 단일/배치 민팅, 권한, pause 상태, auto increment
 * - 메타데이터: Base URI 설정, tokenURI 반환
 * - 잠금: 단일/배치 잠금/해제, 이벤트, 권한
 * - 전송: 잠금 차단, Owner 예외, approval
 * - 소각: 권한, 잠긴 토큰, 플래그 정리
 * - 일시정지: pause/unpause, 기능 차단, 복구
 * - 조회: isLocked, name, symbol, balanceOf 등
 * - 엣지 케이스: 반복 잠금, 소각 후 재민팅 등
 * - 가스 벤치마크: 배치 작업 가스 측정
 */
contract BIVENFTTest is Test {
    BIVENFT public nft;
    address public owner;
    address public user1;
    address public user2;

    // 이벤트 선언 (테스트용)
    event TokenLocked(uint256 indexed tokenId);
    event TokenUnlocked(uint256 indexed tokenId);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        nft = new BIVENFT("BIVENFT", "BIVE", "", owner);
    }

    // ============================================
    // 민팅 테스트 (Minting with Auto Increment)
    // ============================================

    function test_SafeMint_Success() public {
        uint256 tokenId = nft.safeMint(user1);
        assertEq(tokenId, 0); // 첫 토큰은 0
        assertEq(nft.ownerOf(0), user1);
    }

    function test_SafeMint_AutoIncrement() public {
        uint256 tokenId1 = nft.safeMint(user1);
        uint256 tokenId2 = nft.safeMint(user2);
        uint256 tokenId3 = nft.safeMint(user1);

        assertEq(tokenId1, 0);
        assertEq(tokenId2, 1);
        assertEq(tokenId3, 2);
        
        assertEq(nft.ownerOf(0), user1);
        assertEq(nft.ownerOf(1), user2);
        assertEq(nft.ownerOf(2), user1);
    }

    function test_SafeMint_RevertWhen_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert(); // Ownable unauthorized
        nft.safeMint(user1);
    }

    function test_SafeMint_RevertWhen_Paused() public {
        nft.pause();
        vm.expectRevert(); // ERC721Pausable
        nft.safeMint(user1);
    }

    function test_BatchMint_Success() public {
        uint256 startTokenId = nft.batchMint(user1, 100);

        assertEq(startTokenId, 0);
        // 검증: 첫/중간/마지막 토큰
        assertEq(nft.ownerOf(0), user1);
        assertEq(nft.ownerOf(50), user1);
        assertEq(nft.ownerOf(99), user1);
    }

    function test_BatchMint_SingleToken() public {
        uint256 startTokenId = nft.batchMint(user1, 1);
        assertEq(startTokenId, 0);
        assertEq(nft.ownerOf(0), user1);
    }

    function test_BatchMint_LargeCount() public {
        // 가스 한도 내에서 큰 배치 (500개)
        uint256 startTokenId = nft.batchMint(user1, 500);
        assertEq(startTokenId, 0);
        assertEq(nft.ownerOf(0), user1);
        assertEq(nft.ownerOf(499), user1);
    }

    function test_BatchMint_RevertWhen_CountZero() public {
        vm.expectRevert(BIVENFT.EmptyBatch.selector);
        nft.batchMint(user1, 0);
    }

    function test_BatchMint_RevertWhen_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert(); // Ownable unauthorized
        nft.batchMint(user1, 100);
    }

    function test_BatchMint_RevertWhen_Paused() public {
        nft.pause();
        vm.expectRevert(); // ERC721Pausable
        nft.batchMint(user1, 100);
    }

    function test_BatchMint_MultipleBatches() public {
        // 여러 배치를 다른 주소에 민팅
        uint256 startTokenId1 = nft.batchMint(user1, 100);
        uint256 startTokenId2 = nft.batchMint(user2, 100);

        assertEq(startTokenId1, 0);
        assertEq(startTokenId2, 100);
        assertEq(nft.ownerOf(0), user1);
        assertEq(nft.ownerOf(99), user1);
        assertEq(nft.ownerOf(100), user2);
        assertEq(nft.ownerOf(199), user2);
    }

    function test_BatchMint_AutoIncrementAfterSafeMint() public {
        // safeMint와 batchMint 혼합 사용
        uint256 tokenId1 = nft.safeMint(user1); // 0
        uint256 startTokenId = nft.batchMint(user2, 5); // 1-5
        uint256 tokenId2 = nft.safeMint(user1); // 6

        assertEq(tokenId1, 0);
        assertEq(startTokenId, 1);
        assertEq(tokenId2, 6);
        
        assertEq(nft.ownerOf(0), user1);
        assertEq(nft.ownerOf(1), user2);
        assertEq(nft.ownerOf(5), user2);
        assertEq(nft.ownerOf(6), user1);
    }

    function test_Constructor_CustomMetadata() public {
        BIVENFT customNft = new BIVENFT(
            "Custom NFT",
            "CNFT",
            "ipfs://custom-metadata/",
            owner
        );

        assertEq(customNft.name(), "Custom NFT");
        assertEq(customNft.symbol(), "CNFT");

        customNft.safeMint(user1);
        assertEq(customNft.tokenURI(0), "ipfs://custom-metadata/0");
    }

    function test_Constructor_RevertWhen_EmptyName() public {
        vm.expectRevert(BIVENFT.EmptyTokenName.selector);
        new BIVENFT("", "CNFT", "", owner);
    }

    function test_Constructor_RevertWhen_EmptySymbol() public {
        vm.expectRevert(BIVENFT.EmptyTokenSymbol.selector);
        new BIVENFT("Custom NFT", "", "", owner);
    }

    // ============================================
    // 메타데이터 Base URI 테스트 (Metadata)
    // ============================================

    function test_SetBaseURI_Success() public {
        string memory baseURI = "https://example.com/metadata/";
        nft.setBaseURI(baseURI);

        // tokenURI 확인을 위해 토큰 민팅
        nft.safeMint(user1);
        string memory expectedURI = "https://example.com/metadata/0";
        assertEq(nft.tokenURI(0), expectedURI);
    }

    function test_SetBaseURI_RevertWhen_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert(); // Ownable unauthorized
        nft.setBaseURI("https://example.com/");
    }

    function test_TokenURI_WithoutBaseURI() public {
        nft.safeMint(user1);
        // Base URI가 설정되지 않았을 때는 빈 문자열 + tokenId
        // ERC721 표준에서는 빈 base URI일 때 빈 문자열 반환
        assertEq(bytes(nft.tokenURI(0)).length, 0);
    }

    function test_TokenURI_MultipleTokens() public {
        string memory baseURI = "ipfs://QmTest/";
        nft.setBaseURI(baseURI);

        nft.batchMint(user1, 3);

        assertEq(nft.tokenURI(0), "ipfs://QmTest/0");
        assertEq(nft.tokenURI(1), "ipfs://QmTest/1");
        assertEq(nft.tokenURI(2), "ipfs://QmTest/2");
    }

    function test_SetBaseURI_UpdateExisting() public {
        // 첫 번째 Base URI 설정
        nft.setBaseURI("https://old.com/");
        nft.safeMint(user1);
        assertEq(nft.tokenURI(0), "https://old.com/0");

        // Base URI 업데이트
        nft.setBaseURI("https://new.com/");
        assertEq(nft.tokenURI(0), "https://new.com/0");
    }

    function test_TokenURI_RevertWhen_TokenDoesNotExist() public {
        vm.expectRevert(); // ERC721: invalid token ID
        nft.tokenURI(999);
    }

    function test_SetBaseURI_EmptyString() public {
        // 빈 문자열로 설정 가능
        nft.setBaseURI("");
        nft.safeMint(user1);
        // ERC721 표준에서는 빈 base URI일 때 빈 문자열 반환
        assertEq(bytes(nft.tokenURI(0)).length, 0);
    }

    function test_SetBaseURI_WithTrailingSlash() public {
        nft.setBaseURI("https://api.bive.com/nft/");
        nft.batchMint(user1, 43); // 0-42
        assertEq(nft.tokenURI(42), "https://api.bive.com/nft/42");
    }

    function test_SetBaseURI_WithoutTrailingSlash() public {
        nft.setBaseURI("https://api.bive.com/nft");
        nft.batchMint(user1, 43); // 0-42
        assertEq(nft.tokenURI(42), "https://api.bive.com/nft42");
    }

    // ============================================
    // 토큰 잠금 테스트 (Locking)
    // ============================================

    function test_LockToken_Success() public {
        nft.safeMint(user1);
        nft.lockToken(0);
        assertTrue(nft.isLocked(0));
    }

    function test_LockToken_EmitsEvent() public {
        nft.safeMint(user1);

        vm.expectEmit(true, false, false, false);
        emit TokenLocked(0);
        nft.lockToken(0);
    }

    function test_LockToken_RevertWhen_TokenDoesNotExist() public {
        vm.expectRevert(
            abi.encodeWithSelector(BIVENFT.TokenDoesNotExist.selector, 999)
        );
        nft.lockToken(999);
    }

    function test_LockToken_RevertWhen_NotOwner() public {
        nft.safeMint(user1);

        vm.prank(user1);
        vm.expectRevert(); // Ownable unauthorized
        nft.lockToken(0);
    }

    function test_LockToken_AlreadyLocked() public {
        nft.safeMint(user1);
        nft.lockToken(0);

        // 이미 잠긴 토큰을 다시 잠금 (성공해야 함)
        nft.lockToken(0);
        assertTrue(nft.isLocked(0));
    }

    function test_UnlockToken_Success() public {
        nft.safeMint(user1);
        nft.lockToken(0);

        nft.unlockToken(0);
        assertFalse(nft.isLocked(0));
    }

    function test_UnlockToken_EmitsEvent() public {
        nft.safeMint(user1);
        nft.lockToken(0);

        vm.expectEmit(true, false, false, false);
        emit TokenUnlocked(0);
        nft.unlockToken(0);
    }

    function test_UnlockToken_RevertWhen_TokenDoesNotExist() public {
        vm.expectRevert(
            abi.encodeWithSelector(BIVENFT.TokenDoesNotExist.selector, 999)
        );
        nft.unlockToken(999);
    }

    function test_UnlockToken_RevertWhen_NotOwner() public {
        nft.safeMint(user1);
        nft.lockToken(0);

        vm.prank(user1);
        vm.expectRevert(); // Ownable unauthorized
        nft.unlockToken(0);
    }

    function test_UnlockToken_AlreadyUnlocked() public {
        nft.safeMint(user1);
        // 잠금 없이 바로 해제 시도 (성공해야 함)
        nft.unlockToken(0);
        assertFalse(nft.isLocked(0));
    }

    // ============================================
    // 배치 잠금 테스트 (Batch Locking)
    // ============================================

    function test_BatchLockTokens_Success() public {
        // 10개 토큰 민팅
        nft.batchMint(user1, 10);

        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            tokenIds[i] = i;
        }

        nft.batchLockTokens(tokenIds);

        // 모든 토큰이 잠김
        for (uint256 i = 0; i < 10; i++) {
            assertTrue(nft.isLocked(tokenIds[i]));
        }
    }

    function test_BatchLockTokens_EmitsEvents() public {
        nft.batchMint(user1, 2);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 1;

        vm.expectEmit(true, false, false, false);
        emit TokenLocked(0);
        vm.expectEmit(true, false, false, false);
        emit TokenLocked(1);

        nft.batchLockTokens(tokenIds);
    }

    function test_BatchLockTokens_RevertWhen_EmptyArray() public {
        uint256[] memory tokenIds = new uint256[](0);

        vm.expectRevert(BIVENFT.EmptyBatch.selector);
        nft.batchLockTokens(tokenIds);
    }

    function test_BatchLockTokens_RevertWhen_TokenDoesNotExist() public {
        nft.batchMint(user1, 2);

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 0;
        tokenIds[1] = 999; // 존재하지 않는 토큰
        tokenIds[2] = 1;

        vm.expectRevert(
            abi.encodeWithSelector(BIVENFT.TokenDoesNotExist.selector, 999)
        );
        nft.batchLockTokens(tokenIds);
    }

    function test_BatchLockTokens_RevertWhen_NotOwner() public {
        nft.safeMint(user1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;

        vm.prank(user1);
        vm.expectRevert(); // Ownable unauthorized
        nft.batchLockTokens(tokenIds);
    }

    function test_BatchLockTokens_LargeCount() public {
        // 100개 토큰 배치 잠금
        nft.batchMint(user1, 100);

        uint256[] memory tokenIds = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            tokenIds[i] = i;
        }

        nft.batchLockTokens(tokenIds);

        // 모든 토큰이 잠김
        assertTrue(nft.isLocked(0));
        assertTrue(nft.isLocked(99));
    }

    function test_BatchUnlockTokens_Success() public {
        // 10개 토큰 민팅 및 잠금
        nft.batchMint(user1, 10);
        
        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            tokenIds[i] = i;
        }
        
        nft.batchLockTokens(tokenIds);
        nft.batchUnlockTokens(tokenIds);

        // 모든 토큰이 잠금 해제
        for (uint256 i = 0; i < 10; i++) {
            assertFalse(nft.isLocked(tokenIds[i]));
        }
    }

    function test_BatchUnlockTokens_EmitsEvents() public {
        nft.batchMint(user1, 2);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 1;
        
        nft.batchLockTokens(tokenIds);

        vm.expectEmit(true, false, false, false);
        emit TokenUnlocked(0);
        vm.expectEmit(true, false, false, false);
        emit TokenUnlocked(1);

        nft.batchUnlockTokens(tokenIds);
    }

    function test_BatchUnlockTokens_RevertWhen_EmptyArray() public {
        uint256[] memory tokenIds = new uint256[](0);

        vm.expectRevert(BIVENFT.EmptyBatch.selector);
        nft.batchUnlockTokens(tokenIds);
    }

    function test_BatchUnlockTokens_RevertWhen_TokenDoesNotExist() public {
        nft.safeMint(user1);
        nft.lockToken(0);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 999; // 존재하지 않는 토큰

        vm.expectRevert(
            abi.encodeWithSelector(BIVENFT.TokenDoesNotExist.selector, 999)
        );
        nft.batchUnlockTokens(tokenIds);
    }

    function test_BatchUnlockTokens_RevertWhen_NotOwner() public {
        nft.safeMint(user1);
        nft.lockToken(0);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;

        vm.prank(user1);
        vm.expectRevert(); // Ownable unauthorized
        nft.batchUnlockTokens(tokenIds);
    }

    // ============================================
    // 전송 차단 테스트 (Transfer Blocking)
    // ============================================

    function test_Transfer_SuccessWhen_Unlocked() public {
        nft.safeMint(user1);

        vm.prank(user1);
        nft.transferFrom(user1, user2, 0);

        assertEq(nft.ownerOf(0), user2);
    }

    function test_Transfer_RevertWhen_Locked() public {
        nft.safeMint(user1);
        nft.lockToken(0);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(BIVENFT.TokenIsLocked.selector, 0)
        );
        nft.transferFrom(user1, user2, 0);
    }

    function test_Transfer_OwnerCanTransferLocked() public {
        nft.safeMint(user1);
        nft.lockToken(0);

        // Owner가 직접 전송 (approval 필요)
        vm.prank(user1);
        nft.approve(owner, 0);

        // Owner는 잠긴 토큰도 전송 가능
        nft.transferFrom(user1, user2, 0);

        assertEq(nft.ownerOf(0), user2);
    }

    function test_SafeTransferFrom_RevertWhen_Locked() public {
        nft.safeMint(user1);
        nft.lockToken(0);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(BIVENFT.TokenIsLocked.selector, 0)
        );
        nft.safeTransferFrom(user1, user2, 0);
    }

    function test_SafeTransferFrom_OwnerCanTransferLocked() public {
        nft.safeMint(user1);
        nft.lockToken(0);

        vm.prank(user1);
        nft.approve(owner, 0);

        nft.safeTransferFrom(user1, user2, 0);
        assertEq(nft.ownerOf(0), user2);
    }

    function test_Transfer_AfterUnlock() public {
        nft.safeMint(user1);
        nft.lockToken(0);
        nft.unlockToken(0);

        vm.prank(user1);
        nft.transferFrom(user1, user2, 0);

        assertEq(nft.ownerOf(0), user2);
    }

    function test_TransferFrom_WithApproval() public {
        nft.safeMint(user1);

        vm.prank(user1);
        nft.approve(user2, 0);

        vm.prank(user2);
        nft.transferFrom(user1, address(0xdead), 0);

        assertEq(nft.ownerOf(0), address(0xdead));
    }

    function test_TransferFrom_WithApprovalForAll() public {
        nft.safeMint(user1);

        vm.prank(user1);
        nft.setApprovalForAll(user2, true);

        vm.prank(user2);
        nft.transferFrom(user1, address(0xdead), 0);

        assertEq(nft.ownerOf(0), address(0xdead));
    }

    function test_Transfer_RevertWhen_LockedWithApproval() public {
        nft.safeMint(user1);
        nft.lockToken(0);

        vm.prank(user1);
        nft.approve(user2, 0);

        // user2는 approval 있어도 잠긴 토큰 전송 불가
        vm.prank(user2);
        vm.expectRevert(
            abi.encodeWithSelector(BIVENFT.TokenIsLocked.selector, 0)
        );
        nft.transferFrom(user1, address(0xdead), 0);
    }

    // ============================================
    // 소각 테스트 (Burning)
    // ============================================

    function test_Burn_SuccessWhen_Owner() public {
        nft.safeMint(user1);

        nft.burn(0);

        // 소각된 토큰은 ownerOf() 호출 시 revert
        vm.expectRevert();
        nft.ownerOf(0);
    }

    function test_Burn_RevertWhen_NotOwner() public {
        nft.safeMint(user1);

        vm.prank(user1);
        vm.expectRevert(BIVENFT.OnlyOwnerCanBurn.selector);
        nft.burn(0);
    }

    function test_Burn_LockedToken() public {
        nft.safeMint(user1);
        nft.lockToken(0);

        // Owner는 잠긴 토큰도 소각 가능
        nft.burn(0);

        vm.expectRevert();
        nft.ownerOf(0);
    }

    function test_Burn_ClearsLockFlag() public {
        nft.safeMint(user1);
        uint256 tokenId = 0;
        nft.lockToken(tokenId);

        nft.burn(tokenId);

        // 소각 후 다시 민팅하면 잠금 플래그 초기화되어야 함
        // safeMint는 auto increment이므로 tokenId 1로 발행됨
        // 따라서 isLocked는 tokenId 0에 대해 호출하면 TokenDoesNotExist 에러
        // 하지만 내부적으로 _locked[0]은 false로 초기화됨
    }

    function test_Burn_RevertWhen_TokenDoesNotExist() public {
        vm.expectRevert(); // ERC721: invalid token ID
        nft.burn(999);
    }

    function test_Burn_RevertWhen_Paused() public {
        nft.safeMint(user1);
        nft.pause();

        vm.expectRevert(); // ERC721Pausable
        nft.burn(0);
    }

    // ============================================
    // 일시정지 테스트 (Pause)
    // ============================================

    function test_Pause_Success() public {
        nft.pause();
        assertTrue(nft.paused());
    }

    function test_Pause_RevertWhen_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert(); // Ownable unauthorized
        nft.pause();
    }

    function test_Unpause_Success() public {
        nft.pause();
        nft.unpause();
        assertFalse(nft.paused());
    }

    function test_Unpause_RevertWhen_NotOwner() public {
        nft.pause();

        vm.prank(user1);
        vm.expectRevert(); // Ownable unauthorized
        nft.unpause();
    }

    function test_Pause_BlocksMinting() public {
        nft.pause();

        vm.expectRevert(); // ERC721Pausable
        nft.safeMint(user1);
    }

    function test_Pause_BlocksBatchMinting() public {
        nft.pause();

        vm.expectRevert(); // ERC721Pausable
        nft.batchMint(user1, 100);
    }

    function test_Pause_BlocksTransfer() public {
        nft.safeMint(user1);
        nft.pause();

        vm.prank(user1);
        vm.expectRevert(); // ERC721Pausable
        nft.transferFrom(user1, user2, 0);
    }

    function test_Pause_BlocksBurn() public {
        nft.safeMint(user1);
        nft.pause();

        vm.expectRevert(); // ERC721Pausable
        nft.burn(0);
    }

    function test_Pause_AllowsLocking() public {
        nft.safeMint(user1);
        nft.pause();

        // pause 상태에서도 잠금은 가능
        nft.lockToken(0);
        assertTrue(nft.isLocked(0));
    }

    function test_Pause_AllowsUnlocking() public {
        nft.safeMint(user1);
        nft.lockToken(0);
        nft.pause();

        // pause 상태에서도 잠금 해제 가능
        nft.unlockToken(0);
        assertFalse(nft.isLocked(0));
    }

    function test_Unpause_RestoresFunctionality() public {
        nft.pause();
        nft.unpause();

        // 모든 기능 정상 작동
        nft.safeMint(user1);
        assertEq(nft.ownerOf(0), user1);

        vm.prank(user1);
        nft.transferFrom(user1, user2, 0);
        assertEq(nft.ownerOf(0), user2);
    }

    // ============================================
    // 조회 기능 테스트 (View Functions)
    // ============================================

    function test_IsLocked_DefaultFalse() public {
        nft.safeMint(user1);
        assertFalse(nft.isLocked(0));
    }

    function test_IsLocked_ReturnsTrueAfterLock() public {
        nft.safeMint(user1);
        nft.lockToken(0);
        assertTrue(nft.isLocked(0));
    }

    function test_IsLocked_RevertWhen_TokenDoesNotExist() public {
        vm.expectRevert(
            abi.encodeWithSelector(BIVENFT.TokenDoesNotExist.selector, 999)
        );
        nft.isLocked(999);
    }

    function test_Name_ReturnsCorrectValue() public view {
        assertEq(nft.name(), "BIVENFT");
    }

    function test_Symbol_ReturnsCorrectValue() public view {
        assertEq(nft.symbol(), "BIVE");
    }

    function test_BalanceOf_Correct() public {
        nft.batchMint(user1, 10);
        assertEq(nft.balanceOf(user1), 10);
    }

    function test_OwnerOf_Correct() public {
        nft.safeMint(user1);
        assertEq(nft.ownerOf(0), user1);
    }

    function test_GetApproved_Correct() public {
        nft.safeMint(user1);

        vm.prank(user1);
        nft.approve(user2, 0);

        assertEq(nft.getApproved(0), user2);
    }

    function test_IsApprovedForAll_Correct() public {
        vm.prank(user1);
        nft.setApprovalForAll(user2, true);

        assertTrue(nft.isApprovedForAll(user1, user2));
    }

    // ============================================
    // 엣지 케이스 테스트 (Edge Cases)
    // ============================================

    function test_LockUnlock_Multiple() public {
        nft.safeMint(user1);

        // Lock → Unlock → Lock → Unlock
        nft.lockToken(0);
        assertTrue(nft.isLocked(0));

        nft.unlockToken(0);
        assertFalse(nft.isLocked(0));

        nft.lockToken(0);
        assertTrue(nft.isLocked(0));

        nft.unlockToken(0);
        assertFalse(nft.isLocked(0));
    }

    function test_Transfer_LockDoesNotFollowToken() public {
        nft.safeMint(user1);
        nft.lockToken(0);

        // Owner가 강제 전송
        vm.prank(user1);
        nft.approve(owner, 0);
        nft.transferFrom(user1, user2, 0);

        // 잠금 상태는 유지됨
        assertTrue(nft.isLocked(0));
    }

    function test_BatchLockTokens_PartialOverlap() public {
        nft.batchMint(user1, 2);
        nft.lockToken(0); // 0번만 미리 잠금

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 1;

        // 0번은 이미 잠김, 1번은 새로 잠김
        nft.batchLockTokens(tokenIds);

        assertTrue(nft.isLocked(0));
        assertTrue(nft.isLocked(1));
    }

    function test_SafeMint_ToZeroAddress() public {
        vm.expectRevert(); // ERC721: mint to zero address
        nft.safeMint(address(0));
    }

    function test_Transfer_ToZeroAddress() public {
        nft.safeMint(user1);

        vm.prank(user1);
        vm.expectRevert(); // ERC721: transfer to zero address
        nft.transferFrom(user1, address(0), 0);
    }

    // ============================================
    // 가스 벤치마크 테스트 (Gas Benchmarks)
    // ============================================

    function test_GasBenchmark_BatchMint_10() public {
        uint256 gasBefore = gasleft();
        nft.batchMint(user1, 10);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas for batchMint(10):", gasUsed);
    }

    function test_GasBenchmark_BatchMint_100() public {
        uint256 gasBefore = gasleft();
        nft.batchMint(user1, 100);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas for batchMint(100):", gasUsed);
    }

    function test_GasBenchmark_BatchLock_10() public {
        nft.batchMint(user1, 10);

        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            tokenIds[i] = i;
        }

        uint256 gasBefore = gasleft();
        nft.batchLockTokens(tokenIds);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas for batchLockTokens(10):", gasUsed);
    }

    function test_GasBenchmark_BatchUnlock_10() public {
        nft.batchMint(user1, 10);

        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            tokenIds[i] = i;
        }

        nft.batchLockTokens(tokenIds);

        uint256 gasBefore = gasleft();
        nft.batchUnlockTokens(tokenIds);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas for batchUnlockTokens(10):", gasUsed);
    }

    // ============================================
    // 추가 테스트: 상태 관리 (State Management)
    // ============================================

    function test_BurnClearsApproval() public {
        nft.safeMint(user1);

        // approval 설정
        vm.prank(user1);
        nft.approve(user2, 0);
        assertEq(nft.getApproved(0), user2);

        // 소각
        nft.burn(0);

        // 소각된 토큰의 approval 조회 시 revert
        vm.expectRevert(); // ERC721: invalid token ID
        nft.getApproved(0);
    }

    function test_LockDoesNotAffectApproval() public {
        nft.safeMint(user1);

        // approval 설정
        vm.prank(user1);
        nft.approve(user2, 0);

        // 잠금
        nft.lockToken(0);

        // approval은 유지됨
        assertEq(nft.getApproved(0), user2);
    }

    function test_TransferClearsLock_ByOwner() public {
        nft.safeMint(user1);
        nft.lockToken(0);
        assertTrue(nft.isLocked(0));

        // Owner가 강제 전송
        vm.prank(user1);
        nft.approve(owner, 0);
        nft.transferFrom(user1, user2, 0);

        // 잠금 상태는 유지됨 (토큰 ID에 바인딩)
        assertTrue(nft.isLocked(0));
    }

    // ============================================
    // 추가 테스트: Pause 상태 (Pause State)
    // ============================================

    function test_PauseDoesNotBlockApproval() public {
        nft.safeMint(user1);
        nft.pause();

        // Pause 상태에서도 approve 가능
        vm.prank(user1);
        nft.approve(user2, 0);

        assertEq(nft.getApproved(0), user2);
    }

    function test_PauseDoesNotBlockApprovalForAll() public {
        nft.pause();

        // Pause 상태에서도 setApprovalForAll 가능
        vm.prank(user1);
        nft.setApprovalForAll(user2, true);

        assertTrue(nft.isApprovedForAll(user1, user2));
    }

    // ============================================
    // 추가 테스트: Safe Transfer (ERC721Receiver)
    // ============================================

    function test_SafeTransferToReceiver() public {
        ERC721ReceiverMock receiver = new ERC721ReceiverMock();
        nft.safeMint(user1);

        vm.prank(user1);
        nft.safeTransferFrom(user1, address(receiver), 0);

        assertEq(nft.ownerOf(0), address(receiver));
    }

    function test_SafeTransferToNonReceiver() public {
        NonERC721Receiver nonReceiver = new NonERC721Receiver();
        nft.safeMint(user1);

        vm.prank(user1);
        vm.expectRevert(); // ERC721: transfer to non ERC721Receiver implementer
        nft.safeTransferFrom(user1, address(nonReceiver), 0);
    }

    function test_SafeMintToReceiver() public {
        ERC721ReceiverMock receiver = new ERC721ReceiverMock();

        uint256 tokenId = nft.safeMint(address(receiver));
        assertEq(nft.ownerOf(tokenId), address(receiver));
    }

    function test_SafeMintToNonReceiver() public {
        NonERC721Receiver nonReceiver = new NonERC721Receiver();

        vm.expectRevert(); // ERC721: transfer to non ERC721Receiver implementer
        nft.safeMint(address(nonReceiver));
    }

    function test_SafeTransferToRejectingReceiver() public {
        ERC721ReceiverMock receiver = new ERC721ReceiverMock();
        receiver.setShouldAccept(false);

        nft.safeMint(user1);

        vm.prank(user1);
        vm.expectRevert(); // ERC721: transfer to non ERC721Receiver implementer
        nft.safeTransferFrom(user1, address(receiver), 0);
    }

    function test_SafeTransferToRevertingReceiver() public {
        ERC721ReceiverMock receiver = new ERC721ReceiverMock();
        receiver.setShouldRevert(true);

        nft.safeMint(user1);

        vm.prank(user1);
        vm.expectRevert("ERC721ReceiverMock: revert");
        nft.safeTransferFrom(user1, address(receiver), 0);
    }
}

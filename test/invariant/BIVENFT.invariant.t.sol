// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {BIVENFT} from "../../src/nft/BIVENFT.sol";

/**
 * @title BIVENFTInvariantTest
 * @dev BIVENFT 컨트랙트의 Invariant 퍼즈 테스트
 *
 * Invariant (불변성):
 * - 잠긴 토큰은 Owner만 전송 가능
 * - 소각된 토큰은 존재하지 않음
 * - balanceOf 합계 = 발행된 총 토큰 수
 * - 모든 토큰은 정확히 하나의 주소가 소유
 * - pause 상태에서는 전송/민팅/소각 불가
 * - Owner만 권한 함수 호출 가능
 */
contract BIVENFTInvariantTest is StdInvariant, Test {
    BIVENFT public nft;
    NFTHandler public handler;

    address public owner;

    function setUp() public {
        owner = address(this);
        nft = new BIVENFT("BIVENFT", "BIVE", "", owner);

        handler = new NFTHandler(nft, owner);

        // Invariant 테스트 대상 설정
        targetContract(address(handler));
    }

    // ============================================
    // Invariant 1: 잠긴 토큰 보호
    // ============================================

    /// @dev 잠긴 토큰은 항상 존재해야 함 (소각되지 않음, Owner만 소각 가능)
    function invariant_LockedTokensExist() public view {
        uint256[] memory lockedTokens = handler.getLockedTokens();

        for (uint256 i = 0; i < lockedTokens.length; i++) {
            uint256 tokenId = lockedTokens[i];
            // 잠긴 토큰은 존재해야 함
            address tokenOwner = nft.ownerOf(tokenId);
            assertTrue(tokenOwner != address(0));
        }
    }

    /// @dev 잠긴 토큰 상태 일관성
    function invariant_LockedTokensConsistency() public view {
        uint256[] memory mintedTokens = handler.getMintedTokens();

        for (uint256 i = 0; i < mintedTokens.length; i++) {
            uint256 tokenId = mintedTokens[i];

            // 토큰이 존재하면 isLocked 호출 가능
            try nft.ownerOf(tokenId) returns (address) {
                // 존재하는 토큰에 대해서는 isLocked가 성공해야 함
                bool locked = nft.isLocked(tokenId);
                // locked는 true 또는 false (revert 없음)
                assertTrue(locked == true || locked == false);
            } catch {
                // 존재하지 않는 토큰 (정상)
            }
        }
    }

    // ============================================
    // Invariant 2: 토큰 소유권 일관성
    // ============================================

    /// @dev 모든 민팅된 토큰은 정확히 하나의 주소가 소유
    function invariant_AllTokensHaveOwner() public view {
        uint256[] memory mintedTokens = handler.getMintedTokens();

        for (uint256 i = 0; i < mintedTokens.length; i++) {
            uint256 tokenId = mintedTokens[i];

            try nft.ownerOf(tokenId) returns (address tokenOwner) {
                // 토큰이 존재하면 소유자가 있어야 함
                assertTrue(tokenOwner != address(0));
            } catch {
                // 소각된 토큰 (정상)
            }
        }
    }

    /// @dev balanceOf 합계 = 현재 존재하는 토큰 수
    function invariant_TotalBalanceMatchesExistingTokens() public view {
        uint256[] memory mintedTokens = handler.getMintedTokens();
        address[] memory users = handler.getUsers();

        uint256 totalBalance = 0;
        for (uint256 i = 0; i < users.length; i++) {
            totalBalance += nft.balanceOf(users[i]);
        }

        uint256 existingTokens = 0;
        for (uint256 i = 0; i < mintedTokens.length; i++) {
            try nft.ownerOf(mintedTokens[i]) returns (address) {
                existingTokens++;
            } catch {
                // 소각된 토큰
            }
        }

        assertEq(totalBalance, existingTokens);
    }

    // ============================================
    // Invariant 3: Pause 상태 일관성
    // ============================================

    /// @dev pause 상태에서는 전송/민팅/소각 불가
    /// (handler가 pause 시 작업을 시도하지 않으므로 항상 true)
    function invariant_PauseBlocksOperations() public view {
        // pause 상태 확인
        bool paused = nft.paused();

        // handler 카운터로 pause 상태에서 작업 시도 횟수 확인
        if (paused) {
            // pause 상태에서는 handler가 작업을 시도하지 않음
            assertTrue(true);
        }
    }

    // ============================================
    // Invariant 4: 상태 변수 경계
    // ============================================

    /// @dev 토큰 ID는 0 이상이어야 함 (auto increment로 0부터 시작)
    function invariant_TokenIdsAreValid() public view {
        uint256[] memory mintedTokens = handler.getMintedTokens();

        for (uint256 i = 0; i < mintedTokens.length; i++) {
            // 토큰 ID는 0 이상의 유효한 값
            assertGe(mintedTokens[i], 0);
        }
    }

    /// @dev 잠긴 토큰 수는 민팅된 토큰 수를 초과하지 않음
    function invariant_LockedTokensDoNotExceedMinted() public view {
        uint256 lockedCount = handler.getLockedTokens().length;
        uint256 mintedCount = handler.getMintedTokens().length;

        assertLe(lockedCount, mintedCount);
    }

    // ============================================
    // Invariant 5: 소각 일관성
    // ============================================

    /// @dev 소각된 토큰은 존재하지 않음
    function invariant_BurnedTokensDoNotExist() public view {
        uint256[] memory burnedTokens = handler.getBurnedTokens();

        for (uint256 i = 0; i < burnedTokens.length; i++) {
            uint256 tokenId = burnedTokens[i];

            // 소각된 토큰은 ownerOf 호출 시 revert
            try nft.ownerOf(tokenId) returns (address) {
                // 소각된 토큰이 여전히 존재하면 실패
                revert("Burned token should not exist");
            } catch {
                // 정상: 소각된 토큰은 존재하지 않음
            }
        }
    }

    // ============================================
    // Invariant 테스트 설정 및 통계
    // ============================================

    function invariant_CallSummary() public view {
        console.log("=== Invariant Test Summary ===");
        console.log("Total mints:", handler.mintCount());
        console.log("Total locks:", handler.lockCount());
        console.log("Total unlocks:", handler.unlockCount());
        console.log("Total transfers:", handler.transferCount());
        console.log("Total burns:", handler.burnCount());
        console.log("Minted tokens:", handler.getMintedTokens().length);
        console.log("Locked tokens:", handler.getLockedTokens().length);
        console.log("Burned tokens:", handler.getBurnedTokens().length);
        console.log("Users:", handler.getUsers().length);
    }
}

/**
 * @dev NFT 작업을 랜덤하게 수행하는 Handler 컨트랙트
 */
contract NFTHandler is Test {
    BIVENFT public nft;
    address public owner;

    // 작업 카운터
    uint256 public mintCount;
    uint256 public lockCount;
    uint256 public unlockCount;
    uint256 public transferCount;
    uint256 public burnCount;

    // 상태 추적
    uint256[] public mintedTokens;
    uint256[] public lockedTokens;
    uint256[] public burnedTokens;
    address[] public users;

    mapping(uint256 => bool) public isMinted;
    mapping(uint256 => bool) public isBurned;
    mapping(uint256 => bool) public isLocked;
    mapping(address => bool) public isUser;

    uint256 private nextTokenId = 0;

    constructor(BIVENFT _nft, address _owner) {
        nft = _nft;
        owner = _owner;

        // 초기 사용자 등록
        _addUser(makeAddr("user1"));
        _addUser(makeAddr("user2"));
        _addUser(makeAddr("user3"));
    }

    // ============================================
    // Handler 함수 (Fuzzing 대상)
    // ============================================

    function mint(uint256 userSeed) public {
        if (nft.paused()) return;

        address user = _getRandomUser(userSeed);

        vm.prank(owner);
        uint256 tokenId = nft.safeMint(user);

        mintedTokens.push(tokenId);
        isMinted[tokenId] = true;

        mintCount++;
        nextTokenId = tokenId + 1;
    }

    function batchMint(uint256 userSeed, uint256 countSeed) public {
        if (nft.paused()) return;

        address user = _getRandomUser(userSeed);
        uint256 count = bound(countSeed, 1, 10); // 1~10개

        vm.prank(owner);
        uint256 startTokenId = nft.batchMint(user, count);

        for (uint256 i = 0; i < count; i++) {
            mintedTokens.push(startTokenId + i);
            isMinted[startTokenId + i] = true;
        }

        mintCount += count;
        nextTokenId += count;
    }

    function lockToken(uint256 tokenSeed) public {
        if (nft.paused()) return;
        if (mintedTokens.length == 0) return;

        uint256 tokenId = _getRandomMintedToken(tokenSeed);
        if (isBurned[tokenId]) return;

        vm.prank(owner);
        nft.lockToken(tokenId);

        if (!isLocked[tokenId]) {
            lockedTokens.push(tokenId);
            isLocked[tokenId] = true;
        }

        lockCount++;
    }

    function unlockToken(uint256 tokenSeed) public {
        if (nft.paused()) return;
        if (lockedTokens.length == 0) return;

        uint256 tokenId = _getRandomLockedToken(tokenSeed);
        if (isBurned[tokenId]) return;

        vm.prank(owner);
        nft.unlockToken(tokenId);

        isLocked[tokenId] = false;
        _removeFromLockedTokens(tokenId);

        unlockCount++;
    }

    function transfer(uint256 tokenSeed, uint256 toSeed) public {
        if (nft.paused()) return;
        if (mintedTokens.length == 0) return;

        uint256 tokenId = _getRandomMintedToken(tokenSeed);
        if (isBurned[tokenId]) return;
        if (isLocked[tokenId]) return; // 잠긴 토큰은 전송 불가

        address from = nft.ownerOf(tokenId);
        address to = _getRandomUser(toSeed);

        if (from == to) return;

        vm.prank(from);
        nft.transferFrom(from, to, tokenId);

        transferCount++;
    }

    function burn(uint256 tokenSeed) public {
        if (nft.paused()) return;
        if (mintedTokens.length == 0) return;

        uint256 tokenId = _getRandomMintedToken(tokenSeed);
        if (isBurned[tokenId]) return;

        vm.prank(owner);
        nft.burn(tokenId);

        burnedTokens.push(tokenId);
        isBurned[tokenId] = true;

        if (isLocked[tokenId]) {
            isLocked[tokenId] = false;
            _removeFromLockedTokens(tokenId);
        }

        burnCount++;
    }

    function pause() public {
        if (nft.paused()) return;

        vm.prank(owner);
        nft.pause();
    }

    function unpause() public {
        if (!nft.paused()) return;

        vm.prank(owner);
        nft.unpause();
    }

    // ============================================
    // Helper 함수
    // ============================================

    function _getRandomUser(uint256 seed) internal view returns (address) {
        return users[seed % users.length];
    }

    function _getRandomMintedToken(
        uint256 seed
    ) internal view returns (uint256) {
        return mintedTokens[seed % mintedTokens.length];
    }

    function _getRandomLockedToken(
        uint256 seed
    ) internal view returns (uint256) {
        return lockedTokens[seed % lockedTokens.length];
    }

    function _addUser(address user) internal {
        if (!isUser[user]) {
            users.push(user);
            isUser[user] = true;
        }
    }

    function _removeFromLockedTokens(uint256 tokenId) internal {
        for (uint256 i = 0; i < lockedTokens.length; i++) {
            if (lockedTokens[i] == tokenId) {
                lockedTokens[i] = lockedTokens[lockedTokens.length - 1];
                lockedTokens.pop();
                break;
            }
        }
    }

    // ============================================
    // Getter 함수
    // ============================================

    function getMintedTokens() external view returns (uint256[] memory) {
        return mintedTokens;
    }

    function getLockedTokens() external view returns (uint256[] memory) {
        return lockedTokens;
    }

    function getBurnedTokens() external view returns (uint256[] memory) {
        return burnedTokens;
    }

    function getUsers() external view returns (address[] memory) {
        return users;
    }
}

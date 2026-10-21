// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {BIVETicketNFT} from "../../src/nft/BIVETicketNFT.sol";

/**
 * @title BIVETicketNFTInvariantTest
 * @notice BIVETicketNFT의 상태 불변성을 퍼즈로 검증한다.
 *
 * @dev 핸들러가 금지된 동작(잠긴 Ticket 전송, 일시정지 중 민팅, 비-Owner 소각)을
 *      실제로 시도하고 성공 횟수를 센다. invariant는 그 카운터가 0임을 주장하므로
 *      보호 장치가 뚫리면 즉시 실패한다. 핸들러가 시도 자체를 건너뛰면 검사가
 *      공회전하므로 그렇게 하지 않는다.
 */
contract BIVETicketNFTInvariantTest is StdInvariant, Test {
    BIVETicketNFT private ticket;
    TicketHandler private handler;

    address private owner = makeAddr("ticketOwner");

    function setUp() public {
        vm.prank(owner);
        ticket = new BIVETicketNFT("BIVETicketNFT", "TICKET", "", owner);

        handler = new TicketHandler(ticket, owner);
        targetContract(address(handler));
    }

    // ============================================
    // 잠금 상태
    // ============================================

    /// @dev 컨트랙트의 잠금 상태는 핸들러가 추적한 기대 상태와 항상 일치한다.
    function invariant_LockStateMatchesShadow() public view {
        uint256[] memory ids = handler.getMintedIds();

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 tokenId = ids[i];
            if (handler.isBurned(tokenId)) continue;

            assertEq(ticket.isLocked(tokenId), handler.expectedLocked(tokenId), "lock state diverged from shadow");
        }
    }

    /// @dev 잠긴 채로 민팅된 Ticket은 명시적으로 해제되기 전까지 잠긴 상태를 유지한다.
    function invariant_LockedMintStaysLocked() public view {
        uint256[] memory ids = handler.getLockedMintIds();

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 tokenId = ids[i];
            if (handler.isBurned(tokenId)) continue;
            if (handler.wasExplicitlyUnlocked(tokenId)) continue;

            assertTrue(ticket.isLocked(tokenId), "locked-mint ticket unlocked without unlockToken");
        }
    }

    // ============================================
    // 금지된 동작이 성공한 적이 없어야 한다
    // ============================================

    /// @dev 잠긴 Ticket을 보유자가 전송하려는 시도는 한 번도 성공하지 않는다.
    function invariant_LockedTransferNeverSucceeds() public view {
        assertEq(handler.lockedTransferSucceeded(), 0, "locked ticket was transferred");
    }

    /// @dev 일시정지 중 민팅·전송·소각 시도는 한 번도 성공하지 않는다.
    ///      세 가지를 모두 실제로 시도한다. 하나라도 빠지면 이 검사는 그만큼 헐거워진다.
    function invariant_PausedOperationNeverSucceeds() public view {
        assertEq(handler.pausedOpSucceeded(), 0, "operation succeeded while paused");
    }

    /// @dev Owner가 아닌 주소의 소각 시도는 한 번도 성공하지 않는다.
    function invariant_NonOwnerBurnNeverSucceeds() public view {
        assertEq(handler.nonOwnerBurnSucceeded(), 0, "non-owner burn succeeded");
    }

    // ============================================
    // 소유권·발행 일관성
    // ============================================

    /// @dev 사용자 balanceOf 합계는 살아 있는 Ticket 수와 같다.
    function invariant_BalanceSumMatchesLiveTickets() public view {
        address[] memory users = handler.getUsers();
        uint256 balanceSum;
        for (uint256 i = 0; i < users.length; i++) {
            balanceSum += ticket.balanceOf(users[i]);
        }

        uint256[] memory ids = handler.getMintedIds();
        uint256 live;
        for (uint256 i = 0; i < ids.length; i++) {
            if (!handler.isBurned(ids[i])) live++;
        }

        assertEq(balanceSum, live, "balance sum != live ticket count");
    }

    /// @dev tokenId는 0부터 빈틈·중복 없이 순차 발행된다.
    function invariant_TokenIdsAreSequential() public view {
        uint256[] memory ids = handler.getMintedIds();

        for (uint256 i = 0; i < ids.length; i++) {
            assertEq(ids[i], i, "tokenId not sequential");
        }
    }

    /// @dev 소각된 Ticket은 조회되지 않는다.
    function invariant_BurnedTicketsAreGone() public view {
        uint256[] memory ids = handler.getBurnedIds();

        for (uint256 i = 0; i < ids.length; i++) {
            // view를 유지하려고 staticcall로 확인한다. vm.expectRevert는 view에서 못 쓴다.
            (bool ok,) = address(ticket).staticcall(abi.encodeCall(ticket.ownerOf, (ids[i])));
            assertFalse(ok, "burned ticket still resolves an owner");
        }
    }

    function invariant_CallSummary() public view {
        console.log("=== BIVETicketNFT Invariant Summary ===");
        console.log("minted (unlocked):", handler.mintUnlockedCount());
        console.log("minted (locked)  :", handler.mintLockedCount());
        console.log("locks / unlocks  :", handler.lockCount(), handler.unlockCount());
        console.log("transfers        :", handler.transferCount());
        console.log("burns            :", handler.burnCount());
        console.log("-- blocked attempts (zero means that check is vacuous) --");
        console.log("locked transfer  :", handler.lockedTransferAttempts());
        console.log("paused op        :", handler.pausedOpAttempts());
        console.log("non-owner burn   :", handler.nonOwnerBurnAttempts());
    }
}

/**
 * @dev 퍼즈 대상 핸들러. 정상 동작과 금지 동작을 함께 시도한다.
 */
contract TicketHandler is Test {
    BIVETicketNFT private immutable ticket;
    address private immutable owner;

    uint256 public mintUnlockedCount;
    uint256 public mintLockedCount;
    uint256 public lockCount;
    uint256 public unlockCount;
    uint256 public transferCount;
    uint256 public burnCount;

    /// @dev 금지 동작이 성공한 횟수. 전부 0을 유지해야 한다.
    uint256 public lockedTransferSucceeded;
    uint256 public pausedOpSucceeded;
    uint256 public nonOwnerBurnSucceeded;

    /// @dev 금지 동작을 실제로 몇 번 시도했는지. 0이면 그 검사는 공회전한 것이다.
    uint256 public lockedTransferAttempts;
    uint256 public pausedOpAttempts;
    uint256 public nonOwnerBurnAttempts;

    uint256[] private mintedIds;
    uint256[] private lockedMintIds;
    uint256[] private burnedIds;
    address[] private users;

    mapping(uint256 => bool) public expectedLocked;
    mapping(uint256 => bool) public isBurned;
    mapping(uint256 => bool) public wasExplicitlyUnlocked;

    constructor(BIVETicketNFT ticket_, address owner_) {
        ticket = ticket_;
        owner = owner_;

        users.push(makeAddr("ticketUser1"));
        users.push(makeAddr("ticketUser2"));
        users.push(makeAddr("ticketUser3"));
    }

    // ============================================
    // 정상 동작
    // ============================================

    function mintUnlocked(uint256 userSeed) public {
        if (ticket.paused()) return;

        vm.prank(owner);
        uint256 tokenId = ticket.safeMint(_user(userSeed));

        mintedIds.push(tokenId);
        mintUnlockedCount++;
    }

    function mintLocked(uint256 userSeed) public {
        if (ticket.paused()) return;

        vm.prank(owner);
        uint256 tokenId = ticket.safeMintLocked(_user(userSeed));

        mintedIds.push(tokenId);
        lockedMintIds.push(tokenId);
        expectedLocked[tokenId] = true;
        mintLockedCount++;
    }

    function batchMintLocked(uint256 userSeed, uint256 countSeed) public {
        if (ticket.paused()) return;

        uint256 count = bound(countSeed, 1, 8);

        vm.prank(owner);
        uint256 startId = ticket.batchMintLocked(_user(userSeed), count);

        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = startId + i;
            mintedIds.push(tokenId);
            lockedMintIds.push(tokenId);
            expectedLocked[tokenId] = true;
        }
        mintLockedCount += count;
    }

    function lock(uint256 seed) public {
        uint256 tokenId = _liveTicket(seed);
        if (tokenId == type(uint256).max) return;

        vm.prank(owner);
        ticket.lockToken(tokenId);

        expectedLocked[tokenId] = true;
        // 다시 잠갔으므로 LockedMintStaysLocked 검사 대상으로 복귀시킨다.
        wasExplicitlyUnlocked[tokenId] = false;
        lockCount++;
    }

    function unlock(uint256 seed) public {
        uint256 tokenId = _liveTicket(seed);
        if (tokenId == type(uint256).max) return;

        vm.prank(owner);
        ticket.unlockToken(tokenId);

        expectedLocked[tokenId] = false;
        wasExplicitlyUnlocked[tokenId] = true;
        unlockCount++;
    }

    function transferUnlocked(uint256 seed, uint256 toSeed) public {
        if (ticket.paused()) return;

        uint256 tokenId = _liveTicketWithLock(seed, false);
        if (tokenId == type(uint256).max) return;

        address from = ticket.ownerOf(tokenId);
        address to = _user(toSeed);
        if (from == to) return;

        vm.prank(from);
        ticket.transferFrom(from, to, tokenId);
        transferCount++;
    }

    function burn(uint256 seed) public {
        if (ticket.paused()) return;

        uint256 tokenId = _liveTicket(seed);
        if (tokenId == type(uint256).max) return;

        vm.prank(owner);
        ticket.burn(tokenId);

        isBurned[tokenId] = true;
        expectedLocked[tokenId] = false;
        burnedIds.push(tokenId);
        burnCount++;
    }

    function pause() public {
        if (ticket.paused()) return;
        vm.prank(owner);
        ticket.pause();
    }

    function unpause() public {
        if (!ticket.paused()) return;
        vm.prank(owner);
        ticket.unpause();
    }

    // ============================================
    // 금지 동작 — 반드시 실패해야 한다
    // ============================================

    /// @dev 잠긴 Ticket을 보유자가 직접 전송해 본다.
    function attemptLockedTransfer(uint256 seed, uint256 toSeed) public {
        if (ticket.paused()) return;

        uint256 tokenId = _liveTicketWithLock(seed, true);
        if (tokenId == type(uint256).max) return;

        address from = ticket.ownerOf(tokenId);
        address to = _user(toSeed);
        if (from == to) return;

        lockedTransferAttempts++;
        vm.prank(from);
        try ticket.transferFrom(from, to, tokenId) {
            lockedTransferSucceeded++;
        } catch {}
    }

    /// @dev 일시정지 상태에서 민팅해 본다.
    function attemptMintWhilePaused(uint256 userSeed) public {
        if (!ticket.paused()) return;

        pausedOpAttempts++;
        vm.prank(owner);
        try ticket.safeMint(_user(userSeed)) returns (uint256) {
            pausedOpSucceeded++;
        } catch {}
    }

    /// @dev 일시정지 상태에서 전송해 본다.
    function attemptTransferWhilePaused(uint256 seed, uint256 toSeed) public {
        if (!ticket.paused()) return;

        uint256 tokenId = _liveTicketWithLock(seed, false);
        if (tokenId == type(uint256).max) return;

        address from = ticket.ownerOf(tokenId);
        address to = _user(toSeed);
        if (from == to) return;

        pausedOpAttempts++;
        vm.prank(from);
        try ticket.transferFrom(from, to, tokenId) {
            pausedOpSucceeded++;
        } catch {}
    }

    /// @dev 일시정지 상태에서 소각해 본다.
    function attemptBurnWhilePaused(uint256 seed) public {
        if (!ticket.paused()) return;

        uint256 tokenId = _liveTicket(seed);
        if (tokenId == type(uint256).max) return;

        pausedOpAttempts++;
        vm.prank(owner);
        try ticket.burn(tokenId) {
            pausedOpSucceeded++;
        } catch {}
    }

    /// @dev Owner가 아닌 주소로 소각해 본다.
    function attemptNonOwnerBurn(uint256 seed, uint256 callerSeed) public {
        uint256 tokenId = _liveTicket(seed);
        if (tokenId == type(uint256).max) return;

        address caller = _user(callerSeed);
        if (caller == owner) return;

        nonOwnerBurnAttempts++;
        vm.prank(caller);
        try ticket.burn(tokenId) {
            nonOwnerBurnSucceeded++;
        } catch {}
    }

    // ============================================
    // Helper
    // ============================================

    function _user(uint256 seed) private view returns (address) {
        return users[seed % users.length];
    }

    /// @dev 잠금 상태가 want와 일치하는, 살아 있는 Ticket을 찾는다.
    ///      일치하는 것이 나올 때까지 훑어야 시도가 특정 토큰에 몰리지 않는다.
    function _liveTicketWithLock(uint256 seed, bool want) private view returns (uint256) {
        uint256 total = mintedIds.length;
        if (total == 0) return type(uint256).max;

        uint256 start = seed % total;
        for (uint256 i = 0; i < total; i++) {
            uint256 tokenId = mintedIds[(start + i) % total];
            if (isBurned[tokenId]) continue;
            if (expectedLocked[tokenId] == want) return tokenId;
        }
        return type(uint256).max;
    }

    /// @dev 살아 있는 Ticket 하나를 고른다. 없으면 uint256 최대값을 반환한다.
    function _liveTicket(uint256 seed) private view returns (uint256) {
        uint256 total = mintedIds.length;
        if (total == 0) return type(uint256).max;

        uint256 start = seed % total;
        for (uint256 i = 0; i < total; i++) {
            uint256 tokenId = mintedIds[(start + i) % total];
            if (!isBurned[tokenId]) return tokenId;
        }
        return type(uint256).max;
    }

    // ============================================
    // Getter
    // ============================================

    function getMintedIds() external view returns (uint256[] memory) {
        return mintedIds;
    }

    function getLockedMintIds() external view returns (uint256[] memory) {
        return lockedMintIds;
    }

    function getBurnedIds() external view returns (uint256[] memory) {
        return burnedIds;
    }

    function getUsers() external view returns (address[] memory) {
        return users;
    }
}

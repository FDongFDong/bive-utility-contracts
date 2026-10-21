// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {CelebToken} from "../src/token/CelebToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract CelebTokenPermitTest is Test {
    CelebToken public token;

    // Test accounts
    address public tokenOwner;
    address public spender;
    address public recipient;
    address public attacker;

    uint256 public ownerPrivateKey;
    uint256 public spenderPrivateKey;
    uint256 public attackerPrivateKey;

    // EIP-712 constants
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // Test values
    uint256 constant TEST_VALUE = 1000 * 1e18;
    uint256 constant INITIAL_BALANCE = 10000 * 1e18;

    function setUp() public {
        // Setup private keys and addresses
        ownerPrivateKey = 0x1111;
        spenderPrivateKey = 0x2222;
        attackerPrivateKey = 0x3333;

        tokenOwner = vm.addr(ownerPrivateKey);
        spender = vm.addr(spenderPrivateKey);
        attacker = vm.addr(attackerPrivateKey);
        recipient = makeAddr("recipient");

        // Deploy token with tokenOwner as initial holder
        token = new CelebToken("CelebToken", "UTIL", tokenOwner, address(this));

        // Give tokenOwner some tokens for testing
        vm.prank(address(this));
        token.mint(tokenOwner, INITIAL_BALANCE);
    }

    // ============================================
    // Helper Functions
    // ============================================

    function _getPermitDigest(
        address owner,
        address _spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, owner, _spender, value, nonce, deadline)
        );
        return keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );
    }

    function _signPermit(
        uint256 privateKey,
        address owner,
        address _spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 digest = _getPermitDigest(owner, _spender, value, nonce, deadline);
        (v, r, s) = vm.sign(privateKey, digest);
    }

    // ============================================
    // 0. Success: Constructor metadata
    // ============================================

    function test_constructor_sets_custom_metadata() public {
        CelebToken custom = new CelebToken(
            "Custom Utility",
            "CUST",
            tokenOwner,
            address(this)
        );

        assertEq(custom.name(), "Custom Utility");
        assertEq(custom.symbol(), "CUST");
    }

    // ============================================
    // 1. Success: Normal permit + transferFrom
    // ============================================

    function test_permit_success() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(tokenOwner);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            ownerPrivateKey,
            tokenOwner,
            spender,
            TEST_VALUE,
            nonce,
            deadline
        );

        // Execute permit
        token.permit(tokenOwner, spender, TEST_VALUE, deadline, v, r, s);

        // Verify allowance
        assertEq(token.allowance(tokenOwner, spender), TEST_VALUE);
        assertEq(token.nonces(tokenOwner), nonce + 1);

        // Execute transferFrom
        vm.prank(spender);
        token.transferFrom(tokenOwner, recipient, TEST_VALUE);

        // Verify transfer
        assertEq(token.balanceOf(recipient), TEST_VALUE);
    }

    // ============================================
    // 2. Success: Approval event verification
    // ============================================

    function test_permit_emits_approval_event() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(tokenOwner);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            ownerPrivateKey,
            tokenOwner,
            spender,
            TEST_VALUE,
            nonce,
            deadline
        );

        // Expect Approval event
        vm.expectEmit(true, true, false, true);
        emit Approval(tokenOwner, spender, TEST_VALUE);

        token.permit(tokenOwner, spender, TEST_VALUE, deadline, v, r, s);
    }

    // ============================================
    // 3. Success: Transfer event verification
    // ============================================

    function test_transferFrom_emits_transfer_event() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(tokenOwner);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            ownerPrivateKey,
            tokenOwner,
            spender,
            TEST_VALUE,
            nonce,
            deadline
        );

        token.permit(tokenOwner, spender, TEST_VALUE, deadline, v, r, s);

        // Expect Transfer event
        vm.expectEmit(true, true, false, true);
        emit Transfer(tokenOwner, recipient, TEST_VALUE);

        vm.prank(spender);
        token.transferFrom(tokenOwner, recipient, TEST_VALUE);
    }

    // ============================================
    // 4. Success: Revoke allowance (permit value=0)
    // ============================================

    function test_permit_revoke_allowance() public {
        uint256 deadline = block.timestamp + 1 hours;

        // First permit with value
        uint256 nonce1 = token.nonces(tokenOwner);
        (uint8 v1, bytes32 r1, bytes32 s1) = _signPermit(
            ownerPrivateKey,
            tokenOwner,
            spender,
            TEST_VALUE,
            nonce1,
            deadline
        );
        token.permit(tokenOwner, spender, TEST_VALUE, deadline, v1, r1, s1);
        assertEq(token.allowance(tokenOwner, spender), TEST_VALUE);

        // Second permit with value=0 (revoke)
        uint256 nonce2 = token.nonces(tokenOwner);
        (uint8 v2, bytes32 r2, bytes32 s2) = _signPermit(
            ownerPrivateKey,
            tokenOwner,
            spender,
            0,
            nonce2,
            deadline
        );
        token.permit(tokenOwner, spender, 0, deadline, v2, r2, s2);

        // Verify allowance is now 0
        assertEq(token.allowance(tokenOwner, spender), 0);
    }

    // ============================================
    // 5. Fail: Expired deadline
    // ============================================

    function test_permit_expired_deadline_reverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(tokenOwner);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            ownerPrivateKey,
            tokenOwner,
            spender,
            TEST_VALUE,
            nonce,
            deadline
        );

        // Warp time past deadline
        vm.warp(deadline + 1);

        vm.expectRevert(
            abi.encodeWithSignature("ERC2612ExpiredSignature(uint256)", deadline)
        );
        token.permit(tokenOwner, spender, TEST_VALUE, deadline, v, r, s);
    }

    // ============================================
    // 6. Fail: Wrong nonce
    // ============================================

    function test_permit_wrong_nonce_reverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 wrongNonce = token.nonces(tokenOwner) + 1; // Wrong nonce

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            ownerPrivateKey,
            tokenOwner,
            spender,
            TEST_VALUE,
            wrongNonce,
            deadline
        );

        // Will revert because signature is invalid (wrong nonce in hash)
        vm.expectRevert();
        token.permit(tokenOwner, spender, TEST_VALUE, deadline, v, r, s);
    }

    // ============================================
    // 7. Fail: Invalid signature (wrong v/r/s)
    // ============================================

    function test_permit_invalid_signature_reverts() public {
        uint256 deadline = block.timestamp + 1 hours;

        // Use completely invalid signature values
        uint8 v = 28;
        bytes32 r = bytes32(uint256(1));
        bytes32 s = bytes32(uint256(2));

        vm.expectRevert();
        token.permit(tokenOwner, spender, TEST_VALUE, deadline, v, r, s);
    }

    // ============================================
    // 8. Fail: Owner != Signer
    // ============================================

    function test_permit_owner_not_signer_reverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(tokenOwner);

        // Attacker signs for tokenOwner's address
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            attackerPrivateKey, // Wrong signer
            tokenOwner,
            spender,
            TEST_VALUE,
            nonce,
            deadline
        );

        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC2612InvalidSigner(address,address)",
                attacker,
                tokenOwner
            )
        );
        token.permit(tokenOwner, spender, TEST_VALUE, deadline, v, r, s);
    }

    // ============================================
    // 9. Fail: Spender mismatch
    // ============================================

    function test_permit_spender_mismatch_reverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(tokenOwner);

        // Sign for attacker as spender
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            ownerPrivateKey,
            tokenOwner,
            attacker, // Sign for attacker
            TEST_VALUE,
            nonce,
            deadline
        );

        // Try to use permit with different spender
        vm.expectRevert();
        token.permit(tokenOwner, spender, TEST_VALUE, deadline, v, r, s);
    }

    // ============================================
    // 10. Fail: Value tampered
    // ============================================

    function test_permit_value_tampered_reverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(tokenOwner);

        // Sign for TEST_VALUE
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            ownerPrivateKey,
            tokenOwner,
            spender,
            TEST_VALUE,
            nonce,
            deadline
        );

        // Try to use permit with different value
        uint256 tamperedValue = TEST_VALUE + 1;
        vm.expectRevert();
        token.permit(tokenOwner, spender, tamperedValue, deadline, v, r, s);
    }

    // ============================================
    // 11. Fail: VerifyingContract mismatch
    // ============================================

    function test_permit_wrong_verifying_contract_reverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(tokenOwner);

        // Create a different token (different verifyingContract)
        CelebToken otherToken = new CelebToken(
            "CelebToken",
            "UTIL",
            tokenOwner,
            address(this)
        );

        // Sign using the other token's domain
        bytes32 otherStructHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, tokenOwner, spender, TEST_VALUE, nonce, deadline)
        );
        bytes32 otherDigest = keccak256(
            abi.encodePacked("\x19\x01", otherToken.DOMAIN_SEPARATOR(), otherStructHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, otherDigest);

        // Try to use on original token - should fail
        vm.expectRevert();
        token.permit(tokenOwner, spender, TEST_VALUE, deadline, v, r, s);
    }

    // ============================================
    // 12. Fail: transferFrom insufficient allowance
    // ============================================

    function test_transferFrom_insufficient_allowance_reverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(tokenOwner);
        uint256 permitValue = 10 * 1e18;
        uint256 transferAmount = 11 * 1e18; // More than permitted

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            ownerPrivateKey,
            tokenOwner,
            spender,
            permitValue,
            nonce,
            deadline
        );

        token.permit(tokenOwner, spender, permitValue, deadline, v, r, s);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                spender,
                permitValue,
                transferAmount
            )
        );
        token.transferFrom(tokenOwner, recipient, transferAmount);
    }

    // ============================================
    // 13. Frontrun scenario: Third party submits first
    // ============================================

    function test_permit_frontrun_scenario() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(tokenOwner);

        // Owner creates permit signature for spender
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            ownerPrivateKey,
            tokenOwner,
            spender,
            TEST_VALUE,
            nonce,
            deadline
        );

        // Attacker frontruns and submits the permit first
        vm.prank(attacker);
        token.permit(tokenOwner, spender, TEST_VALUE, deadline, v, r, s);

        // Verify allowance is set (frontrun succeeded)
        assertEq(token.allowance(tokenOwner, spender), TEST_VALUE);
        assertEq(token.nonces(tokenOwner), nonce + 1);

        // Original submitter tries to submit - fails due to nonce mismatch
        vm.prank(spender);
        vm.expectRevert(); // Nonce already used
        token.permit(tokenOwner, spender, TEST_VALUE, deadline, v, r, s);

        // But the allowance is already set, so spender can still use it
        vm.prank(spender);
        token.transferFrom(tokenOwner, recipient, TEST_VALUE);
        assertEq(token.balanceOf(recipient), TEST_VALUE);
    }

    // ============================================
    // Events
    // ============================================

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
}

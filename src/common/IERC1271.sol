// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev ERC-1271: contract wallet signature validation standard.
interface IERC1271 {
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4);
}

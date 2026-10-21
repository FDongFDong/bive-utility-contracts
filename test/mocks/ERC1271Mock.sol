// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title ERC1271Mock
 * @dev ERC-1271 스마트 컨트랙트 지갑 서명 테스트용 Mock
 */
contract ERC1271Mock {
    bytes4 public constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 public constant ERC1271_INVALID = 0xffffffff;

    address public signer;
    bool public shouldReturnValid;

    constructor(address _signer) {
        signer = _signer;
        shouldReturnValid = true;
    }

    function setSigner(address _signer) external {
        signer = _signer;
    }

    function setReturnValid(bool _valid) external {
        shouldReturnValid = _valid;
    }

    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4) {
        if (!shouldReturnValid) {
            return ERC1271_INVALID;
        }

        address recovered = ECDSA.recover(hash, signature);
        if (recovered == signer) {
            return ERC1271_MAGIC_VALUE;
        }
        return ERC1271_INVALID;
    }
}

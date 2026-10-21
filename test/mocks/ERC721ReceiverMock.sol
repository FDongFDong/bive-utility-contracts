// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title ERC721ReceiverMock
 * @dev ERC721 Safe Transfer 테스트용 Mock
 */
contract ERC721ReceiverMock is IERC721Receiver {
    bytes4 public constant RECEIVER_MAGIC_VALUE = 0x150b7a02;

    bool public shouldAccept;
    bool public shouldRevert;

    constructor() {
        shouldAccept = true;
        shouldRevert = false;
    }

    function setShouldAccept(bool _accept) external {
        shouldAccept = _accept;
    }

    function setShouldRevert(bool _revert) external {
        shouldRevert = _revert;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external view override returns (bytes4) {
        if (shouldRevert) {
            revert("ERC721ReceiverMock: revert");
        }
        if (shouldAccept) {
            return RECEIVER_MAGIC_VALUE;
        }
        return bytes4(0);
    }
}

/**
 * @title NonERC721Receiver
 * @dev ERC721Receiver를 구현하지 않은 컨트랙트
 */
contract NonERC721Receiver {
    // ERC721Receiver를 구현하지 않음
}

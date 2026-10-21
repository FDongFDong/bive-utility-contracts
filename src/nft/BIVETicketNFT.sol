// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.5.0
pragma solidity ^0.8.27;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {ERC721Pausable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BIVETicketNFT
 * @notice BIVENFT와 동일한 관리 기능에 원자적 잠금 민팅을 추가한 티켓 NFT
 *
 * 주요 기능:
 * - 일반 단일/배치 민팅
 * - 발행 즉시 잠기는 단일/배치 민팅
 * - 개별/배치 잠금 및 잠금 해제
 * - Owner 전용 민팅, 잠금, 일시정지, 소각
 *
 * @dev 잠금 민팅은 ERC721Receiver 콜백 전에 잠금 상태를 기록하여
 *      수신자가 민팅 도중 토큰을 전송할 수 없도록 한다.
 * @dev 배치 크기는 명시적으로 제한하지 않으며, 호출자가 체인 가스 한도에
 *      맞게 트랜잭션을 분할해야 한다.
 */
contract BIVETicketNFT is ERC721, ERC721Pausable, Ownable, ERC721Burnable {
    uint256 private _nextTokenId;
    string private _baseTokenURI;
    mapping(uint256 => bool) private _locked;

    event BatchMinted(address indexed to, uint256 indexed startTokenId, uint256 count);
    event TokenLocked(uint256 indexed tokenId);
    event TokenUnlocked(uint256 indexed tokenId);

    error TokenIsLocked(uint256 tokenId);
    error TokenDoesNotExist(uint256 tokenId);
    error OnlyOwnerCanBurn();
    error EmptyBatch();
    error EmptyTokenName();
    error EmptyTokenSymbol();

    constructor(string memory tokenName, string memory tokenSymbol, string memory initialBaseURI, address initialOwner)
        ERC721(tokenName, tokenSymbol)
        Ownable(initialOwner)
    {
        if (bytes(tokenName).length == 0) revert EmptyTokenName();
        if (bytes(tokenSymbol).length == 0) revert EmptyTokenSymbol();
        _baseTokenURI = initialBaseURI;
    }

    /**
     * @notice 모든 민팅, 전송, 소각을 일시정지한다.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice 일시정지를 해제한다.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice 잠기지 않은 NFT 한 개를 민팅한다.
     * @param to NFT를 받을 주소
     * @return tokenId 발행된 토큰 ID
     */
    function safeMint(address to) external onlyOwner returns (uint256 tokenId) {
        tokenId = _safeMintNext(to, false);
    }

    /**
     * @notice 발행 즉시 잠기는 NFT 한 개를 민팅한다.
     * @param to NFT를 받을 주소
     * @return tokenId 발행된 토큰 ID
     */
    function safeMintLocked(address to) external onlyOwner returns (uint256 tokenId) {
        tokenId = _safeMintNext(to, true);
    }

    /**
     * @notice 잠기지 않은 NFT를 동일 주소에 배치 민팅한다.
     * @param to NFT를 받을 주소
     * @param count 민팅할 개수
     * @return startTokenId 첫 번째로 발행된 토큰 ID
     */
    function batchMint(address to, uint256 count) external onlyOwner returns (uint256 startTokenId) {
        if (count == 0) revert EmptyBatch();

        startTokenId = _nextTokenId;
        for (uint256 i; i < count;) {
            _safeMintNext(to, false);
            unchecked {
                ++i;
            }
        }

        emit BatchMinted(to, startTokenId, count);
    }

    /**
     * @notice 발행 즉시 잠기는 NFT를 동일 주소에 배치 민팅한다.
     * @param to NFT를 받을 주소
     * @param count 민팅할 개수
     * @return startTokenId 첫 번째로 발행된 토큰 ID
     */
    function batchMintLocked(address to, uint256 count) external onlyOwner returns (uint256 startTokenId) {
        if (count == 0) revert EmptyBatch();

        startTokenId = _nextTokenId;
        for (uint256 i; i < count;) {
            _safeMintNext(to, true);
            unchecked {
                ++i;
            }
        }

        emit BatchMinted(to, startTokenId, count);
    }

    /**
     * @notice 모든 토큰의 메타데이터 Base URI를 변경한다.
     */
    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @notice 토큰의 사용자 전송을 잠근다.
     */
    function lockToken(uint256 tokenId) external onlyOwner {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist(tokenId);
        _locked[tokenId] = true;
        emit TokenLocked(tokenId);
    }

    /**
     * @notice 토큰의 사용자 전송 잠금을 해제한다.
     */
    function unlockToken(uint256 tokenId) external onlyOwner {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist(tokenId);
        _locked[tokenId] = false;
        emit TokenUnlocked(tokenId);
    }

    /**
     * @notice 여러 토큰의 사용자 전송을 잠근다.
     */
    function batchLockTokens(uint256[] calldata tokenIds) external onlyOwner {
        uint256 length = tokenIds.length;
        if (length == 0) revert EmptyBatch();

        for (uint256 i; i < length;) {
            uint256 tokenId = tokenIds[i];
            if (_ownerOf(tokenId) == address(0)) {
                revert TokenDoesNotExist(tokenId);
            }
            _locked[tokenId] = true;
            emit TokenLocked(tokenId);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice 여러 토큰의 사용자 전송 잠금을 해제한다.
     */
    function batchUnlockTokens(uint256[] calldata tokenIds) external onlyOwner {
        uint256 length = tokenIds.length;
        if (length == 0) revert EmptyBatch();

        for (uint256 i; i < length;) {
            uint256 tokenId = tokenIds[i];
            if (_ownerOf(tokenId) == address(0)) {
                revert TokenDoesNotExist(tokenId);
            }
            _locked[tokenId] = false;
            emit TokenUnlocked(tokenId);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice 토큰의 잠금 상태를 반환한다.
     */
    function isLocked(uint256 tokenId) public view returns (bool) {
        if (_ownerOf(tokenId) == address(0)) {
            revert TokenDoesNotExist(tokenId);
        }
        return _locked[tokenId];
    }

    /**
     * @notice Owner가 토큰을 소각한다.
     * @dev 토큰 보유자 또는 승인된 운영자는 소각할 수 없다.
     */
    function burn(uint256 tokenId) public override {
        if (msg.sender != owner()) revert OnlyOwnerCanBurn();
        _burn(tokenId);
    }

    /**
     * @dev 다음 토큰 ID를 안전 민팅하고 선택적으로 콜백 전에 잠근다.
     */
    function _safeMintNext(address to, bool locked) private returns (uint256 tokenId) {
        tokenId = _nextTokenId++;

        if (locked) {
            _locked[tokenId] = true;
        }

        _safeMint(to, tokenId);

        if (locked) {
            emit TokenLocked(tokenId);
        }
    }

    /**
     * @dev 잠긴 토큰의 사용자 전송을 차단한다.
     *      잠금을 우회하는 주체는 보유자(from)가 아니라 호출자(auth)다.
     *      transferFrom 경로에서 auth는 msg.sender이므로 호출자가 owner()여야
     *      이 검사를 통과한다. 통과하더라도 super._update의 _checkAuthorized는
     *      그대로 적용되므로, Owner라도 승인받지 않은 남의 잠긴 토큰은 옮길 수 없다.
     *      소각 시에는 더 이상 사용하지 않는 잠금 상태를 삭제한다.
     */
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Pausable)
        returns (address)
    {
        address from = _ownerOf(tokenId);

        if (from != address(0) && to != address(0) && _locked[tokenId] && auth != owner()) {
            revert TokenIsLocked(tokenId);
        }

        if (to == address(0) && _locked[tokenId]) {
            delete _locked[tokenId];
        }

        return super._update(to, tokenId, auth);
    }
}

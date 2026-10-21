// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.5.0
pragma solidity ^0.8.27;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {
    ERC721Burnable
} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {
    ERC721Pausable
} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BIVENFT
 * @dev BIVE 유틸리티 NFT 컨트랙트
 *
 * 주요 기능:
 * - ERC721 표준 NFT 구현
 * - 일시정지 기능 (pause 시 민팅/전송/소각 모두 차단)
 * - 토큰 잠금 기능 (개별 토큰 전송 차단, 단 호출자가 Owner면 우회)
 * - 배치 민팅 (가스 효율적인 대량 발행)
 * - Owner만 소각 가능 (사용자는 자신의 NFT도 소각 불가)
 *
 * 보안/권한 특징:
 * - Owner만 민팅, 잠금, 일시정지, 소각 가능
 * - 잠긴 토큰 전송은 호출자가 Owner일 때만 허용 (ERC721 승인 검사는 별도로 적용)
 * - 소각은 잠금과 무관하게 Owner 전용 (burn이 자체적으로 차단)
 * - 중앙집중형 권한 모델(Owner 키에 강하게 의존)
 */
contract BIVENFT is ERC721, ERC721Pausable, Ownable, ERC721Burnable {
    // ============================================
    // 상태 변수
    // ============================================
    /// @dev 다음 발행될 토큰 ID (auto increment)
    uint256 private _nextTokenId;

    /// @dev 토큰 메타데이터 Base URI
    string private _baseTokenURI;

    /// @dev 토큰별 잠금 상태 (true = 잠김, false = 잠금 해제)
    mapping(uint256 => bool) private _locked;

    // ============================================
    // 이벤트
    // ============================================

    /// @dev 배치 민팅이 완료되었을 때 발생
    event BatchMinted(
        address indexed to,
        uint256 indexed startTokenId,
        uint256 count
    );

    /// @dev 토큰이 잠겼을 때 발생
    event TokenLocked(uint256 indexed tokenId);

    /// @dev 토큰 잠금이 해제되었을 때 발생
    event TokenUnlocked(uint256 indexed tokenId);

    // ============================================
    // 에러
    // ============================================

    /// @dev 잠긴 토큰을 전송하려 할 때 발생
    error TokenIsLocked(uint256 tokenId);

    /// @dev 존재하지 않는 토큰에 대한 작업 시도 시 발생
    error TokenDoesNotExist(uint256 tokenId);

    /// @dev Owner가 아닌 주소가 소각을 시도할 때 발생
    error OnlyOwnerCanBurn();

    /// @dev 배치 작업 시 빈 배열 또는 0 개수가 전달되었을 때 발생
    error EmptyBatch();
    /// @dev 생성자 tokenName이 빈 문자열일 때 발생
    error EmptyTokenName();
    /// @dev 생성자 tokenSymbol이 빈 문자열일 때 발생
    error EmptyTokenSymbol();

    // ============================================
    // 생성자
    // ============================================

    /**
     * @dev 컨트랙트 초기화
     * @param tokenName ERC721 name
     * @param tokenSymbol ERC721 symbol
     * @param initialBaseURI 초기 Base URI (빈 문자열 허용)
     * @param initialOwner 초기 소유자 주소 (민팅, 잠금, 일시정지 권한)
     */
    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        string memory initialBaseURI,
        address initialOwner
    ) ERC721(tokenName, tokenSymbol) Ownable(initialOwner) {
        if (bytes(tokenName).length == 0) revert EmptyTokenName();
        if (bytes(tokenSymbol).length == 0) revert EmptyTokenSymbol();
        _baseTokenURI = initialBaseURI;
    }

    // ============================================
    // 일시정지 기능
    // ============================================

    /**
     * @dev 모든 NFT 민팅/전송/소각을 일시정지 (긴급 상황용)
     * @notice Owner만 호출 가능
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev 일시정지 해제
     * @notice Owner만 호출 가능
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    // ============================================
    // 민팅 기능
    // ============================================

    /**
     * @dev 단일 NFT 안전 민팅 (auto increment)
     * @param to 받을 주소
     * @return tokenId 발행된 토큰 ID
     * @notice Owner만 호출 가능
     * @notice 토큰 ID는 0부터 자동 증가
     */
    function safeMint(address to) public onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        return tokenId;
    }

    /**
     * @dev 배치 민팅 (auto increment)
     * @param to 받을 주소
     * @param count 민팅할 개수
     * @return startTokenId 시작 토큰 ID
     * @notice Owner만 호출 가능
     * @notice 가스 효율을 위해 루프로 구현
     * @notice 토큰 ID는 현재 _nextTokenId부터 자동 증가
     * @notice 개수 상한은 없다. 호출자가 체인 가스 한도에 맞춰 나눠 제출해야 한다
     */
    function batchMint(
        address to,
        uint256 count
    ) external onlyOwner returns (uint256 startTokenId) {
        if (count == 0) revert EmptyBatch();

        startTokenId = _nextTokenId;

        for (uint256 i = 0; i < count; i++) {
            _safeMint(to, _nextTokenId++);
        }

        emit BatchMinted(to, startTokenId, count);
    }

    // ============================================
    // 메타데이터 관리
    // ============================================

    /**
     * @dev Base URI 설정
     * @param baseURI 새로운 Base URI
     * @notice Owner만 호출 가능
     * @notice 모든 토큰의 tokenURI는 baseURI + tokenId 형태
     */
    function setBaseURI(string memory baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    /**
     * @dev Base URI 반환 (내부 함수)
     * @return 현재 설정된 Base URI
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    // ============================================
    // 토큰 잠금 기능
    // ============================================

    /**
     * @dev 토큰 잠금 (전송 차단)
     * @param tokenId 잠글 토큰 ID
     * @notice Owner만 호출 가능
     * @notice 잠긴 토큰은 호출자가 Owner일 때만 전송 가능 (_update 참고)
     */
    function lockToken(uint256 tokenId) external onlyOwner {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist(tokenId);
        _locked[tokenId] = true;
        emit TokenLocked(tokenId);
    }

    /**
     * @dev 토큰 잠금 해제
     * @param tokenId 잠금 해제할 토큰 ID
     * @notice Owner만 호출 가능
     */
    function unlockToken(uint256 tokenId) external onlyOwner {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist(tokenId);
        _locked[tokenId] = false;
        emit TokenUnlocked(tokenId);
    }

    /**
     * @dev 여러 토큰을 배치로 잠금
     * @param tokenIds 잠글 토큰 ID 배열
     * @notice Owner만 호출 가능
     * @notice 개수 상한은 없다. 호출자가 체인 가스 한도에 맞춰 나눠 제출해야 한다
     */
    function batchLockTokens(uint256[] calldata tokenIds) external onlyOwner {
        if (tokenIds.length == 0) revert EmptyBatch();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (_ownerOf(tokenId) == address(0)) {
                revert TokenDoesNotExist(tokenId);
            }
            _locked[tokenId] = true;
            emit TokenLocked(tokenId);
        }
    }

    /**
     * @dev 여러 토큰의 잠금을 배치로 해제
     * @param tokenIds 잠금 해제할 토큰 ID 배열
     * @notice Owner만 호출 가능
     * @notice 개수 상한은 없다. 호출자가 체인 가스 한도에 맞춰 나눠 제출해야 한다
     */
    function batchUnlockTokens(uint256[] calldata tokenIds) external onlyOwner {
        if (tokenIds.length == 0) revert EmptyBatch();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (_ownerOf(tokenId) == address(0)) {
                revert TokenDoesNotExist(tokenId);
            }
            _locked[tokenId] = false;
            emit TokenUnlocked(tokenId);
        }
    }

    // ============================================
    // 조회 기능
    // ============================================

    /**
     * @dev 토큰 잠금 상태 확인
     * @param tokenId 확인할 토큰 ID
     * @return 잠김(true) 또는 잠금 해제(false)
     * @notice 존재하지 않는 토큰에 대해서는 TokenDoesNotExist 에러 발생
     */
    function isLocked(uint256 tokenId) public view returns (bool) {
        if (_ownerOf(tokenId) == address(0)) {
            revert TokenDoesNotExist(tokenId);
        }
        return _locked[tokenId];
    }

    // ============================================
    // 소각 기능
    // ============================================

    /**
     * @dev 토큰 소각 (Owner만 가능)
     * @param tokenId 소각할 토큰 ID
     * @notice Owner만 호출 가능
     * @notice 사용자는 자신의 NFT도 소각할 수 없음 (Owner 권한 필요)
     */
    function burn(uint256 tokenId) public override {
        if (msg.sender != owner()) revert OnlyOwnerCanBurn();
        _burn(tokenId);
    }

    // ============================================
    // 내부 함수 오버라이드
    // ============================================

    /**
     * @dev ERC721 전송 로직 오버라이드
     * @param to 받을 주소
     * @param tokenId 토큰 ID
     * @param auth 전송을 요청한 호출자. transferFrom/safeTransferFrom 경로에서는
     *             msg.sender이고, 내부 _transfer 경로에서는 address(0)이다.
     *             토큰 보유자(from)가 아니라는 점에 주의.
     * @return 이전 소유자 주소
     *
     * 전송/잠금 규칙:
     * - paused() == true: 민팅/전송/소각 모두 차단 (ERC721Pausable 기본 동작)
     * - 잠긴 토큰 전송:
     *   - from != 0, to != 0, _locked[tokenId] == true 인 경우
     *   - auth != owner() 이면 TokenIsLocked 에러로 revert
     *   - 잠금을 우회하는 조건은 "보유자가 Owner"가 아니라 "호출자가 Owner"다.
     *   - 우회하더라도 뒤이은 super._update의 _checkAuthorized는 그대로 적용된다.
     *     따라서 Owner라도 승인받지 않은 남의 잠긴 토큰은 옮길 수 없다
     *     (ERC721InsufficientApproval). 잠긴 토큰의 강제 회수 기능은 없다.
     *   - 내부 _transfer 경로는 auth가 address(0)이라 이 검사에 걸린다.
     *     현재 그 경로를 쓰는 함수는 없다.
     *   - renounceOwnership() 이후에는 owner()가 address(0)이 되어 잠금 해제도
     *     소각도 불가능해진다. 잠긴 토큰이 영구히 묶이므로 호출하면 안 된다.
     * - 소각 시 잠금 플래그 정리 (to == address(0))
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721, ERC721Pausable) returns (address) {
        address from = _ownerOf(tokenId);

        // 민팅(from == address(0)) 또는 소각(to == address(0))이 아닌
        // 일반 전송에서만 잠금 상태를 검사
        if (
            from != address(0) &&
            to != address(0) &&
            _locked[tokenId] &&
            auth != owner()
        ) {
            revert TokenIsLocked(tokenId);
        }

        // 소각 시 잠금 플래그 초기화 (상태 일관성 유지)
        if (to == address(0) && _locked[tokenId]) {
            delete _locked[tokenId];
        }

        return super._update(to, tokenId, auth);
    }
}

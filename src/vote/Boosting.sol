// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SignatureVerifier} from "./lib/SignatureVerifier.sol";
import {ReasonCodes} from "./lib/ReasonCodes.sol";

/**
 * @title Boosting
 * @author Celebus Team
 * @notice 팬 부스팅 시스템의 메인 컨트랙트
 *
 * @dev 이 컨트랙트는 "1트랜잭션 N레코드" 구조를 사용합니다.
 *      - 각 사용자가 자신의 레코드에 개별 서명 (1:1 서명 방식)
 *      - 여러 유저의 배치를 하나의 트랜잭션으로 묶어서 처리
 *
 * 보안 특징:
 *      - EIP-712 구조화 서명으로 피싱 방지
 *      - 이중 서명 검증: 사용자 서명 + Executor 서명
 *      - Nonce 시스템으로 리플레이 공격 방지
 *      - Chain ID 검증으로 크로스체인 리플레이 방지
 *
 * 데이터 흐름:
 *      1. 유저가 오프체인에서 부스팅 레코드에 서명
 *      2. 백엔드(executorSigner)가 여러 유저의 배치를 수집
 *      3. executorSigner가 배치 전체에 서명 후 submitBoostBatch 호출
 *      4. 컨트랙트가 모든 서명 검증 후 부스팅 저장
 */
contract Boosting is Ownable2Step, EIP712 {
    // ========================================
    // 상수 (Constants)
    // ========================================

    /**
     * @dev 한 트랜잭션에서 처리할 수 있는 최대 부스팅 레코드 수
     *      가스 한도 초과 방지 및 DoS 공격 방지 목적
     */
    uint256 public constant MAX_RECORDS_PER_BATCH = 2000;

    /**
     * @dev userId 등 문자열 필드의 최대 길이
     *      과도한 스토리지 사용 방지
     */
    uint256 public constant MAX_STRING_LENGTH = 100;

    /**
     * @dev 부스팅 타입의 최대값 (0부터 시작하므로 1이면 0,1 두 가지)
     *      0: BP (Boosting Point)
     *      1: CELB (Celebus Token)
     */
    uint8 public constant MAX_BOOST_TYPE = 1;

    /// @notice 레코드당 amt 상한 (집계 오버플로우 DoS 방지)
    uint256 public constant MAX_BOOST_AMT = 1e30;

    // UserBoostFailed / UserMissionResult 이벤트용 실패 사유 코드
    //
    // 값은 ReasonCodes 라이브러리가 유일한 출처다. 여기서는 도메인 이름으로 alias만 한다.
    // 새 코드가 필요하면 lib/ReasonCodes.sol에 추가한다. 여기에 숫자를 직접 적으면
    // 세 컨트랙트가 어긋난다.
    //
    // Boosting은 1·9·12번을 쓰지 않는다.
    //   1  : 1:1 구조라 배치 크기 개념이 없다
    //   9  : 레코드가 1건이라 배치 내 ID 불일치가 발생할 수 없다
    //   12 : 선택지 2단 구조가 없다 (SubVoting 전용)
    uint8 private constant REASON_INVALID_USER_SIGNATURE = ReasonCodes.INVALID_USER_SIGNATURE; // EIP-712 서명 불일치
    uint8 private constant REASON_USER_NONCE_INVALID = ReasonCodes.USER_NONCE_INVALID; // 이미 사용된 nonce
    uint8 private constant REASON_INVALID_BOOST_TYPE = ReasonCodes.INVALID_TYPE;       // MAX_BOOST_TYPE 초과. 0=BP는 유효값
    uint8 private constant REASON_ARTIST_NOT_ALLOWED = ReasonCodes.TARGET_NOT_ALLOWED; // 비활성화된 아티스트에 부스팅 시도
    uint8 private constant REASON_STRING_TOO_LONG = ReasonCodes.STRING_TOO_LONG;       // userId > 100자
    uint8 private constant REASON_DUPLICATE_HASH = ReasonCodes.DUPLICATE_RECORD;       // 이미 처리된 해시
    uint8 private constant REASON_ZERO_AMT = ReasonCodes.ZERO_AMOUNT;                  // 0포인트 부스팅 (무효)
    uint8 private constant REASON_INVALID_OPTION_ID = ReasonCodes.INVALID_OPTION_ID;   // optionId = 0
    uint8 private constant REASON_AMOUNT_TOO_LARGE = ReasonCodes.AMOUNT_TOO_LARGE;     // amt 상한 초과

    // ========================================
    // EIP-712 타입 해시 (Type Hashes)
    // ========================================

    /**
     * @dev 개별 부스팅 레코드의 EIP-712 타입 해시
     *
     * 참고: userId는 서명 대상에서 제외됩니다.
     *      - 프론트엔드에서 userId를 모르는 상태로 서명 가능
     *      - 백엔드가 DB에서 userId를 조회하여 BoostRecord에 주입
     */
    bytes32 private constant BOOST_RECORD_TYPEHASH =
        keccak256(
            "BoostRecord(uint256 timestamp,uint256 missionId,uint256 boostingId,uint256 optionId,uint8 boostingWith,uint256 amt,address user)"
        );

    /**
     * @dev 유저 서명의 EIP-712 타입 해시
     *
     * 구조: 유저 주소 + 유저 nonce + 레코드 해시
     * 유저가 자신의 부스팅 레코드를 서명으로 승인합니다.
     */
    bytes32 private constant USER_SIG_TYPEHASH =
        keccak256("UserSig(address user,uint256 userNonce,bytes32 recordHash)");

    /**
     * @dev 전체 배치의 EIP-712 타입 해시
     *
     * executorSigner가 배치를 묶어서 서명할 때 사용됩니다.
     * batchNonce로 리플레이 공격을 방지합니다.
     */
    bytes32 private constant BATCH_TYPEHASH =
        keccak256("Batch(uint256 batchNonce)");

    // ========================================
    // 커스텀 에러 (Custom Errors)
    // ========================================

    /// @dev 주소가 zero address일 때
    error ZeroAddress();

    /// @dev 서명 검증 실패
    error InvalidSignature();

    /// @dev 배포 시 체인과 현재 체인이 다를 때 (크로스체인 리플레이 방지)
    error BadChain();

    /// @dev 배치 nonce가 이미 사용됨
    error BatchNonceAlreadyUsed();

    /// @dev 전체 배치가 MAX_RECORDS_PER_BATCH 초과
    error BatchTooLarge();

    /// @dev 입력 레코드/배치가 비어있음
    error InvalidRecordIndices();

    /// @dev 호출자가 owner도 executorSigner도 아님
    error NotOwnerOrExecutor();

    /// @dev 빈 문자열 입력
    error EmptyText();

    /// @dev optionId가 0일 때
    error InvalidOptionId(uint256 optionId);

    /// @dev 부스팅 타입이 유효하지 않음 (MAX_BOOST_TYPE 초과)
    error InvalidBoostType(uint8 boostType);

    /// @dev 배치 내 모든 유저가 실패함
    error NoSuccessfulUser();

    // ========================================
    // 구조체 (Structs)
    // ========================================

    /**
     * @dev 개별 부스팅 레코드
     * @param recordId 백엔드가 생성하는 유니크 ID (서명 데이터에는 포함 X)
     * @param timestamp 부스팅 생성 시간 (오프체인에서 설정)
     * @param missionId 미션(캠페인) ID
     * @param boostingId 부스팅 세션 ID
     * @param userId 유저 식별자 (오프체인 시스템의 유저 ID)
     * @param optionId 부스팅 대상 아티스트 ID
     * @param boostingWith 부스팅 타입 (0: BP, 1: CELB)
     * @param amt 부스팅 수량 (포인트)
     */
    struct BoostRecord {
        uint256 recordId;
        uint256 timestamp;
        uint256 missionId;
        uint256 boostingId;
        string userId;
        uint256 optionId;
        uint8 boostingWith;
        uint256 amt;
    }

    /**
     * @dev 유저의 서명 정보
     * @param user 유저의 지갑 주소
     * @param userNonce 유저의 고유 nonce (리플레이 방지)
     * @param signature 유저의 EIP-712 서명
     */
    struct UserSig {
        address user;
        uint256 userNonce;
        bytes signature;
    }

    /**
     * @dev 한 유저의 부스팅 배치
     *      유저는 하나의 레코드에 하나의 서명을 제출합니다. (1:1 방식)
     * @param record 유저의 부스팅 레코드
     * @param userSig 유저의 서명 정보
     */
    struct UserBoostBatch {
        BoostRecord record;
        UserSig userSig;
    }

    // ========================================
    // 상태 변수 (State Variables)
    // ========================================

    /**
     * @dev 부스팅 레코드 저장소
     *      key: 레코드 해시 (recordDigest)
     *      value: 부스팅 레코드 데이터
     */
    mapping(bytes32 => BoostRecord) public boosts;

    /**
     * @dev 미션/부스팅 세션별 부스팅 해시 목록
     *      조회 시 특정 missionId + boostingId의 모든 부스팅을 찾을 때 사용
     *
     * 구조: missionId => boostingId => recordDigest[]
     *
     * 주의: boostingId당 레코드 수 제한이 없으므로 대량 데이터 시
     *       조회 가스비에 주의하세요.
     */
    mapping(uint256 => mapping(uint256 => bytes32[]))
        private boostHashesByBoostingId;

    /**
     * @dev 유저별 사용된 Nonce 추적 (중복 방지)
     *      리플레이 공격 방지용
     */
    mapping(address => mapping(uint256 => bool)) public usedUserNonces;

    /**
     * @dev executorSigner별 배치 nonce 사용 여부 (중복 방지)
     *
     * 구조: signer => nonce => used
     */
    mapping(address => mapping(uint256 => bool)) public usedBatchNonces;

    /**
     * @dev 레코드 소비 여부
     *      동일한 레코드를 중복 제출하는 것을 방지
     *
     * 구조: recordDigest => consumed
     */
    /// @dev 중복 레코드 방지 (recordDigest => consumed)
    ///      recordDigest(recordHash)는 EIP-712 BoostRecord 해시이며 user를 포함합니다.
    mapping(bytes32 => bool) public consumed;

    /**
     * @dev 배포 시점의 체인 ID (immutable)
     *      크로스체인 리플레이 공격 방지용
     */
    uint256 public immutable CHAIN_ID;

    /**
     * @dev 배치 제출 권한이 있는 서명자 주소
     *      백엔드 서버의 핫월렛 주소가 설정됩니다.
     */
    address public executorSigner;

    /**
     * @dev 미션/부스팅 세션별 부스팅 횟수
     *
     * 구조: missionId => boostingId => count
     */
    mapping(uint256 => mapping(uint256 => uint256)) public boostCount;

    /**
     * @dev 미션별 전체 부스팅 횟수
     *
     * 구조: missionId => count
     */
    mapping(uint256 => uint256) public boostCountByMission;

    /**
     * @dev 아티스트 이름 저장소
     *
     * 구조: missionId => optionId => artistName
     */
    mapping(uint256 => mapping(uint256 => string)) public artistName;

    /**
     * @dev 아티스트 부스팅 허용 여부
     *      false인 아티스트에게는 부스팅할 수 없습니다.
     *
     * 구조: missionId => optionId => allowed
     */
    mapping(uint256 => mapping(uint256 => bool)) public allowedArtist;

    /**
     * @dev 부스팅 타입별 이름
     *      0 => "BP", 1 => "CELB"
     */
    mapping(uint8 => string) public boostingTypeName;

    /**
     * @dev 아티스트별 총 부스팅 포인트
     *
     * 구조: missionId => optionId => totalAmt
     */
    mapping(uint256 => mapping(uint256 => uint256)) public artistTotalAmt;

    /// @dev 아티스트별 BP 타입 부스팅 총량
    mapping(uint256 => mapping(uint256 => uint256)) public artistBpAmt;

    /// @dev 아티스트별 CELB 타입 부스팅 총량
    mapping(uint256 => mapping(uint256 => uint256)) public artistCelbAmt;

    // ========================================
    // 이벤트 (Events)
    // ========================================

    /**
     * @dev executorSigner가 변경되었을 때 발생
     * @param oldSigner 이전 서명자 주소
     * @param newSigner 새로운 서명자 주소
     */
    event ExecutorSignerChanged(
        address indexed oldSigner,
        address indexed newSigner
    );

    /**
     * @dev 유저의 부스팅이 처리되었을 때 발생
     * @param batchDigest 전체 배치의 해시
     * @param user 유저 주소
     * @param userNonce 사용된 유저 nonce
     */
    event UserBoostProcessed(
        bytes32 indexed batchDigest,
        address indexed user,
        uint256 userNonce
    );

    /**
     * @dev 유저 부스팅 처리 실패 (Soft-fail)
     * @param batchDigest 전체 배치의 해시
     * @param user 유저 주소
     * @param userNonce 시도된 유저 nonce
     * @param reasonCode 실패 사유 코드
     */
    event UserBoostFailed(
        bytes32 indexed batchDigest,
        address indexed user,
        uint256 userNonce,
        uint8 reasonCode
    );

    /**
     * @dev 전체 배치가 처리 완료되었을 때 발생
     * @param batchDigest 배치 해시
     * @param executorSigner 실행한 서명자
     * @param batchNonce 사용된 배치 nonce
     * @param recordCount 실제 저장된 레코드 수 (중복 제외)
     * @param userCount 참여한 유저 수
     * @param failedUserCount 검증 실패한 유저 수
     */
    event BatchProcessed(
        bytes32 indexed batchDigest,
        address indexed executorSigner,
        uint256 batchNonce,
        uint256 recordCount,
        uint256 userCount,
        uint256 failedUserCount
    );

    /**
     * @dev 아티스트 정보가 설정되었을 때 발생
     * @param missionId 미션 ID
     * @param optionId 아티스트 옵션 ID
     * @param name 아티스트 이름
     * @param allowed 부스팅 허용 여부
     */
    event ArtistSet(
        uint256 indexed missionId,
        uint256 indexed optionId,
        string name,
        bool allowed
    );

    /**
     * @dev 부스팅 타입 이름이 설정되었을 때 발생
     * @param typeId 부스팅 타입 (0: BP, 1: CELB)
     * @param name 타입 이름
     */
    event BoostingTypeSet(uint8 indexed typeId, string name);

    /**
     * @dev boostingId별 부스팅 결과 이벤트
     *      MainVoting/SubVoting의 UserMissionResult와 일관성 유지
     * @param boostingId 부스팅 세션 ID
     * @param success 모든 레코드 성공 여부 (일부 실패 시 false)
     * @param failedRecordIds 실패한 레코드 ID 배열
     * @param reasonCode 실패 사유 코드 (모두 성공 시 0)
     */
    event UserMissionResult(
        uint256 indexed boostingId,
        bool success,
        uint256[] failedRecordIds,
        uint8 reasonCode
    );

    // ========================================
    // 생성자 및 관리자 함수 (Constructor & Admin)
    // ========================================

    /**
     * @dev 컨트랙트 생성자
     * @param initialOwner 초기 소유자 주소
     *
     * EIP712 도메인:
     *   - name: "Boosting"
     *   - version: "1"
     *
     * 체인 ID가 immutable로 저장되어 크로스체인 리플레이를 방지합니다.
     */
    constructor(
        address initialOwner
    ) EIP712("Boosting", "1") Ownable(initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
        CHAIN_ID = block.chainid;
    }

    /**
     * @dev 배치 실행 서명자 설정
     * @param s 새로운 서명자 주소
     */
    function setExecutorSigner(address s) external onlyOwner {
        if (s == address(0)) revert ZeroAddress();
        address oldSigner = executorSigner;
        executorSigner = s;
        emit ExecutorSignerChanged(oldSigner, s);
    }

    /**
     * @dev 아티스트 정보 설정
     * @param missionId 미션 ID
     * @param optionId 아티스트 옵션 ID
     * @param name 아티스트 이름 (조회 시 표시용)
     * @param allowed_ 부스팅 허용 여부 (false면 해당 아티스트에게 부스팅 불가)
     *
     * 사용 예:
     *   setArtist(1, 1, "BTS", true)  // 미션1의 옵션1로 BTS 등록
     *   setArtist(1, 1, "BTS", false) // BTS 부스팅 비활성화
     */
    function setArtist(
        uint256 missionId,
        uint256 optionId,
        string calldata name,
        bool allowed_
    ) external onlyOwner {
        if (optionId == 0) revert InvalidOptionId(optionId);
        if (bytes(name).length == 0) revert EmptyText();
        artistName[missionId][optionId] = name;
        allowedArtist[missionId][optionId] = allowed_;
        emit ArtistSet(missionId, optionId, name, allowed_);
    }

    /**
     * @dev 부스팅 타입 이름 설정
     * @param typeId 부스팅 타입 ID (0: BP, 1: CELB)
     * @param name 타입 이름
     *
     * 초기 설정 예:
     *   setBoostingTypeName(0, "BP")
     *   setBoostingTypeName(1, "CELB")
     */
    function setBoostingTypeName(
        uint8 typeId,
        string calldata name
    ) external onlyOwner {
        if (typeId > MAX_BOOST_TYPE) revert InvalidBoostType(typeId);
        if (bytes(name).length == 0) revert EmptyText();
        boostingTypeName[typeId] = name;
        emit BoostingTypeSet(typeId, name);
    }

    // ========================================
    // 내부 함수: 해시 로직 (Internal: Hash Logic)
    // ========================================

    /**
     * @dev 개별 부스팅 레코드의 EIP-712 구조체 해시 생성
     * @param record 부스팅 레코드
     * @return result 레코드의 해시값
     *
     * 참고: userId는 서명 검증에 포함되지 않습니다.
     *   프론트엔드에서 userId 없이 서명하고,
     *   백엔드가 나중에 userId를 주입합니다.
     *   inline assembly로 가스 최적화
     */
    function _hashBoostRecord(
        BoostRecord calldata record,
        address user
    ) internal pure returns (bytes32 result) {
        bytes32 typeHash = BOOST_RECORD_TYPEHASH;
        uint256 timestamp_ = record.timestamp;
        uint256 missionId_ = record.missionId;
        uint256 boostingId_ = record.boostingId;
        uint256 optionId_ = record.optionId;
        uint8 boostingWith_ = record.boostingWith;
        uint256 amt_ = record.amt;

        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, typeHash)
            mstore(add(ptr, 0x20), timestamp_)
            mstore(add(ptr, 0x40), missionId_)
            mstore(add(ptr, 0x60), boostingId_)
            mstore(add(ptr, 0x80), optionId_)
            mstore(add(ptr, 0xa0), boostingWith_)
            mstore(add(ptr, 0xc0), amt_)
            mstore(add(ptr, 0xe0), user)
            result := keccak256(ptr, 0x100)
        }
    }

    /**
     * @dev 유저 서명의 EIP-712 다이제스트 생성
     * @param user 유저 주소
     * @param nonce_ 유저 nonce
     * @param recordHash 레코드 해시
     * @return EIP-712 서명용 다이제스트
     *
     * 유저는 이 다이제스트에 서명하여 레코드를 승인합니다.
     */
    function _hashUserSig(
        address user,
        uint256 nonce_,
        bytes32 recordHash
    ) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(USER_SIG_TYPEHASH, user, nonce_, recordHash)
                )
            );
    }

    /**
     * @dev 전체 배치의 EIP-712 다이제스트 생성
     * @param batchNonce 배치 nonce
     * @return EIP-712 서명용 다이제스트
     *
     * executorSigner가 이 다이제스트에 서명하여 배치 제출을 승인합니다.
     */
    function _hashBatch(uint256 batchNonce) internal view returns (bytes32) {
        return
            _hashTypedDataV4(keccak256(abi.encode(BATCH_TYPEHASH, batchNonce)));
    }

    // ========================================
    // 내부 함수: Nonce 관리 (Internal: Nonce Management)
    // ========================================

    /**
     * @dev 유저 nonce 중복 검증
     * @param user 유저 주소
     * @param nonce_ 제출된 nonce
     * @return 검증 성공 여부 (사용되지 않은 nonce면 true)
     */
    function _checkUserNonce(address user, uint256 nonce_) internal view returns (bool) {
        return !usedUserNonces[user][nonce_];
    }

    /**
     * @dev 배치 nonce 검증 및 사용 처리 (중복 방지)
     * @param signer 서명자 주소
     * @param nonce_ 사용할 nonce
     */
    function _consumeBatchNonce(address signer, uint256 nonce_) internal {
        if (usedBatchNonces[signer][nonce_]) revert BatchNonceAlreadyUsed();
        usedBatchNonces[signer][nonce_] = true;
    }

    // ========================================
    // 내부 함수: 검증 로직 (Internal: Validation)
    // ========================================

    /**
     * @dev 문자열 필드 길이 검증 (soft-fail 버전)
     * @param record 검증할 레코드
     * @return true if valid, false if any string exceeds MAX_STRING_LENGTH
     */
    function _validateStringsSoft(BoostRecord calldata record) internal pure returns (bool) {
        return bytes(record.userId).length <= MAX_STRING_LENGTH;
    }

    /**
     * @dev 단일 레코드의 해시 생성
     * @param record 부스팅 레코드
     * @return recordDigest 레코드의 해시
     */
    function _buildRecordDigest(
        BoostRecord calldata record,
        address user
    ) internal pure returns (bytes32 recordDigest) {
        recordDigest = _hashBoostRecord(record, user);
    }

    // ========================================
    // 내부 함수: 서명 검증 (Internal: Signature Verification)
    // ========================================

    /**
     * @dev 유저 서명 검증 (Soft-fail 방식)
     *      실패 시 revert 대신 (false, reasonCode) 반환 + 이벤트 발생
     *      → 다른 유저의 부스팅은 계속 처리 가능
     *
     * @param userSig 유저 서명 정보
     * @param recordHash 레코드 해시
     * @param batchDigest 배치 다이제스트 (이벤트용)
     * @return ok 검증 성공 여부
     * @return reasonCode 실패 사유 코드 (성공 시 0)
     */
    function _verifyUserSignatureSoft(
        UserSig calldata userSig,
        bytes32 recordHash,
        bytes32 batchDigest
    ) internal returns (bool ok, uint8 reasonCode) {
        address user = userSig.user;
        uint256 nonce_ = userSig.userNonce;

        // 1) 서명 검증
        bytes32 userSigDigest = _hashUserSig(user, nonce_, recordHash);

        if (!SignatureVerifier.isValidSignature(user, userSigDigest, userSig.signature)) {
            reasonCode = REASON_INVALID_USER_SIGNATURE;
            emit UserBoostFailed(batchDigest, user, nonce_, reasonCode);
            return (false, reasonCode);
        }

        // 2) Nonce 중복 검증
        if (!_checkUserNonce(user, nonce_)) {
            reasonCode = REASON_USER_NONCE_INVALID;
            emit UserBoostFailed(batchDigest, user, nonce_, reasonCode);
            return (false, reasonCode);
        }
        return (true, 0);
    }

    // ========================================
    // 내부 함수: 저장 로직 (Internal: Storage)
    // ========================================

    /**
     * @dev 검증 통과한 부스팅 레코드들을 스토리지에 저장
     *      MainVoting/SubVoting과 동일한 패턴: 유저 배치당 1개의 UserMissionResult 이벤트
     *
     * @param batches 배치 배열
     * @param recordHashes 레코드 해시 배열
     * @param userOk 유저별 검증 통과 여부
     * @param userReason 유저별 실패 사유 코드 (검증 통과 시 추가 검증에서 사용)
     * @param batchDigest 배치 다이제스트 (이벤트용)
     * @return storedCount 실제 저장된 레코드 수
     *
     * 저장 로직:
     *   - userOk[i] == false: 검증 단계 실패 → recordId를 failedRecordIds에 넣고 이벤트 1개
     *   - userOk[i] == true: per-record 검증 수행 → 실패 시 failedRecordIds에 포함, 이벤트 1개
     */
    function _storeBoostRecords(
        UserBoostBatch[] calldata batches,
        bytes32[] memory recordHashes,
        bool[] memory userOk,
        uint8[] memory userReason,
        bytes32 batchDigest
    ) internal returns (uint256 storedCount, uint256 successfulUserCount) {
        uint256 len = batches.length;

        for (uint256 i; i < len; ) {
            BoostRecord calldata record = batches[i].record;
            address user = batches[i].userSig.user;
            uint256 nonce_ = batches[i].userSig.userNonce;

            // 검증 단계에서 실패한 유저 → UserMissionResult(false) 1개 발생
            if (!userOk[i]) {
                uint256[] memory failedRecordIds = new uint256[](1);
                failedRecordIds[0] = record.recordId;
                emit UserMissionResult(record.boostingId, false, failedRecordIds, userReason[i]);
                unchecked {
                    ++i;
                }
                continue;
            }

            // per-record 검증 및 저장 (Boosting은 1:1이므로 레코드 1개)
            bool recordFailed;
            uint8 localReason;
            bytes32 recordDigest = recordHashes[i];

            // 중복 레코드 검증
            if (consumed[recordDigest]) {
                recordFailed = true;
                localReason = REASON_DUPLICATE_HASH;
            }
            // 0포인트 부스팅 검증
            else if (record.amt == 0) {
                recordFailed = true;
                localReason = REASON_ZERO_AMT;
            }
            // amt 상한 검증 (집계 오버플로우 방지)
            else if (record.amt > MAX_BOOST_AMT) {
                recordFailed = true;
                localReason = REASON_AMOUNT_TOO_LARGE;
            }
            // boostingWith 타입 검증
            else if (record.boostingWith > MAX_BOOST_TYPE) {
                recordFailed = true;
                localReason = REASON_INVALID_BOOST_TYPE;
            }
            // optionId 검증 (0은 유효한 아티스트 ID가 아니다)
            // allowedArtist[missionId][0]은 언제나 false라 이 검사가 없으면
            // optionId 누락이 ARTIST_NOT_ALLOWED로 잘못 보고된다.
            // MainVoting / SubVoting과 같은 코드를 쓰도록 별도 검사를 둔다.
            else if (record.optionId == 0) {
                recordFailed = true;
                localReason = REASON_INVALID_OPTION_ID;
            }
            // 아티스트 허용 여부 검증
            else if (!allowedArtist[record.missionId][record.optionId]) {
                recordFailed = true;
                localReason = REASON_ARTIST_NOT_ALLOWED;
            }
            // nonce 중복(같은 트랜잭션 내에서 선행 저장으로 인해 사용 처리된 경우 포함)
            else if (usedUserNonces[user][nonce_]) {
                recordFailed = true;
                localReason = REASON_USER_NONCE_INVALID;
            }

            // 검증 실패 시 → UserMissionResult(false) 1개 발생
            if (recordFailed) {
                uint256[] memory failedRecordIds = new uint256[](1);
                failedRecordIds[0] = record.recordId;
                emit UserMissionResult(record.boostingId, false, failedRecordIds, localReason);
                unchecked {
                    ++i;
                }
                continue;
            }

            // 여기까지 왔다면 최종 검증 통과 → nonce 소비 + 저장
            usedUserNonces[user][nonce_] = true;
            emit UserBoostProcessed(batchDigest, user, nonce_);

            consumed[recordDigest] = true;
            boosts[recordDigest] = record;

            // 조회용 인덱스에 추가
            boostHashesByBoostingId[record.missionId][record.boostingId].push(recordDigest);

            // 집계 업데이트
            boostCount[record.missionId][record.boostingId] += 1;
            boostCountByMission[record.missionId] += 1;

            // 타입별 집계 업데이트
            if (record.boostingWith == 0) {
                artistBpAmt[record.missionId][record.optionId] += record.amt;
            } else {
                artistCelbAmt[record.missionId][record.optionId] += record.amt;
            }
            artistTotalAmt[record.missionId][record.optionId] += record.amt;

            // 성공 → UserMissionResult(true) 1개 발생
            uint256[] memory emptyArray = new uint256[](0);
            emit UserMissionResult(record.boostingId, true, emptyArray, 0);

            unchecked {
                ++storedCount;
                ++successfulUserCount;
                ++i;
            }
        }
    }

    // ========================================
    // 메인 진입점 (Main Entry Point)
    // ========================================

    /**
     * @notice 여러 유저의 부스팅 배치를 한 번에 제출
     * @param batches 유저별 부스팅 배치 배열
     * @param batchNonce_ 이 배치의 고유 nonce (리플레이 방지)
     * @param executorSig executorSigner의 서명
     *
     * @dev executorSigner 또는 owner만 호출할 수 있습니다.
     *      제3자 제출은 batchNonce 선점 front-run 방지를 위해 차단됩니다.
     *      유저는 오프체인 서명만 하며, 가스는 executor가 부담합니다.
     *
     *      Soft-fail 방식:
     *      - 한 유저의 검증이 실패해도 다른 유저는 계속 처리
     *      - 모든 유저가 실패한 경우에만 revert
     *
     * 처리 순서:
     *   1. 기본 검증 (크기 제한, executorSigner 설정, 체인 ID)
     *   2. executorSigner 서명 검증 및 nonce 소비
     *   3. 모든 레코드의 해시 계산
     *   4. 각 유저의 서명 검증 (Soft-fail: 실패해도 다른 유저 계속)
     *   5. 검증 통과한 부스팅 레코드 저장 및 집계 업데이트
     *   6. 완료 이벤트 발생
     */
    function submitBoostBatch(
        UserBoostBatch[] calldata batches,
        uint256 batchNonce_,
        bytes calldata executorSig
    ) external {
        // === 0. 제출 권한 검증 (front-run/batchNonce 선점 방지) ===
        // executor 또는 owner만 제출 가능. 유저는 오프체인 서명만 하며 가스는 executor가 부담.
        if (msg.sender != executorSigner && msg.sender != owner())
            revert NotOwnerOrExecutor();

        // === 1. 입력 검증 ===
        uint256 userCount = batches.length;
        if (userCount == 0) revert InvalidRecordIndices();
        if (userCount > MAX_RECORDS_PER_BATCH) revert BatchTooLarge();
        if (executorSigner == address(0)) revert ZeroAddress();
        if (block.chainid != CHAIN_ID) revert BadChain();

        // === 2. Executor 서명 & Nonce 검증 ===
        bytes32 batchDigest = _hashBatch(batchNonce_);
        if (
            !SignatureVerifier.isValidSignature(
                executorSigner,
                batchDigest,
                executorSig
            )
        ) {
            revert InvalidSignature();
        }
        _consumeBatchNonce(executorSigner, batchNonce_);

        // === 3. 각 유저별 Soft-fail 검증 (문자열 검증 포함) ===
        bytes32[] memory recordHashes = new bytes32[](userCount);
        bool[] memory userOk = new bool[](userCount);
        uint8[] memory userReason = new uint8[](userCount);
        uint256 successUserCount;

        for (uint256 i; i < userCount; ) {
            address user = batches[i].userSig.user;
            uint256 nonce_ = batches[i].userSig.userNonce;

            // 문자열 검증 (soft-fail) - userId 길이 초과 시 해당 유저만 실패
            if (!_validateStringsSoft(batches[i].record)) {
                userOk[i] = false;
                userReason[i] = REASON_STRING_TOO_LONG;
                emit UserBoostFailed(batchDigest, user, nonce_, REASON_STRING_TOO_LONG);
                recordHashes[i] = bytes32(0);
                unchecked {
                    ++i;
                }
                continue;
            }

            // 레코드 해시 생성
            recordHashes[i] = _buildRecordDigest(batches[i].record, user);

            (bool ok, uint8 reason) = _verifyUserSignatureSoft(
                batches[i].userSig,
                recordHashes[i],
                batchDigest
            );

            if (ok) {
                userOk[i] = true;
                unchecked {
                    ++successUserCount;
                }
            }
            userReason[i] = reason;

            unchecked {
                ++i;
            }
        }

        if (successUserCount == 0) revert NoSuccessfulUser();

        // === 5. 레코드 저장 ===
        (uint256 stored, uint256 successfulUsers) = _storeBoostRecords(
            batches,
            recordHashes,
            userOk,
            userReason,
            batchDigest
        );
        if (stored == 0) revert NoSuccessfulUser();

        emit BatchProcessed(
            batchDigest,
            executorSigner,
            batchNonce_,
            stored,
            userCount,
            userCount - successfulUsers
        );
    }

    // ========================================
    // 조회 함수 (View Functions)
    // ========================================

    /**
     * @notice EIP-712 도메인 구분자 조회
     * @return EIP-712 도메인 구분자 해시
     *
     * 오프체인에서 서명 생성 시 이 값이 필요합니다.
     */
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @dev 부스팅 조회용 요약 구조체
     * @param recordId 레코드 ID
     * @param timestamp 부스팅 시간
     * @param missionId 미션 ID
     * @param boostingId 부스팅 세션 ID
     * @param userId 유저 식별자
     * @param boostingFor 부스팅 대상 아티스트 이름
     * @param boostingWith 부스팅 타입 이름 ("BP" 또는 "CELB")
     * @param amt 부스팅 수량
     */
    struct BoostRecordSummary {
        uint256 recordId;
        uint256 timestamp;
        uint256 missionId;
        uint256 boostingId;
        string userId;
        string boostingFor;
        string boostingWith;
        uint256 amt;
    }

    /**
     * @notice 특정 미션/부스팅 세션의 모든 부스팅 요약 조회
     * @param missionId 미션 ID
     * @param boostingId 부스팅 세션 ID
     * @return 부스팅 요약 배열
     *
     * @dev 주의: boostingId당 레코드 수 제한이 없으므로 대량 데이터 시
     *      가스 비용이 높아질 수 있습니다. 필요 시 오프체인 조회를 권장합니다.
     */
    function getBoostSummariesByBoostingId(
        uint256 missionId,
        uint256 boostingId
    ) external view returns (BoostRecordSummary[] memory) {
        bytes32[] storage allHashes = boostHashesByBoostingId[missionId][
            boostingId
        ];
        uint256 totalCount = allHashes.length;
        BoostRecordSummary[] memory result = new BoostRecordSummary[](
            totalCount
        );

        for (uint256 i; i < totalCount; ) {
            BoostRecord storage record = boosts[allHashes[i]];

            string memory artistNameStr = artistName[record.missionId][
                record.optionId
            ];
            string memory boostingTypeStr = boostingTypeName[
                record.boostingWith
            ];

            result[i] = BoostRecordSummary({
                recordId: record.recordId,
                timestamp: record.timestamp,
                missionId: record.missionId,
                boostingId: record.boostingId,
                userId: record.userId,
                boostingFor: artistNameStr,
                boostingWith: boostingTypeStr,
                amt: record.amt
            });
            unchecked {
                ++i;
            }
        }

        return result;
    }

    /// @notice 아티스트별 부스팅 집계 조회
    /// @return bpAmt BP 타입 부스팅 총량
    /// @return celbAmt CELB 타입 부스팅 총량
    /// @return total 전체 부스팅 총량
    function getBoostAggregates(
        uint256 missionId,
        uint256 optionId
    ) external view returns (uint256 bpAmt, uint256 celbAmt, uint256 total) {
        return (
            artistBpAmt[missionId][optionId],
            artistCelbAmt[missionId][optionId],
            artistTotalAmt[missionId][optionId]
        );
    }
}

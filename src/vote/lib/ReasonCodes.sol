// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ReasonCodes
 * @notice UserMissionResult / UserBatchFailed / UserBoostFailed 이벤트에 실리는 실패 사유 코드
 * @dev MainVoting / SubVoting / Boosting이 공유하는 **단일 출처**다.
 *      백엔드·프론트는 하나의 디코더를 세 컨트랙트에 함께 쓸 수 있다.
 *
 *      각 컨트랙트는 이 값을 도메인 이름으로 alias 해서 쓴다.
 *      예: Boosting의 REASON_ARTIST_NOT_ALLOWED, SubVoting의 REASON_QUESTION_NOT_ALLOWED가
 *          모두 TARGET_NOT_ALLOWED(5)를 가리킨다.
 *
 *      internal constant만 있으므로 별도 배포 없이 인라인된다 (가스·배포 비용 0).
 *
 *      새 코드를 추가할 때는 반드시 여기에만 추가한다.
 *      컨트랙트 파일에 직접 숫자를 적으면 세 컨트랙트가 어긋난다.
 *      실제로 커밋 30b217d에서 AMOUNT_TOO_LARGE를 세 파일에 따로 넣다가
 *      MainVoting/SubVoting은 11, Boosting은 9가 되어 어긋난 적이 있다.
 *
 *      값을 바꾸면 이미 배포된 컨트랙트가 남긴 과거 이벤트 로그의 의미가 달라진다.
 *      변경 시 test/ReasonCodes.t.sol의 고정 테스트도 함께 갱신해야 한다.
 */
library ReasonCodes {
    /// @notice 성공 (실패 사유 없음)
    uint8 internal constant NONE = 0;

    /// @notice 유저 배치 크기 오류 (레코드 0개 또는 상한 초과) — Boosting은 1:1 구조라 미사용
    uint8 internal constant USER_BATCH_TOO_LARGE = 1;

    /// @notice 유저 서명 검증 실패 (EIP-712 서명 불일치)
    uint8 internal constant INVALID_USER_SIGNATURE = 2;

    /// @notice 유저 nonce 중복 사용
    uint8 internal constant USER_NONCE_INVALID = 3;

    /// @notice 잘못된 타입 — MainVoting은 voteType, Boosting은 boostingWith. SubVoting은 미사용
    uint8 internal constant INVALID_TYPE = 4;

    /// @notice 투표·부스팅 대상 미허용 — Main/Boosting은 아티스트, SubVoting은 질문
    uint8 internal constant TARGET_NOT_ALLOWED = 5;

    /// @notice 문자열 길이 초과 (userId)
    uint8 internal constant STRING_TOO_LONG = 6;

    /// @notice 중복 레코드 (이미 저장됐거나 배치 내 중복)
    uint8 internal constant DUPLICATE_RECORD = 7;

    /// @notice 수량이 0
    uint8 internal constant ZERO_AMOUNT = 8;

    /// @notice 유저 배치 내 votingId 불일치 — Boosting은 1:1 구조라 미사용
    uint8 internal constant VOTING_ID_MISMATCH = 9;

    /// @notice optionId가 0 — 세 컨트랙트 모두 사용한다.
    ///         Boosting도 별도 검사를 둔다. allowedArtist[missionId][0]은
    ///         언제나 false라 이 검사가 없으면 optionId 누락이
    ///         TARGET_NOT_ALLOWED(5)로 잘못 보고되기 때문이다.
    uint8 internal constant INVALID_OPTION_ID = 10;

    /// @notice 수량이 상한 초과 (집계 오버플로우 방지)
    uint8 internal constant AMOUNT_TOO_LARGE = 11;

    /// @notice 선택지 미허용 — 질문-선택지 2단 구조를 가진 SubVoting 전용
    uint8 internal constant OPTION_NOT_ALLOWED = 12;
}

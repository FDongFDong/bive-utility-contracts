// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ReasonCodes} from "../src/vote/lib/ReasonCodes.sol";

/**
 * @title ReasonCodesTest
 * @notice ReasonCodes 값을 리터럴로 못박는 고정(pin) 테스트
 * @dev 이 파일의 숫자는 ReasonCodes.sol과 의도적으로 중복된다.
 *      라이브러리를 참조하지 않고 리터럴을 쓰는 것이 핵심이다.
 *      라이브러리에서 값을 가져오면 어떤 값이든 통과해 감시자 역할을 못 한다.
 *
 *      값이 바뀌면 여기서 실패한다. 실패했다면 다음을 확인한다:
 *        1. 이미 배포된 컨트랙트가 남긴 과거 이벤트 로그의 의미가 달라진다
 *        2. 백엔드(contractResultCode 컬럼)와 프론트 디코더를 함께 고쳐야 한다
 *        3. Notion의 MainVoting / SubVoting / Boosting 문서 대조표도 갱신해야 한다
 *      모두 확인했다면 이 테스트의 기대값을 갱신한다.
 */
contract ReasonCodesTest is Test {
    /// @notice 각 코드가 약속된 번호를 유지하는지 확인
    function test_ReasonCodeValuesArePinned() public pure {
        assertEq(ReasonCodes.NONE, 0, "NONE");
        assertEq(ReasonCodes.USER_BATCH_TOO_LARGE, 1, "USER_BATCH_TOO_LARGE");
        assertEq(ReasonCodes.INVALID_USER_SIGNATURE, 2, "INVALID_USER_SIGNATURE");
        assertEq(ReasonCodes.USER_NONCE_INVALID, 3, "USER_NONCE_INVALID");
        assertEq(ReasonCodes.INVALID_TYPE, 4, "INVALID_TYPE");
        assertEq(ReasonCodes.TARGET_NOT_ALLOWED, 5, "TARGET_NOT_ALLOWED");
        assertEq(ReasonCodes.STRING_TOO_LONG, 6, "STRING_TOO_LONG");
        assertEq(ReasonCodes.DUPLICATE_RECORD, 7, "DUPLICATE_RECORD");
        assertEq(ReasonCodes.ZERO_AMOUNT, 8, "ZERO_AMOUNT");
        assertEq(ReasonCodes.VOTING_ID_MISMATCH, 9, "VOTING_ID_MISMATCH");
        assertEq(ReasonCodes.INVALID_OPTION_ID, 10, "INVALID_OPTION_ID");
        assertEq(ReasonCodes.AMOUNT_TOO_LARGE, 11, "AMOUNT_TOO_LARGE");
        assertEq(ReasonCodes.OPTION_NOT_ALLOWED, 12, "OPTION_NOT_ALLOWED");
    }

    /// @notice 서로 다른 사유가 같은 번호를 쓰지 않는지 확인
    /// @dev 새 코드를 추가하면서 이미 쓰인 번호를 재사용하는 실수를 잡는다.
    ///      값 하나를 바꿔 다른 코드와 겹치게 만들면 위 고정 테스트와 함께 여기서도 실패한다.
    function test_ReasonCodesAreUnique() public pure {
        uint8[13] memory codes = [
            ReasonCodes.NONE,
            ReasonCodes.USER_BATCH_TOO_LARGE,
            ReasonCodes.INVALID_USER_SIGNATURE,
            ReasonCodes.USER_NONCE_INVALID,
            ReasonCodes.INVALID_TYPE,
            ReasonCodes.TARGET_NOT_ALLOWED,
            ReasonCodes.STRING_TOO_LONG,
            ReasonCodes.DUPLICATE_RECORD,
            ReasonCodes.ZERO_AMOUNT,
            ReasonCodes.VOTING_ID_MISMATCH,
            ReasonCodes.INVALID_OPTION_ID,
            ReasonCodes.AMOUNT_TOO_LARGE,
            ReasonCodes.OPTION_NOT_ALLOWED
        ];

        for (uint256 i; i < codes.length; ++i) {
            for (uint256 j = i + 1; j < codes.length; ++j) {
                assertTrue(codes[i] != codes[j], "duplicate reasonCode");
            }
        }
    }
}

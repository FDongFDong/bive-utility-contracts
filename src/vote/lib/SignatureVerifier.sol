// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC1271} from "../../common/IERC1271.sol";

/**
 * @title SignatureVerifier
 * @notice EOA와 스마트 컨트랙트 지갑 서명을 모두 지원하는 공유 서명 검증 라이브러리
 * @dev signer에 코드가 없으면 ECDSA recover, 있으면 ERC-1271 staticcall로 검증한다.
 *      MainVoting / SubVoting / Boosting이 공통으로 사용한다.
 */
library SignatureVerifier {
    bytes4 private constant ERC1271_MAGICVALUE = 0x1626ba7e;

    /// @notice digest에 대한 sig가 signer의 유효한 서명인지 검증
    /// @param signer 서명자 주소 (EOA 또는 ERC-1271 지갑)
    /// @param digest EIP-712 서명 다이제스트
    /// @param sig 검증할 서명 바이트
    /// @return 서명 유효 여부
    function isValidSignature(
        address signer,
        bytes32 digest,
        bytes calldata sig
    ) internal view returns (bool) {
        if (signer.code.length == 0) {
            (
                address recovered,
                ECDSA.RecoverError err,
                bytes32 errArg
            ) = ECDSA.tryRecoverCalldata(digest, sig);
            errArg; // suppress unused warning
            return err == ECDSA.RecoverError.NoError && recovered == signer;
        }

        (bool ok, bytes memory ret) = signer.staticcall(
            abi.encodeWithSelector(
                IERC1271.isValidSignature.selector,
                digest,
                sig
            )
        );
        // ABI-encoded bytes4 is padded to 32 bytes.
        return ok && ret.length >= 32 && bytes4(ret) == ERC1271_MAGICVALUE;
    }
}

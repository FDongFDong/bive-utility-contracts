#!/usr/bin/env node
/**
 * submit-stress-viem.mjs
 *
 * 스트레스 테스트 서명 데이터를 컨트랙트에 제출하는 스크립트
 *
 * 주요 기능:
 *   - stress-viem.mjs가 생성한 JSON 파일 로드
 *   - submitMultiUserBatch 함수 호출
 *   - 가스 추정 및 nonce 지정 지원
 *
 * 사용법:
 *   PRIVATE_KEY=0x... node scripts/submit-stress-viem.mjs [options]
 *
 * 옵션:
 *   --file <path>         서명 데이터 JSON 파일 경로
 *   --votingAddress       컨트랙트 주소
 *   --rpcUrl              RPC URL
 *   --nonce N             트랜잭션 nonce (병렬 제출용)
 *   --gas N               가스 리밋 (미지정 시 자동 추정)
 *   --gasBumpPercent N    가스 가격 버프 % (기본: 0)
 *
 * 출력:
 *   트랜잭션 해시 및 opbnbscan 링크
 */

import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  createWalletClient,
  createPublicClient,
  decodeAbiParameters,
  defineChain,
  getAddress,
  http,
  encodeFunctionData,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

// =============================================================================
// 상수 정의
// =============================================================================

const DEFAULT_RPC_URL = "https://opbnb-testnet-rpc.bnbchain.org";
const DEFAULT_STRESS_FILE = "stress-artifacts/stress-output.json";
const DEFAULT_VOTING_ADDRESS = "0x10Fb9C7BFec7d2059b65c9e70B4F58E2E6fd0eFE";
const DEFAULT_CALLDATA_OUT = "stress-artifacts/last-calldata.txt";

// =============================================================================
// ABI 인코딩용 구조체 정의 (stress-viem.mjs와 동일)
// =============================================================================

// VoteRecord 구조체
const VOTE_RECORD_TUPLE = {
  type: "tuple",
  components: [
    { name: "timestamp", type: "uint256" },
    { name: "missionId", type: "uint256" },
    { name: "votingId", type: "uint256" },
    { name: "optionId", type: "uint256" },
    { name: "voteType", type: "uint8" },
    { name: "userId", type: "string" },
    { name: "votingAmt", type: "uint256" },
  ],
};

// UserBatchSig 구조체
const USER_BATCH_SIG_TUPLE = {
  type: "tuple",
  components: [
    { name: "user", type: "address" },
    { name: "userNonce", type: "uint256" },
    { name: "signature", type: "bytes" },
  ],
};

// UserVoteBatch 구조체 배열
const USER_VOTE_BATCH_TUPLE = {
  type: "tuple[]",
  components: [
    {
      name: "records",
      type: "tuple[]",
      components: VOTE_RECORD_TUPLE.components,
    },
    {
      name: "userBatchSig",
      type: "tuple",
      components: USER_BATCH_SIG_TUPLE.components,
    },
  ],
};

// submitMultiUserBatch 함수 ABI
const MAIN_VOTING_ABI = [
  {
    type: "function",
    stateMutability: "nonpayable",
    name: "submitMultiUserBatch",
    inputs: [
      {
        name: "batches",
        type: "tuple[]",
        components: [
          {
            name: "records",
            type: "tuple[]",
            components: VOTE_RECORD_TUPLE.components,
          },
          {
            name: "userBatchSig",
            type: "tuple",
            components: USER_BATCH_SIG_TUPLE.components,
          },
        ],
      },
      { name: "batchNonce", type: "uint256" },
      { name: "executorSig", type: "bytes" },
    ],
    outputs: [],
  },
];

// =============================================================================
// 유틸리티 함수
// =============================================================================

/**
 * CLI 인자 파싱
 */
function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const part = argv[i];
    if (!part.startsWith("--")) continue;
    const key = part.slice(2);
    const value =
      argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[++i] : "true";
    args[key] = value;
  }
  return args;
}

/**
 * Private Key 정규화 (0x 접두사 및 길이 검증)
 */
function normalizePrivateKey(value) {
  if (!value) return null;
  let hex = value.trim().toLowerCase();
  if (!hex.startsWith("0x")) hex = `0x${hex}`;
  if (hex.length !== 66) {
    throw new Error("PRIVATE_KEY must be 32 bytes (64 hex chars)");
  }
  return hex;
}

/**
 * 값을 BigInt로 변환
 */
function toBigInt(value, label) {
  if (!value) return undefined;
  try {
    return BigInt(value);
  } catch (err) {
    throw new Error(`${label} 값을 BigInt로 변환할 수 없습니다: ${value}`);
  }
}

/**
 * 스트레스 테스트 JSON 파일 로드
 */
function loadStressFile(filePath) {
  const resolved = resolve(process.cwd(), filePath);
  const raw = readFileSync(resolved, "utf8");
  const json = JSON.parse(raw);
  return { json, resolved };
}

/**
 * ABI 인코딩된 배치 데이터를 디코딩
 */
function decodeUserVoteBatches(encoded) {
  const [batches] = decodeAbiParameters([USER_VOTE_BATCH_TUPLE], encoded);
  return batches.map((batch) => ({
    records: batch.records.map((r) => ({
      timestamp: BigInt(r.timestamp),
      missionId: BigInt(r.missionId),
      votingId: BigInt(r.votingId),
      optionId: BigInt(r.optionId),
      voteType: Number(r.voteType),
      userId: r.userId,
      votingAmt: BigInt(r.votingAmt),
    })),
    userBatchSig: {
      user: getAddress(batch.userBatchSig.user),
      userNonce: BigInt(batch.userBatchSig.userNonce),
      signature: batch.userBatchSig.signature,
    },
  }));
}

// =============================================================================
// 메인 함수
// =============================================================================

async function main() {
  // -------------------------------------------------------------------------
  // 1. 설정값 파싱
  // -------------------------------------------------------------------------
  const cli = parseArgs(process.argv.slice(2));
  const privateKey = normalizePrivateKey(
    process.env.PRIVATE_KEY || cli.privateKey
  );
  if (!privateKey) {
    throw new Error(
      "환경변수 PRIVATE_KEY (또는 --privateKey) 를 설정해주세요."
    );
  }

  const rpcUrl = cli.rpcUrl || process.env.RPC_URL || DEFAULT_RPC_URL;
  const stressFile = cli.file || process.env.STRESS_FILE || DEFAULT_STRESS_FILE;

  // -------------------------------------------------------------------------
  // 2. 서명 데이터 로드
  // -------------------------------------------------------------------------
  const { json, resolved } = loadStressFile(stressFile);
  const votingAddress = getAddress(
    cli.votingAddress ||
      process.env.VOTING_ADDRESS ||
      json.metadata?.votingAddress ||
      DEFAULT_VOTING_ADDRESS
  );

  const batches = decodeUserVoteBatches(json.batches);
  const batchNonce = BigInt(json.batchNonce);
  const executorSig = json.executorSig;

  const chainId = BigInt(
    cli.chainId || process.env.CHAIN_ID || json.metadata?.chainId || 5611
  );
  const gasLimitInput = cli.gas || process.env.GAS_LIMIT;
  const nonceInput = cli.nonce || process.env.NONCE;
  const gasBumpPercentInput =
    cli.gasBumpPercent || process.env.GAS_BUMP_PERCENT;

  // -------------------------------------------------------------------------
  // 3. 클라이언트 설정
  // -------------------------------------------------------------------------
  const chain = defineChain({
    id: Number(chainId),
    name: "opBNB Testnet",
    network: "opbnb-testnet",
    nativeCurrency: { name: "BNB", symbol: "BNB", decimals: 18 },
    rpcUrls: { default: { http: [rpcUrl] }, public: { http: [rpcUrl] } },
  });

  const account = privateKeyToAccount(privateKey);
  const client = createWalletClient({
    account,
    chain,
    transport: http(rpcUrl),
  });
  const publicClient = createPublicClient({ chain, transport: http(rpcUrl) });

  // 총 레코드 수 계산
  const totalRecords = batches.reduce((sum, b) => sum + b.records.length, 0);

  console.log("== 스트레스 서명 제출 시작 ==");
  console.log(`파일: ${resolved}`);
  console.log(`목표 컨트랙트: ${votingAddress}`);
  console.log(`배치 논스: ${batchNonce}`);
  console.log(`총 레코드: ${totalRecords}, 유저 배치: ${batches.length}`);

  // -------------------------------------------------------------------------
  // 4. 가스 추정
  // -------------------------------------------------------------------------
  let gasLimit;
  if (gasLimitInput) {
    gasLimit = toBigInt(gasLimitInput, "gas");
  } else {
    const encodedCalldata = encodeFunctionData({
      abi: MAIN_VOTING_ABI,
      functionName: "submitMultiUserBatch",
      args: [batches, batchNonce, executorSig],
    });

    const calldataByteLen = (encodedCalldata.length - 2) / 2;
    console.log("Calldata length:", calldataByteLen, "bytes");
    console.log(`Calldata hex saved to: ${DEFAULT_CALLDATA_OUT}`);
    writeFileSync(DEFAULT_CALLDATA_OUT, encodedCalldata + "\n", "utf8");
    // console.log("Calldata hex:", encodedCalldata);
    // publicClient.estimateContractGas()
    //    - 컨트랙트 호출을 시뮬레이션하여 필요한 gas를 계산
    //    - revert 없이 실행될 때 필요한 가스를 반환
    const estimate = await publicClient.estimateContractGas({
      account,
      address: votingAddress,
      abi: MAIN_VOTING_ABI,
      functionName: "submitMultiUserBatch",
      args: [batches, batchNonce, executorSig],
    });
    // 25% 안전 마진 추가
    gasLimit = (estimate * 125n) / 100n;
    console.log(
      `Estimated gas: ${estimate.toString()} -> applying 25% buffer = ${gasLimit.toString()}`
    );
  }

  // -------------------------------------------------------------------------
  // 5. 가스 가격 조회 및 버프 적용
  // -------------------------------------------------------------------------
  let maxFeePerGas;
  let maxPriorityFeePerGas;
  try {
    // ============================================================
    // EIP-1559 기반 가스 가격 추정 (기본 방식)
    // ------------------------------------------------------------
    // estimateFeesPerGas() 는 다음 값을 반환함:
    //   - maxFeePerGas          : 사용자가 지불 가능한 최대 가스비 ceiling
    //   - maxPriorityFeePerGas  : 채굴자(validator) 팁
    //
    // opBNB도 대부분 EIP-1559 스타일을 지원하므로 우선 이 방식으로 시도함.
    // ============================================================
    const feeData = await publicClient.estimateFeesPerGas();
    maxFeePerGas = feeData.maxFeePerGas;
    maxPriorityFeePerGas = feeData.maxPriorityFeePerGas;
  } catch (err) {
    // EIP-1559 미지원 RPC의 경우 fallback 처리
    // ------------------------------------------------------------
    // getGasPrice() → 단일 gasPrice 방식 반환
    // 이 방식에서는:
    //   maxFeePerGas = gasPrice
    //   maxPriorityFeePerGas = gasPrice
    //
    // 즉, 일반적인 gasPrice 기반 트랜잭션처럼 처리됨.
    // ============================================================
    const gasPrice = await publicClient.getGasPrice();
    maxFeePerGas = gasPrice;
    maxPriorityFeePerGas = gasPrice;
  }

  // 가스 가격 버프(percent) 적용
  // ------------------------------------------------------------
  // --gasBumpPercent 옵션이 지정되면, 예를 들어 20이라면
  //  → maxFeePerGas, maxPriorityFeePerGas 둘 다 +20% 증가
  //
  // 목적: 네트워크 혼잡 시 트랜잭션을 빨리 포함시키기 위한 "가스 가격 인상 기법"
  // ============================================================
  const gasBumpPercent = gasBumpPercentInput ? Number(gasBumpPercentInput) : 0;
  if (gasBumpPercent > 0) {
    const bump = BigInt(100 + gasBumpPercent);
    maxFeePerGas = (maxFeePerGas * bump) / 100n;
    maxPriorityFeePerGas = (maxPriorityFeePerGas * bump) / 100n;
  }

  // -------------------------------------------------------------------------
  // 6. 트랜잭션 전송
  // -------------------------------------------------------------------------
  const nonce = nonceInput ? toBigInt(nonceInput, "nonce") : undefined;

  const writeParams = {
    address: votingAddress,
    abi: MAIN_VOTING_ABI,
    functionName: "submitMultiUserBatch",
    args: [batches, batchNonce, executorSig],
    gas: gasLimit,
    maxFeePerGas,
    maxPriorityFeePerGas,
  };

  // nonce가 지정된 경우 추가 (병렬 제출용)
  if (nonce !== undefined) {
    writeParams.nonce = nonce;
  }

  const hash = await client.writeContract(writeParams);

  // -------------------------------------------------------------------------
  // 7. 결과 출력
  // -------------------------------------------------------------------------
  console.log("[OK] 제출 완료");
  console.log(`txHash: ${hash}`);
  console.log(`opbnbscan: https://testnet.opbnbscan.com/tx/${hash}`);

  // RLP 사이즈 조회 (optional)
  try {
    const rawTx = await client.transport.request({
      method: "eth_getRawTransactionByHash",
      params: [hash],
    });
    if (rawTx) {
      // console.log("rawTransaction: ", rawTx);
      const byteLen = (rawTx.length - 2) / 2;
      const kb = byteLen / 1024;
      console.log(`RLP size: ${byteLen} bytes (${kb.toFixed(2)} KB)`);
    }
  } catch (err) {
    console.warn("[WARN] raw tx size 조회 실패:", err.message ?? err);
  }
}

main().catch((err) => {
  console.error("[ERROR] 제출 중 오류 발생:", err.message ?? err);
  process.exitCode = 1;
});

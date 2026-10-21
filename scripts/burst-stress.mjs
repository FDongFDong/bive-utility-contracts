#!/usr/bin/env node
/**
 * burst-stress.mjs
 *
 * 동시 다발적 스트레스 테스트 오케스트레이터
 *
 * 주요 기능:
 *   - 여러 배치를 생성하고 병렬로 제출
 *   - nonce 사전 할당으로 동시 트랜잭션 지원
 *   - stress-viem.mjs, submit-stress-viem.mjs 호출
 *
 * 사용법:
 *   VOTING_ADDRESS=0x... PRIVATE_KEY=0x... node scripts/burst-stress.mjs [options]
 *
 * 옵션:
 *   --count N           동시 제출할 배치 수 (기본: 2)
 *   --totalVotes N      배치당 총 투표 수 (기본: 100)
 *   --userCount N       유저 수 (기본: 20)
 *   --perUserVotes N    유저당 투표 수 (totalVotes/userCount로 계산됨)
 *   --missionId N       미션 ID (기본: 1)
 *   --gasBumpPercent N  가스 버프 % (기본: 10)
 *   --dryRun            실제 제출 없이 데이터 생성만
 */

import { spawn } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createPublicClient, defineChain, http, getAddress } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

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
    if (!part.startsWith('--')) continue;
    const key = part.slice(2);
    const value = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : 'true';
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
  if (!hex.startsWith('0x')) hex = `0x${hex}`;
  if (hex.length !== 66) {
    throw new Error('PRIVATE_KEY must be 32 bytes (64 hex chars)');
  }
  return hex;
}

/**
 * 자식 프로세스 실행 및 출력 캡처
 */
function runCommand(command, commandArgs, envOverrides = {}, label) {
  return new Promise((resolvePromise, reject) => {
    console.log(`\n[RUN] [${label}] ${command} ${commandArgs.slice(0, 3).join(' ')}...`);

    const child = spawn(command, commandArgs, {
      stdio: 'pipe',
      env: { ...process.env, ...envOverrides },
      cwd: resolve(__dirname, '..'),
    });

    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (data) => {
      stdout += data.toString();
      process.stdout.write(data);
    });

    child.stderr.on('data', (data) => {
      stderr += data.toString();
      process.stderr.write(data);
    });

    child.on('exit', (code) => {
      if (code === 0) {
        resolvePromise({ stdout, stderr });
      } else {
        reject(new Error(`${label ?? command} exited with code ${code}\n${stderr}`));
      }
    });

    child.on('error', (err) => {
      reject(new Error(`${label ?? command} failed to start: ${err.message}`));
    });
  });
}

/**
 * 구분선 출력
 */
function printBanner(title) {
  console.log('\n' + '='.repeat(60));
  console.log(`  ${title}`);
  console.log('='.repeat(60));
}

/**
 * 설정값 출력
 */
function printConfig(config) {
  console.log('\n[CONFIG]');
  console.log(`   count:          ${config.count}`);
  console.log(`   totalVotes:     ${config.totalVotes}`);
  console.log(`   userCount:      ${config.userCount}`);
  console.log(`   votesPerUser:   ${config.votesPerUser}`);
  console.log(`   missionId:      ${config.missionId}`);
  console.log(`   gasBumpPercent: ${config.gasBumpPercent}%`);
  console.log(`   votingAddress:  ${config.votingAddress}`);
  console.log(`   rpcUrl:         ${config.rpcUrl}`);
}

// =============================================================================
// 메인 함수
// =============================================================================

async function main() {
  printBanner('MainVoting Burst Stress Test');

  const cli = parseArgs(process.argv.slice(2));

  // -------------------------------------------------------------------------
  // 1. 설정값 파싱 및 검증
  // -------------------------------------------------------------------------
  const privateKey = normalizePrivateKey(process.env.PRIVATE_KEY || cli.privateKey);
  if (!privateKey) {
    console.error('[ERROR] PRIVATE_KEY 환경변수가 필요합니다.');
    console.error('   예시: PRIVATE_KEY=0x... node scripts/burst-stress.mjs');
    process.exit(1);
  }

  const rpcUrl = cli.rpcUrl || process.env.RPC_URL || 'https://opbnb-testnet-rpc.bnbchain.org';
  const votingAddress = cli.votingAddress || cli.VOTING_ADDRESS || process.env.VOTING_ADDRESS;

  if (!votingAddress) {
    console.error('[ERROR] VOTING_ADDRESS 환경변수가 필요합니다.');
    console.error('   예시: VOTING_ADDRESS=0x... node scripts/burst-stress.mjs');
    process.exit(1);
  }

  const normalizedVotingAddress = getAddress(votingAddress);

  // 설정값 파싱
  const count = Number(cli.count || process.env.STRESS_BURST_COUNT || 2);
  const userCount = Number(cli.userCount || process.env.USER_COUNT || 20);
  const perUserVotes = cli.perUserVotes || cli.recordsPerUser || process.env.PER_USER_VOTES;

  let totalVotes;
  let votesPerUser;

  if (perUserVotes) {
    votesPerUser = Number(perUserVotes);
    totalVotes = votesPerUser * userCount;
  } else {
    totalVotes = Number(cli.totalVotes || process.env.TOTAL_VOTES || 100);
    if (totalVotes % userCount !== 0) {
      console.error(`[ERROR] totalVotes(${totalVotes})가 userCount(${userCount})로 나누어 떨어져야 합니다.`);
      process.exit(1);
    }
    votesPerUser = totalVotes / userCount;
  }

  // 유효성 검증
  if (votesPerUser > 20) {
    console.error(`[ERROR] 유저당 투표 수(${votesPerUser})가 최대치(20)를 초과합니다.`);
    process.exit(1);
  }
  if (votesPerUser % 2 !== 0) {
    console.error(`[ERROR] 유저당 투표 수(${votesPerUser})는 짝수여야 합니다 (Remember/Forget 균등 분배).`);
    process.exit(1);
  }
  if (totalVotes > 2000) {
    console.error(`[ERROR] 배치당 총 투표 수(${totalVotes})가 최대치(2000)를 초과합니다.`);
    process.exit(1);
  }

  const missionId = Number(cli.missionId || process.env.MISSION_ID || 1);
  const gasBumpPercent = Number(cli.gasBumpPercent || process.env.GAS_BUMP_PERCENT || 10);
  const chainId = Number(cli.chainId || process.env.CHAIN_ID || 5611);
  const dryRun = cli.dryRun === 'true' || cli.dryRun === true;

  const config = {
    count,
    totalVotes,
    userCount,
    votesPerUser,
    missionId,
    gasBumpPercent,
    votingAddress: normalizedVotingAddress,
    rpcUrl,
    chainId,
    dryRun,
  };

  printConfig(config);

  // -------------------------------------------------------------------------
  // 2. Nonce 조회
  // -------------------------------------------------------------------------
  const chain = defineChain({
    id: chainId,
    name: 'opBNB Testnet',
    network: 'opbnb-testnet',
    nativeCurrency: { name: 'BNB', symbol: 'BNB', decimals: 18 },
    rpcUrls: { default: { http: [rpcUrl] }, public: { http: [rpcUrl] } },
  });

  const account = privateKeyToAccount(privateKey);
  const publicClient = createPublicClient({ chain, transport: http(rpcUrl) });

  console.log(`\n[INFO] Executor: ${account.address}`);

  let baseNonce;
  try {
    baseNonce = BigInt(
      await publicClient.getTransactionCount({ address: account.address, blockTag: 'pending' })
    );
    console.log(`[INFO] Current pending nonce: ${baseNonce}`);
  } catch (err) {
    console.error(`[ERROR] nonce 조회 실패: ${err.message}`);
    process.exit(1);
  }

  // -------------------------------------------------------------------------
  // Phase 1: 서명 데이터 생성
  // -------------------------------------------------------------------------
  printBanner(`Phase 1: Generate Signatures (${count} batches, ${totalVotes} votes each)`);

  const generatedFiles = [];
  const stressViemPath = resolve(__dirname, 'stress-viem.mjs');

  for (let i = 0; i < count; i++) {
    const timestamp = Date.now();
    const fileName = `burst-${totalVotes}-${missionId}-${timestamp}-${i}.json`;
    const filePath = resolve(__dirname, '..', 'stress-artifacts', fileName);

    // 각 배치에 오프셋 적용:
    // - batchNonceOffset: 순차적 batchNonce 사용 (0, 1, 2, ...)
    // - userIndexOffset: 각 배치가 다른 유저 사용 (0, userCount, userCount*2, ...)
    const batchNonceOffset = i;
    const userIndexOffset = i * userCount;

    try {
      await runCommand(
        'node',
        [
          stressViemPath,
          '--totalVotes', String(totalVotes),
          '--userCount', String(userCount),
          '--missionId', String(missionId),
          '--file', fileName,
          '--votingAddress', normalizedVotingAddress,
          '--rpcUrl', rpcUrl,
          '--chainId', String(chainId),
          '--batchNonceOffset', String(batchNonceOffset),
          '--userIndexOffset', String(userIndexOffset),
        ],
        {
          PRIVATE_KEY: privateKey,
          VOTING_ADDRESS: normalizedVotingAddress,
          RPC_URL: rpcUrl,
        },
        `Generate #${i + 1}/${count}`
      );
      generatedFiles.push(filePath);
      console.log(`   [OK] Generated: ${fileName}`);
    } catch (err) {
      console.error(`   [ERROR] Generate failed #${i + 1}: ${err.message}`);
      process.exit(1);
    }
  }

  console.log(`\n[OK] ${generatedFiles.length} signature files generated`);

  if (dryRun) {
    printBanner('Dry Run Complete (submission skipped)');
    console.log('\nGenerated files:');
    generatedFiles.forEach((f, i) => console.log(`   ${i + 1}. ${f}`));
    return;
  }

  // -------------------------------------------------------------------------
  // Phase 2: 동시 제출
  // -------------------------------------------------------------------------
  printBanner(`Phase 2: Parallel Submit (${count} transactions)`);

  console.log('\n[INFO] Starting parallel submission...');
  console.log(`   Base nonce: ${baseNonce}`);
  console.log(`   Nonce range: ${baseNonce} ~ ${baseNonce + BigInt(count - 1)}`);

  const submitViemPath = resolve(__dirname, 'submit-stress-viem.mjs');

  const submitPromises = generatedFiles.map((filePath, idx) => {
    const assignedNonce = baseNonce + BigInt(idx);
    console.log(`   [SUBMIT] #${idx + 1}: nonce=${assignedNonce}`);

    return runCommand(
      'node',
      [
        submitViemPath,
        '--file', filePath,
        '--votingAddress', normalizedVotingAddress,
        '--rpcUrl', rpcUrl,
        '--nonce', assignedNonce.toString(),
        '--gasBumpPercent', String(gasBumpPercent),
      ],
      {
        VOTING_ADDRESS: normalizedVotingAddress,
        RPC_URL: rpcUrl,
        PRIVATE_KEY: privateKey,
        NONCE: assignedNonce.toString(),
        GAS_BUMP_PERCENT: String(gasBumpPercent),
      },
      `Submit #${idx + 1}`
    );
  });

  const results = await Promise.allSettled(submitPromises);

  // -------------------------------------------------------------------------
  // 결과 요약
  // -------------------------------------------------------------------------
  printBanner('Results Summary');

  let successCount = 0;
  let failCount = 0;

  results.forEach((res, idx) => {
    const nonce = baseNonce + BigInt(idx);
    if (res.status === 'fulfilled') {
      console.log(`   [OK] Submit #${idx + 1} (nonce=${nonce}): Success`);
      successCount++;
    } else {
      console.log(`   [FAIL] Submit #${idx + 1} (nonce=${nonce}): Failed`);
      console.log(`      -> ${res.reason?.message?.split('\n')[0] || res.reason}`);
      failCount++;
    }
  });

  console.log('\n' + '-'.repeat(40));
  console.log(`   Success: ${successCount}/${count}`);
  console.log(`   Failed:  ${failCount}/${count}`);
  console.log(`   Total vote records: ${successCount * totalVotes}`);
  console.log('-'.repeat(40));

  if (failCount > 0) {
    console.log('\n[WARN] Some transactions failed.');
    process.exitCode = 1;
  } else {
    console.log('\n[OK] All stress tests completed!');
  }

  console.log('\nGenerated files:');
  generatedFiles.forEach((f, i) => console.log(`   ${i + 1}. ${f}`));
}

main().catch((err) => {
  console.error('\n[ERROR] Script error:', err.message ?? err);
  process.exit(1);
});

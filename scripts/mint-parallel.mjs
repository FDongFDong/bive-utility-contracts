#!/usr/bin/env node

/**
 * 병렬 NFT 민팅 스크립트 (viem) - 완전 자동화
 *
 * 사용법:
 *   npm run mint:parallel -- --batch-size 200 --repeat 5
 *
 * 모든 것이 자동으로 처리됩니다:
 *   1. NFT 컨트랙트 배포
 *   2. RPC 동기화 대기
 *   3. 병렬 민팅 실행
 */

import { createWalletClient, http, parseAbi, publicActions } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { opBNBTestnet } from 'viem/chains'
import { execSync } from 'child_process'
import { readFileSync } from 'fs'

// 하드코딩된 설정 (테스트용)
const PRIVATE_KEY = process.env.PRIVATE_KEY
const RECIPIENT = process.env.RECIPIENT || '0xDc45fE9fF7aF3522bB2B88a602670Ab4bE2C6f91'
const RPC_URL = process.env.RPC_URL || 'https://opbnb-testnet-rpc.bnbchain.org'

if (!PRIVATE_KEY) {
  console.error('❌ PRIVATE_KEY 환경변수가 필요합니다.')
  console.error('   예: export PRIVATE_KEY=0x...')
  process.exit(1)
}

console.log('╔════════════════════════════════════════╗')
console.log('║   🤖 자동 NFT 배포 및 민팅           ║')
console.log('╚════════════════════════════════════════╝\n')

// NFT 배포 함수
async function deployNFT() {
  console.log('🚀 NFT 컨트랙트 배포 중...\n')

  try {
    // Forge 스크립트 실행
    execSync(
      `forge script script/DeployNFT.s.sol:DeployNFT ` +
      `--rpc-url ${RPC_URL} ` +
      `--broadcast ` +
      `--private-key ${PRIVATE_KEY} ` +
      `-vv`,
      { stdio: 'inherit' }
    )

    // 배포된 주소 추출
    const chainId = '5611' // opBNB testnet
    const broadcastFile = `broadcast/DeployNFT.s.sol/${chainId}/run-latest.json`
    const broadcast = JSON.parse(readFileSync(broadcastFile, 'utf8'))

    const nftAddress = broadcast.transactions.find(
      tx => tx.contractName === 'BIVENFT'
    )?.contractAddress

    if (!nftAddress) {
      throw new Error('배포된 NFT 주소를 찾을 수 없습니다')
    }

    console.log('\n✅ NFT 배포 완료!')
    console.log(`📍 주소: ${nftAddress}\n`)

    return nftAddress
  } catch (error) {
    console.error('❌ NFT 배포 실패:', error.message)
    process.exit(1)
  }
}

// 파라미터 파싱
const args = process.argv.slice(2)
let batchSize = 200
let repeatCount = 5

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--batch-size' && args[i + 1]) {
    batchSize = parseInt(args[i + 1])
  }
  if (args[i] === '--repeat' && args[i + 1]) {
    repeatCount = parseInt(args[i + 1])
  }
}

const account = privateKeyToAccount(PRIVATE_KEY)
const client = createWalletClient({
  account,
  chain: opBNBTestnet,
  transport: http(RPC_URL)
}).extend(publicActions)

const nftAbi = parseAbi([
  'function batchMint(address to, uint256 count) external'
])

async function parallelMint(nftAddress) {
  console.log('╔════════════════════════════════════════╗')
  console.log('║   🚀 병렬 NFT 민팅 (viem)            ║')
  console.log('╚════════════════════════════════════════╝\n')

  console.log(`📍 NFT 주소: ${nftAddress}`)
  console.log(`👤 수령자: ${RECIPIENT}`)
  console.log(`📦 배치 크기: ${batchSize}`)
  console.log(`🔄 반복 횟수: ${repeatCount}`)
  console.log(`📊 총 민팅: ${batchSize * repeatCount}개\n`)

  // 배치 생성
  const batches = Array.from({ length: repeatCount }, () => ({
    count: batchSize
  }))

  console.log('⏳ RPC 노드 동기화 확인...')

  // 최대 20번 재시도 (60초)
  for (let attempt = 1; attempt <= 20; attempt++) {
    try {
      await client.readContract({
        address: nftAddress,
        abi: parseAbi(['function balanceOf(address) view returns (uint256)']),
        functionName: 'balanceOf',
        args: [RECIPIENT]
      })
      console.log('✅ 컨트랙트 동기화 완료!\n')
      break
    } catch (error) {
      if (attempt === 20) {
        console.error('❌ 컨트랙트 동기화 실패 (60초 타임아웃)')
        process.exit(1)
      }
      console.log(`   📡 시도 ${attempt}/20... (3초 대기)`)
      await new Promise(resolve => setTimeout(resolve, 3000))
    }
  }

  // 시작 시간
  const startTime = Date.now()

  // 현재 nonce 조회
  const baseNonce = await client.getTransactionCount({ address: account.address })

  console.log(`📤 ${repeatCount}개 트랜잭션 동시 전송 중...\n`)

  // 🚀 병렬 전송 (Promise.all) - 명시적 nonce 할당
  const txPromises = batches.map(({ count }, index) => {
    console.log(`  [${index + 1}/${repeatCount}] batchMint ${count}개`)

    return client.writeContract({
      address: nftAddress,
      abi: nftAbi,
      functionName: 'batchMint',
      args: [RECIPIENT, BigInt(count)],
      nonce: baseNonce + index  // 명시적 nonce: 0, 1, 2, 3, 4
    })
  })

  let hashes
  try {
    hashes = await Promise.all(txPromises)
    console.log('\n✅ 모든 트랜잭션 전송 완료!')
  } catch (error) {
    console.error('\n❌ 트랜잭션 전송 실패:', error.message)
    process.exit(1)
  }

  // 전송 완료 시간
  const sendTime = Date.now()
  console.log(`⏱️  전송 소요 시간: ${((sendTime - startTime) / 1000).toFixed(2)}초\n`)

  // 트랜잭션 해시 출력
  console.log('📋 트랜잭션 해시:')
  hashes.forEach((hash, i) => {
    console.log(`  [${i + 1}] ${hash}`)
  })

  console.log('\n⏳ 블록 confirmation 대기 중...\n')

  // 🚀 병렬 대기 (모든 receipt)
  const receiptPromises = hashes.map((hash, index) =>
    client.waitForTransactionReceipt({ hash }).then(receipt => {
      const gasUsed = receipt.gasUsed.toLocaleString()
      console.log(`  ✅ [${index + 1}/${repeatCount}] 블록 #${receipt.blockNumber} (가스: ${gasUsed})`)
      return receipt
    })
  )

  const receipts = await Promise.all(receiptPromises)

  // 완료 시간
  const endTime = Date.now()
  const totalTime = ((endTime - startTime) / 1000).toFixed(2)

  console.log('\n╔════════════════════════════════════════╗')
  console.log('║   ✅ 민팅 완료!                      ║')
  console.log('╚════════════════════════════════════════╝\n')

  // 통계 계산
  const totalGas = receipts.reduce((sum, r) => sum + r.gasUsed, 0n)
  const avgGas = totalGas / BigInt(receipts.length)

  // 블록 범위 계산
  const blockNumbers = receipts.map(r => r.blockNumber)
  const minBlock = Math.min(...blockNumbers)
  const maxBlock = Math.max(...blockNumbers)
  const blockSpan = maxBlock - minBlock + 1

  console.log(`📊 총 민팅: ${batchSize * repeatCount}개`)
  console.log(`⛽ 총 가스: ${totalGas.toLocaleString()}`)
  console.log(`📈 평균 가스: ${avgGas.toLocaleString()}`)
  console.log(`🚀 병렬 전송: ${((sendTime - startTime) / 1000).toFixed(2)}초`)
  console.log(`📦 블록 범위: #${minBlock} ~ #${maxBlock} (${blockSpan}개 블록)`)
  console.log(`⏱️  총 소요 시간: ${totalTime}초 (네트워크 대기 포함)`)

  console.log(`\n🔗 opBNBScan:`)
  console.log(`   https://testnet.opbnbscan.com/address/${nftAddress}`)
  console.log(`   https://testnet.opbnbscan.com/address/${RECIPIENT}\n`)
}

// 메인 실행: 배포 → 민팅
async function main() {
  const nftAddress = await deployNFT()
  await parallelMint(nftAddress)
}

main().catch(console.error)

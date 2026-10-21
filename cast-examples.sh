#!/bin/bash

# Cast Examples for MainVoting v3.0.0
# Contract Address: 0x10Fb9C7BFec7d2059b65c9e70B4F58E2E6fd0eFE
# Network: opBNB Testnet (Chain ID: 5611)

CONTRACT_ADDRESS="0x10Fb9C7BFec7d2059b65c9e70B4F58E2E6fd0eFE"
RPC_URL="https://opbnb-testnet-rpc.bnbchain.org"

echo "=============================================="
echo "MainVoting v3.0.0 Cast Examples"
echo "=============================================="
echo "Contract: $CONTRACT_ADDRESS"
echo "Network: opBNB Testnet"
echo "==============================================\n"

# ============================================
# View Functions (읽기 전용)
# ============================================

echo "\n### 1. Owner 조회"
cast call $CONTRACT_ADDRESS \
  "owner()(address)" \
  --rpc-url $RPC_URL

echo "\n### 2. Executor Signer 조회"
cast call $CONTRACT_ADDRESS \
  "executorSigner()(address)" \
  --rpc-url $RPC_URL

echo "\n### 3. Chain ID 조회"
cast call $CONTRACT_ADDRESS \
  "CHAIN_ID()(uint256)" \
  --rpc-url $RPC_URL

echo "\n### 4. votingId로 투표 수 조회"
# 예시: missionId=1, votingId=1
cast call $CONTRACT_ADDRESS \
  "getVoteCountByVotingId(uint256,uint256)(uint256)" \
  1 1 \
  --rpc-url $RPC_URL

echo "\n### 5. 사용자의 투표 통계 조회"
# 예시: user=0xDc45fE9fF7aF3522bB2B88a602670Ab4bE2C6f91, missionId=1, votingId=1
cast call $CONTRACT_ADDRESS \
  "getUserVotingStat(address,uint256,uint256)" \
  0xDc45fE9fF7aF3522bB2B88a602670Ab4bE2C6f91 1 1 \
  --rpc-url $RPC_URL

echo "\n### 6. 사용자의 votingId로 모든 투표 조회 (신규 함수!)"
# 예시: user=0xDc45fE9fF7aF3522bB2B88a602670Ab4bE2C6f91, missionId=1, votingId=1
cast call $CONTRACT_ADDRESS \
  "getVotesByUserVotingId(address,uint256,uint256)" \
  0xDc45fE9fF7aF3522bB2B88a602670Ab4bE2C6f91 1 1 \
  --rpc-url $RPC_URL

echo "\n### 6-1. 주소 없이 요약만 조회 (신규)"
cast call $CONTRACT_ADDRESS \
  "getVoteSummariesByMissionVotingId(uint256,uint256)" \
  1 1 \
  --rpc-url $RPC_URL

echo "\n### 7. 사용자의 투표 해시 조회 (페이지네이션)"
# 예시: user=0xDc45fE9fF7aF3522bB2B88a602670Ab4bE2C6f91, missionId=1, votingId=1, offset=0, limit=10
cast call $CONTRACT_ADDRESS \
  "getUserVoteHashes(address,uint256,uint256,uint256,uint256)" \
  0xDc45fE9fF7aF3522bB2B88a602670Ab4bE2C6f91 1 1 0 10 \
  --rpc-url $RPC_URL

echo "\n### 8. 투표 해시로 투표 상세 조회"
# 예시: voteHash (실제 해시값으로 교체 필요)
# cast call $CONTRACT_ADDRESS \
#   "getVoteByHash(bytes32)" \
#   0xYourVoteHash \
#   --rpc-url $RPC_URL

# ============================================
# Write Functions (트랜잭션 필요)
# ============================================

echo "\n=============================================="
echo "Write Functions (PRIVATE_KEY 필요)"
echo "==============================================\n"

# 환경변수에서 PRIVATE_KEY 로드
source .env

echo "\n### 9. Executor Signer 설정 (Owner만 가능)"
# 주의: 이미 설정되어 있으므로 필요시에만 실행
# cast send $CONTRACT_ADDRESS \
#   "setExecutorSigner(address)" \
#   0xDc45fE9fF7aF3522bB2B88a602670Ab4bE2C6f91 \
#   --rpc-url $RPC_URL \
#   --private-key $PRIVATE_KEY

echo "\n### 10. 사용자 Nonce 취소 (Owner만 가능)"
# 예시: user=0xUserAddress, newMinUserNonce=100
# cast send $CONTRACT_ADDRESS \
#   "cancelAllUserNonceUpTo(address,uint256)" \
#   0xUserAddress 100 \
#   --rpc-url $RPC_URL \
#   --private-key $PRIVATE_KEY

echo "\n### 11. 배치 Nonce 취소 (Owner/Executor만 가능)"
# 예시: newMinBatchNonce=100
# cast send $CONTRACT_ADDRESS \
#   "cancelAllBatchNonceUpTo(uint256)" \
#   100 \
#   --rpc-url $RPC_URL \
#   --private-key $PRIVATE_KEY

# ============================================
# Constructor Args (검증용)
# ============================================

echo "\n=============================================="
echo "Constructor Args for Verification"
echo "==============================================\n"

echo "Constructor Args (ABI-encoded):"
cast abi-encode "constructor(address)" 0xDc45fE9fF7aF3522bB2B88a602670Ab4bE2C6f91

echo "\n=============================================="
echo "완료!"
echo "=============================================="

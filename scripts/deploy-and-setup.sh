#!/bin/bash

# ========================================
# MainVoting 배포 및 초기 설정 스크립트
# ========================================

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}MainVoting 배포 및 초기 설정${NC}"
echo -e "${GREEN}========================================${NC}"

# 환경 변수 확인
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY 환경 변수가 설정되지 않았습니다.${NC}"
    exit 1
fi

# RPC URL 설정
RPC_URL="https://opbnb-testnet-rpc.bnbchain.org"

# ========================================
# 1. MainVoting 배포
# ========================================
echo -e "\n${YELLOW}[1/5] MainVoting 컨트랙트 배포 중...${NC}"

DEPLOY_OUTPUT=$(forge script script/DeployMainVoting.s.sol:DeployMainVoting \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --json 2>&1)

# 배포된 주소 추출 (로그에서 MainVoting Address 찾기)
VOTING_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -o '0x[a-fA-F0-9]\{40\}' | head -1)

if [ -z "$VOTING_ADDRESS" ]; then
    echo -e "${RED}Error: 컨트랙트 배포 실패${NC}"
    echo "$DEPLOY_OUTPUT"
    exit 1
fi

export VOTING_ADDRESS

echo -e "${GREEN}✅ MainVoting 배포 완료: $VOTING_ADDRESS${NC}"

# ========================================
# 2. Executor 설정
# ========================================
echo -e "\n${YELLOW}[2/5] Executor Signer 등록 중...${NC}"

EXECUTOR_ADDRESS="0x240eCdd1C5a7C30149D43987ce5A3Eb4e9E97897"

cast send $VOTING_ADDRESS \
    "setExecutorSigner(address)" $EXECUTOR_ADDRESS \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --silent

# 확인
REGISTERED_EXECUTOR=$(cast call $VOTING_ADDRESS \
    "executorSigner()(address)" \
    --rpc-url $RPC_URL)

echo -e "${GREEN}✅ Executor 등록 완료: $REGISTERED_EXECUTOR${NC}"

# ========================================
# 3. 투표 타입 등록
# ========================================
echo -e "\n${YELLOW}[3/5] 투표 타입 등록 중...${NC}"

cast send $VOTING_ADDRESS \
    "setVoteTypeName(uint8,string)" 0 "Forget" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --silent

cast send $VOTING_ADDRESS \
    "setVoteTypeName(uint8,string)" 1 "Remember" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --silent

echo -e "${GREEN}✅ 투표 타입 등록 완료 (Forget, Remember)${NC}"

# ========================================
# 4. 미션 및 아티스트 설정
# ========================================
echo -e "\n${YELLOW}[4/5] 미션 및 아티스트 등록 중...${NC}"

# 미션 ID (변경 가능)
MISSION_ID=1

# 아티스트 10명 등록
for i in {1..10}; do
    cast send $VOTING_ADDRESS \
        "setCandidate(uint256,uint256,string,bool)" \
        $MISSION_ID $i "Artist-$i" true \
        --rpc-url $RPC_URL \
        --private-key $PRIVATE_KEY \
        --silent
    
    echo -e "${GREEN}  ✓ Artist-$i 등록 완료${NC}"
    sleep 0.5
done

echo -e "${GREEN}✅ 아티스트 등록 완료 (1-10)${NC}"

# ========================================
# 5. 배포 정보 출력
# ========================================
echo -e "\n${YELLOW}[5/5] 배포 정보 요약${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "컨트랙트 주소: ${GREEN}$VOTING_ADDRESS${NC}"
echo -e "Executor: ${GREEN}$EXECUTOR_ADDRESS${NC}"
echo -e "미션 ID: ${GREEN}$MISSION_ID${NC}"
echo -e "등록된 아티스트: ${GREEN}10명${NC}"
echo -e "RPC: ${GREEN}$RPC_URL${NC}"
echo -e "${GREEN}========================================${NC}"

# 환경 변수 내보내기 명령어 출력
echo -e "\n${YELLOW}환경 변수 설정 (복사해서 사용):${NC}"
echo "export VOTING_ADDRESS=$VOTING_ADDRESS"
echo "export EXECUTOR_ADDRESS=$EXECUTOR_ADDRESS"
echo "export MISSION_ID=$MISSION_ID"

echo -e "\n${GREEN}✅ 모든 설정 완료!${NC}"

#!/bin/bash

# ========================================
# MainVoting 스트레스 테스트 스크립트
# ========================================

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}MainVoting 스트레스 테스트${NC}"
echo -e "${GREEN}========================================${NC}"

# 환경 변수 확인
if [ -z "$VOTING_ADDRESS" ]; then
    echo -e "${RED}Error: VOTING_ADDRESS 환경 변수가 설정되지 않았습니다.${NC}"
    echo -e "${YELLOW}힌트: export VOTING_ADDRESS=0x...${NC}"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY 환경 변수가 설정되지 않았습니다.${NC}"
    exit 1
fi

# RPC URL 설정
RPC_URL="https://opbnb-testnet-rpc.bnbchain.org"

# 스트레스 테스트 파일 경로
STRESS_FILE="${STRESS_FILE:-stress-artifacts/stress-output.json}"

# ========================================
# 스트레스 테스트 실행
# ========================================
echo -e "\n${YELLOW}스트레스 테스트 시작...${NC}"
echo -e "${BLUE}파일: $STRESS_FILE${NC}"
echo -e "${BLUE}컨트랙트: $VOTING_ADDRESS${NC}"

forge script script/SubmitStressVoting.s.sol:SubmitStressVoting \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    -vvv

echo -e "\n${GREEN}✅ 스트레스 테스트 완료!${NC}"

# ========================================
# 결과 확인
# ========================================
echo -e "\n${YELLOW}결과 확인 중...${NC}"

# 예시: 미션 1, 투표 ID 1의 투표 수 조회
MISSION_ID=${MISSION_ID:-1}
VOTING_ID=${VOTING_ID:-1}

VOTE_COUNT=$(cast call $VOTING_ADDRESS \
    "getVoteCountByVotingId(uint256,uint256)(uint256)" \
    $MISSION_ID $VOTING_ID \
    --rpc-url $RPC_URL)

echo -e "${GREEN}========================================${NC}"
echo -e "미션 ID: ${GREEN}$MISSION_ID${NC}"
echo -e "투표 ID: ${GREEN}$VOTING_ID${NC}"
echo -e "총 투표 수: ${GREEN}$VOTE_COUNT${NC}"
echo -e "${GREEN}========================================${NC}"

# 후보별 집계 확인 (Artist-1 ~ Artist-10)
echo -e "\n${YELLOW}후보별 투표 집계:${NC}"
for i in {1..10}; do
    STATS=$(cast call $VOTING_ADDRESS \
        "getCandidateAggregates(uint256,uint256)(uint256,uint256,uint256)" \
        $MISSION_ID $i \
        --rpc-url $RPC_URL)
    
    # 결과 파싱 (remember, forget, total)
    REMEMBER=$(echo $STATS | awk '{print $1}')
    FORGET=$(echo $STATS | awk '{print $2}')
    TOTAL=$(echo $STATS | awk '{print $3}')
    
    echo -e "  Artist-$i: Remember=${GREEN}$REMEMBER${NC}, Forget=${RED}$FORGET${NC}, Total=${BLUE}$TOTAL${NC}"
done

echo -e "\n${GREEN}✅ 모든 테스트 완료!${NC}"

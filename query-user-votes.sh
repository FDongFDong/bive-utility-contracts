#!/bin/bash

# MainVoting 사용자 투표 정보 조회 스크립트

CONTRACT=0x10Fb9C7BFec7d2059b65c9e70B4F58E2E6fd0eFE
RPC_URL=https://opbnb-testnet-rpc.bnbchain.org

# 사용법 체크
if [ -z "$1" ]; then
  echo "사용법: $0 <사용자주소> [missionId]"
  echo ""
  echo "예시:"
  echo "  $0 0xDc45fE9fF7aF3522bB2B88a602670Ab4bE2C6f91"
  echo "  $0 0xDc45fE9fF7aF3522bB2B88a602670Ab4bE2C6f91 1"
  exit 1
fi

USER_ADDRESS=$1
MISSION_ID=${2:-1}  # 기본값 1

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        MainVoting 사용자 투표 정보 조회                       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "🔗 컨트랙트: $CONTRACT"
echo "👤 사용자: $USER_ADDRESS"
echo "🎯 Mission ID: $MISSION_ID"
echo ""

# Mission의 전체 투표 개수 확인
TOTAL_VOTES=$(cast call $CONTRACT \
  "getVoteCount(uint256)(uint256)" \
  $MISSION_ID \
  --rpc-url $RPC_URL)

echo "📊 Mission $MISSION_ID 전체 투표 개수: $TOTAL_VOTES"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Voting ID 자동 탐지 (1부터 시작해서 투표가 없을 때까지)
VOTING_ID=1
FOUND_ANY=false

while true; do
  # 투표 통계 조회
  STAT=$(cast call $CONTRACT \
    "getUserVotingStat(address,uint256,uint256)(bool,uint256,uint256)" \
    $USER_ADDRESS $MISSION_ID $VOTING_ID \
    --rpc-url $RPC_URL 2>/dev/null)

  if [ -z "$STAT" ]; then
    break
  fi

  HAS_VOTED=$(echo "$STAT" | sed -n '1p')
  TOTAL_AMT=$(echo "$STAT" | sed -n '2p')
  COUNT=$(echo "$STAT" | sed -n '3p')

  # 투표를 했다면 상세 정보 출력
  if [ "$HAS_VOTED" = "true" ]; then
    FOUND_ANY=true

    echo "┌─ Voting ID: $VOTING_ID ────────────────────────────────────────┐"
    echo "│"
    echo "│ ✅ 투표 여부: $HAS_VOTED"
    echo "│ 💰 총 포인트: $TOTAL_AMT"
    echo "│ 🔢 투표 횟수: $COUNT"
    echo "│"

    # 투표 해시 조회
    VOTE_HASH=$(cast call $CONTRACT \
      "getUserVoteHashes(address,uint256,uint256,uint256,uint256)(bytes32[])" \
      $USER_ADDRESS $MISSION_ID $VOTING_ID 0 1 \
      --rpc-url $RPC_URL | grep -o "0x[a-fA-F0-9]*" | head -1)

    echo "│ 📝 투표 해시: $VOTE_HASH"
    echo "│"

    # 투표 상세 정보
    DETAIL=$(cast call $CONTRACT \
      "getVoteByHash(bytes32)((uint256,uint256,uint256,address,string,string,string,uint256,uint256))" \
      $VOTE_HASH \
      --rpc-url $RPC_URL)

    # VoteRecord 파싱
    TIMESTAMP=$(echo "$DETAIL" | sed -n 's/.*(//p' | cut -d',' -f1 | xargs)
    USERID=$(echo "$DETAIL" | grep -o '"[^"]*"' | sed -n '1p' | tr -d '"')
    VOTING_FOR=$(echo "$DETAIL" | grep -o '"[^"]*"' | sed -n '2p' | tr -d '"')
    VOTED_ON=$(echo "$DETAIL" | grep -o '"[^"]*"' | sed -n '3p' | tr -d '"')
    VOTING_AMT=$(echo "$DETAIL" | cut -d',' -f8 | xargs)
    DEADLINE=$(echo "$DETAIL" | cut -d',' -f9 | cut -d')' -f1 | xargs)

    # 타임스탬프를 날짜로 변환
    if command -v date &> /dev/null; then
      DATE_STR=$(date -r $TIMESTAMP "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -d @$TIMESTAMP "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$TIMESTAMP")
    else
      DATE_STR=$TIMESTAMP
    fi

    echo "│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "│ 📋 투표 상세 정보:"
    echo "│"
    echo "│   👤 사용자 ID: $USERID"
    echo "│   🎤 투표 대상: $VOTING_FOR"
    echo "│   🎵 선택 항목: $VOTED_ON"
    echo "│   💎 포인트: $VOTING_AMT"
    echo "│   ⏰ 투표 시각: $DATE_STR"
    echo "│"
    echo "└────────────────────────────────────────────────────────────────┘"
    echo ""
  fi

  VOTING_ID=$((VOTING_ID + 1))

  # 안전장치: 100개 이상 조회하지 않음
  if [ $VOTING_ID -gt 100 ]; then
    break
  fi
done

if [ "$FOUND_ANY" = false ]; then
  echo "ℹ️  이 사용자는 Mission $MISSION_ID에 투표하지 않았습니다."
  echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 조회 완료"
echo ""

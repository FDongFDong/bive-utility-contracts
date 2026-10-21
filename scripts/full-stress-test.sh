#!/usr/bin/env bash
# =============================================================================
# full-stress-test.sh
#
# MainVoting 스트레스 테스트 통합 스크립트
#
# 주요 기능:
#   - 컨트랙트 초기 설정 (ExecutorSigner, VoteType, Artist)
#   - burst-stress.mjs 실행
#   - 결과 확인
#
# 사용법:
#   ./scripts/full-stress-test.sh [옵션]
#
# 옵션:
#   --count N           동시 배치 수 (기본: 2)
#   --votes N           배치당 투표 수 (기본: 100)
#   --users N           유저 수 (기본: 20)
#   --mission N         미션 ID (기본: 1)
#   --skip-setup        컨트랙트 설정 건너뛰기
#   --dry-run           실제 제출 없이 데이터 생성만
#   --voting-address    컨트랙트 주소 지정
#
# 환경변수:
#   VOTING_ADDRESS      (필수) 컨트랙트 주소
#   PRIVATE_KEY         (필수) 실행자 개인키
#   RPC_URL             (선택) RPC URL (기본: opBNB testnet)
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# 스크립트 디렉토리 및 환경 설정
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

# .env 파일 로드
if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

# -----------------------------------------------------------------------------
# 기본값 설정
# -----------------------------------------------------------------------------
COUNT=2
TOTAL_VOTES=100
USER_COUNT=10
MISSION_ID=1
SKIP_SETUP=false
DRY_RUN=false
RPC_URL="${RPC_URL:-https://opbnb-testnet-rpc.bnbchain.org}"

# -----------------------------------------------------------------------------
# 인자 파싱
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    --count)
      COUNT="$2"
      shift 2
      ;;
    --votes)
      TOTAL_VOTES="$2"
      shift 2
      ;;
    --users)
      USER_COUNT="$2"
      shift 2
      ;;
    --mission)
      MISSION_ID="$2"
      shift 2
      ;;
    --skip-setup)
      SKIP_SETUP=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --voting-address)
      VOTING_ADDRESS="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  --count N           Number of concurrent batches (default: 2)"
      echo "  --votes N           Votes per batch (default: 100)"
      echo "  --users N           Number of users (default: 20)"
      echo "  --mission N         Mission ID (default: 1)"
      echo "  --skip-setup        Skip contract setup"
      echo "  --dry-run           Generate data only, no submission"
      echo "  --voting-address    Contract address"
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: $1"
      exit 1
      ;;
  esac
done

# -----------------------------------------------------------------------------
# 필수 환경변수 확인
# -----------------------------------------------------------------------------
if [[ -z "${PRIVATE_KEY:-}" ]]; then
  echo "[ERROR] PRIVATE_KEY environment variable is required."
  echo "   export PRIVATE_KEY=0x..."
  exit 1
fi

if [[ -z "${VOTING_ADDRESS:-}" ]]; then
  echo "[ERROR] VOTING_ADDRESS environment variable is required."
  echo "   export VOTING_ADDRESS=0x..."
  exit 1
fi

# 실행자 주소 가져오기
EXECUTOR_ADDRESS=$(cast wallet address --private-key "$PRIVATE_KEY")

# -----------------------------------------------------------------------------
# 배너 출력
# -----------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  MainVoting Stress Test"
echo "============================================================"
echo ""
echo "[CONFIG]"
echo "   count:          $COUNT"
echo "   votes:          $TOTAL_VOTES"
echo "   users:          $USER_COUNT"
echo "   missionId:      $MISSION_ID"
echo "   votingAddress:  $VOTING_ADDRESS"
echo "   executor:       $EXECUTOR_ADDRESS"
echo "   rpcUrl:         $RPC_URL"
echo ""

# -----------------------------------------------------------------------------
# Phase 1: 컨트랙트 초기 설정
# -----------------------------------------------------------------------------
if [[ "$SKIP_SETUP" == "false" ]]; then
  echo "============================================================"
  echo "  Phase 1: Contract Setup"
  echo "============================================================"
  echo ""

  # 1.1 ExecutorSigner 설정
  echo "[SETUP] 1.1 Setting ExecutorSigner..."
  cast send "$VOTING_ADDRESS" \
    "setExecutorSigner(address)" \
    "$EXECUTOR_ADDRESS" \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --quiet || true
  echo "   [OK] ExecutorSigner: $EXECUTOR_ADDRESS"

  # 1.2 VoteType 설정
  echo "[SETUP] 1.2 Setting VoteTypes..."
  cast send "$VOTING_ADDRESS" \
    "setVoteTypeName(uint8,string)" \
    0 "Forget" \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --quiet || true
  echo "   [OK] VoteType 0: Forget"

  cast send "$VOTING_ADDRESS" \
    "setVoteTypeName(uint8,string)" \
    1 "Remember" \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --quiet || true
  echo "   [OK] VoteType 1: Remember"

  # 1.3 아티스트 설정 (1~10)
  echo "[SETUP] 1.3 Setting Artists (1~10)..."
  for i in {1..10}; do
    cast send "$VOTING_ADDRESS" \
      "setArtist(uint256,uint256,string,bool)" \
      "$MISSION_ID" "$i" "Artist-$i" true \
      --rpc-url "$RPC_URL" \
      --private-key "$PRIVATE_KEY" \
      --quiet || true
    echo "   [OK] Artist-$i (missionId=$MISSION_ID, optionId=$i)"
  done

  echo ""
  echo "[OK] Contract setup complete"
  echo ""
fi

# -----------------------------------------------------------------------------
# Phase 2: 스트레스 테스트 실행
# -----------------------------------------------------------------------------
echo "============================================================"
echo "  Phase 2: Stress Test Execution"
echo "============================================================"
echo ""

DRY_RUN_FLAG=""
if [[ "$DRY_RUN" == "true" ]]; then
  DRY_RUN_FLAG="--dryRun"
  echo "[INFO] Dry Run mode: data generation only, no submission"
  echo ""
fi

node scripts/burst-stress.mjs \
  --count "$COUNT" \
  --totalVotes "$TOTAL_VOTES" \
  --userCount "$USER_COUNT" \
  --missionId "$MISSION_ID" \
  --votingAddress "$VOTING_ADDRESS" \
  --rpcUrl "$RPC_URL" \
  $DRY_RUN_FLAG

# -----------------------------------------------------------------------------
# Phase 3: 결과 확인
# -----------------------------------------------------------------------------
if [[ "$DRY_RUN" == "false" ]]; then
  echo ""
  echo "============================================================"
  echo "  Phase 3: Results Verification"
  echo "============================================================"
  echo ""

  echo "[RESULTS] Artist vote counts:"
  for i in {1..10}; do
    RESULT=$(cast call "$VOTING_ADDRESS" \
      "getArtistAggregates(uint256,uint256)(uint256,uint256,uint256)" \
      "$MISSION_ID" "$i" \
      --rpc-url "$RPC_URL" 2>/dev/null || echo "0 0 0")

    REMEMBER=$(echo "$RESULT" | awk '{print $1}')
    FORGET=$(echo "$RESULT" | awk '{print $2}')
    TOTAL=$(echo "$RESULT" | awk '{print $3}')

    if [[ "$TOTAL" != "0" ]]; then
      echo "   Artist-$i: Remember=$REMEMBER, Forget=$FORGET, Total=$TOTAL"
    fi
  done
  echo ""
fi

echo "[OK] Stress test complete!"
echo ""

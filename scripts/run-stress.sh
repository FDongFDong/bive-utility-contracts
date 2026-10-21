#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)
cd "$ROOT_DIR"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq가 필요합니다. 설치 후 다시 시도해주세요." >&2
  exit 1
fi

if ! command -v cast >/dev/null 2>&1; then
  echo "Foundry 'cast' 명령이 필요합니다." >&2
  exit 1
fi

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [[ -z "${PRIVATE_KEY:-}" ]]; then
  echo "환경변수 PRIVATE_KEY가 설정되어야 합니다." >&2
  exit 1
fi

RPC_URL="${RPC_URL:-https://opbnb-testnet-rpc.bnbchain.org}"
CHAIN_ID="${CHAIN_ID:-5611}"
TOTAL_VOTES="${TOTAL_VOTES:-${1:-100}}"
USER_COUNT="${USER_COUNT:-20}"
MISSION_ID="${MISSION_ID:-1}"
GAS_LIMIT="${GAS_LIMIT:-}"
EXECUTOR_PRIVATE_KEY="${EXECUTOR_PRIVATE_KEY:-$PRIVATE_KEY}"

OWNER_ADDRESS="$(cast wallet address --private-key "$PRIVATE_KEY")"
EXECUTOR_ADDRESS="$(cast wallet address --private-key "$EXECUTOR_PRIVATE_KEY")"
TIMESTAMP="$(date +%s)"
STRESS_FILE_NAME="stress-${TOTAL_VOTES}-${MISSION_ID}-${TIMESTAMP}.json"
STRESS_FILE_PATH="$ROOT_DIR/stress-artifacts/${STRESS_FILE_NAME}"

export FOUNDRY_FS_PERMISSIONS="read($ROOT_DIR),write($ROOT_DIR),write($ROOT_DIR/stress-artifacts)"

echo "== 1. MainVoting 배포 (owner: $OWNER_ADDRESS) =="
forge script script/DeployMainVoting.s.sol:DeployMainVoting \
  --rpc-url "$RPC_URL" \
  --broadcast -q

DEPLOY_JSON="$ROOT_DIR/broadcast/DeployMainVoting.s.sol/${CHAIN_ID}/run-latest.json"
if [[ ! -f "$DEPLOY_JSON" ]]; then
  echo "배포 결과 파일을 찾을 수 없습니다: $DEPLOY_JSON" >&2
  exit 1
fi
VOTING_ADDRESS="$(jq -r '.transactions[0].contractAddress' "$DEPLOY_JSON")"
if [[ "$VOTING_ADDRESS" == "null" || -z "$VOTING_ADDRESS" ]]; then
  echo "배포 주소 파싱 실패" >&2
  exit 1
fi
echo "배포 완료: $VOTING_ADDRESS"

echo "== 2. Executor 설정 (executor: $EXECUTOR_ADDRESS) =="
cast send "$VOTING_ADDRESS" \
  "setExecutorSigner(address)" \
  "$EXECUTOR_ADDRESS" \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" >/tmp/stress-exec.log

echo "== 3. 서명 데이터 생성 (${TOTAL_VOTES} votes) =="
env \
  PRIVATE_KEY="$EXECUTOR_PRIVATE_KEY" \
  VOTING_ADDRESS="$VOTING_ADDRESS" \
  TOTAL_VOTES="$TOTAL_VOTES" \
  USER_COUNT="$USER_COUNT" \
  MISSION_ID="$MISSION_ID" \
  STRESS_OUT="$STRESS_FILE_NAME" \
  RPC_URL="$RPC_URL" \
  npm run --silent stress:viem >/tmp/stress-generate.log

if [[ ! -f "$STRESS_FILE_PATH" ]]; then
  echo "생성된 스트레스 파일을 찾을 수 없습니다: $STRESS_FILE_PATH" >&2
  exit 1
fi

echo "== 4. 투표 제출 (${STRESS_FILE_NAME}) =="
declare -a SUBMIT_ENV=(
  "PRIVATE_KEY=$EXECUTOR_PRIVATE_KEY"
  "RPC_URL=$RPC_URL"
  "VOTING_ADDRESS=$VOTING_ADDRESS"
)
if [[ -n "$GAS_LIMIT" ]]; then
  SUBMIT_ENV+=("GAS_LIMIT=$GAS_LIMIT")
fi
env "${SUBMIT_ENV[@]}" npm run --silent stress:submit -- --file "$STRESS_FILE_PATH"

echo "✅ 완료"
echo "- 컨트랙트 주소: $VOTING_ADDRESS"
echo "- Executor: $EXECUTOR_ADDRESS"
echo "- 스트레스 파일: $STRESS_FILE_PATH"
echo "- 총 투표 수: $TOTAL_VOTES (유저 ${USER_COUNT}명)"

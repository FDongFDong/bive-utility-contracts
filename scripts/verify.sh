#!/usr/bin/env bash
#
# 커밋 전 검증의 단일 진입점.
#
# 이 저장소에는 자동으로 도는 CI가 없다. origin은 Bitbucket인데
# bitbucket-pipelines.yml이 없고, .github/workflows/의 GitHub Actions는
# Bitbucket에서 실행되지 않는다. 즉 여기 있는 검사를 아무도 대신 돌려주지 않는다.
#
# 검증 명령의 단일 출처는 이 파일이다. 새 검사를 추가할 때는 README나 CLAUDE.md가
# 아니라 이 파일에 추가한다. 문서는 이 스크립트를 가리키기만 한다.
#
# 사용법:
#   ./scripts/verify.sh              # 전체 (약 5분)
#   ./scripts/verify.sh contracts    # 컨트랙트만 (약 4분)
#   ./scripts/verify.sh demo         # demo-next만 (약 1분)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

TARGET="${1:-all}"
FAILED_STEP=""

case "$TARGET" in
  all | contracts | demo) ;;
  -h | --help | help)
    # shebang 다음 주석 블록을 그대로 도움말로 쓴다. 줄 번호를 박아두면
    # 헤더를 고칠 때마다 어긋나므로, 주석이 끝나는 지점을 스스로 찾는다.
    awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "${BASH_SOURCE[0]}"
    exit 0
    ;;
  *)
    echo "알 수 없는 대상: $TARGET (사용 가능: all, contracts, demo)" >&2
    exit 2
    ;;
esac

# 실패한 단계를 즉시 알 수 있게 각 명령을 이름과 함께 실행한다.
# 뒤 단계는 앞 단계가 성공해야 의미가 있으므로 첫 실패에서 멈춘다.
run_step() {
  local label="$1"
  shift
  printf '\n\033[1m▶ %s\033[0m\n' "$label"
  if ! "$@"; then
    FAILED_STEP="$label"
    return 1
  fi
}

require_tool() {
  if ! command -v "$1" > /dev/null 2>&1; then
    echo "필요한 도구가 없습니다: $1" >&2
    echo "  $2" >&2
    exit 127
  fi
}

# 배포된 6개 컨트랙트를 solc로 재컴파일해 바이트코드가 비트 단위로 같은지 본다.
# 소스가 배포본과 어긋나는 상황은 이 검사로만 잡힌다.
#
# 컨트랙트 소스를 고쳐도, demo-next/contract-artifacts/를 재생성해도 깨질 수 있다.
# 두 경로가 서로 다른 대상에 속하므로 양쪽에서 모두 돌리고, all일 때만 한 번으로 줄인다.
ARTIFACTS_CHECKED=0
verify_artifacts() {
  if [ "$ARTIFACTS_CHECKED" = "1" ]; then
    return 0
  fi
  ARTIFACTS_CHECKED=1
  run_step "배포 바이트코드 재현 검증" \
    npm --prefix demo-next run check:contract-artifacts
}

verify_contracts() {
  require_tool forge "설치: curl -L https://foundry.paradigm.xyz | bash && foundryup"

  run_step "forge build" forge build || return 1
  # invariant 스위트 5개가 포함돼 7~8분 걸린다. 느리다고 빼면 안 된다.
  run_step "forge test (약 7~8분)" forge test || return 1
  # BIVETicketNFT는 0.8.35 전용 프로파일로 한 번 더 본다.
  # invariant 스위트는 여기 넣지 않는다. compilation_restrictions가 모든 프로파일에서
  # 0.8.35를 강제하므로 위 forge test가 이미 같은 바이너리를 돌린 뒤이고,
  # ticket 프로파일이 더 보는 건 산출물 경로 분리뿐이라 240초를 더 쓸 값이 없다.
  run_step "forge test (ticket 프로파일)" \
    env FOUNDRY_PROFILE=ticket forge test --match-path test/BIVETicketNFT.t.sol || return 1
  # 이미 배포된 0.8.30 소스를 재포맷하면 컴파일러 메타데이터가 바뀌어
  # 배포본과 바이트코드가 달라진다. 그래서 신규 ticket 계열만 검사한다.
  run_step "forge fmt --check (ticket 계열)" \
    forge fmt --check \
    src/nft/BIVETicketNFT.sol \
    script/DeployTicketNFT.s.sol \
    test/BIVETicketNFT.t.sol \
    test/invariant/BIVETicketNFT.invariant.t.sol || return 1
  verify_artifacts || return 1
}

# 싼 검사를 앞에 둔다. lint 오류 때문에 next build를 다 기다린 뒤 실패하면 낭비다.
verify_demo() {
  run_step "eslint" npm --prefix demo-next run lint || return 1
  run_step "공개 배포 보안 가드" \
    npm --prefix demo-next run check:public-security || return 1
  run_step "공개 배포 보안 가드 회귀 테스트" \
    npm --prefix demo-next run test:public-security || return 1
  run_step "vitest" npm --prefix demo-next run test:run || return 1
  verify_artifacts || return 1
  # next build는 prebuild로 보안 가드를 다시 돌린다. 중복이지만 몇 초라 그대로 둔다.
  # 타입 검사(tsc)도 이 단계가 겸한다.
  run_step "next build" npm --prefix demo-next run build || return 1
}

# 컨트랙트 검증도 solc 재현에 demo-next 의존성을 쓰므로 두 대상 모두 확인한다.
if [ ! -d demo-next/node_modules ]; then
  echo "demo-next/node_modules가 없습니다. 먼저 의존성을 설치하세요:" >&2
  echo "  npm ci --prefix demo-next" >&2
  exit 1
fi

case "$TARGET" in
  contracts) verify_contracts ;;
  demo) verify_demo ;;
  all) verify_contracts && verify_demo ;;
esac

if [ -n "$FAILED_STEP" ]; then
  printf '\n\033[31m✗ 검증 실패: %s\033[0m\n' "$FAILED_STEP" >&2
  exit 1
fi

printf '\n\033[32m✓ 검증 통과 (%s)\033[0m\n' "$TARGET"

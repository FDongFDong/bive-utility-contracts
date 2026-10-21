# Stress Test Guide

MainVoting 컨트랙트 스트레스 테스트 가이드입니다.

## 개요

스트레스 테스트는 대량의 투표 데이터를 생성하고 블록체인에 제출하여 컨트랙트 성능을 검증합니다.

### 주요 스크립트

| 스크립트 | 역할 |
|----------|------|
| `full-stress-test.sh` | 통합 실행 스크립트 (설정 + 테스트) |
| `burst-stress.mjs` | 오케스트레이터 (생성/제출 조율) |
| `stress-viem.mjs` | 서명 데이터 생성 |
| `submit-stress-viem.mjs` | 블록체인 제출 |

## 실행 흐름

### 1. full-stress-test.sh

진입점 스크립트입니다. 컨트랙트 초기 설정 후 burst-stress.mjs를 호출합니다.

```bash
./scripts/full-stress-test.sh --count 3 --votes 100 --users 20
```

**Phase 1: 컨트랙트 초기 설정** (--skip-setup 없으면 실행)
- setExecutorSigner(address) - Executor 권한 부여
- setVoteTypeName(0, "Forget") / setVoteTypeName(1, "Remember")
- setArtist(missionId, 1~10, "Artist-N", true) - 10개 아티스트 등록

**Phase 2: burst-stress.mjs 호출**

**Phase 3: 결과 확인** - 아티스트별 투표 집계 조회

### 2. burst-stress.mjs

생성과 제출을 조율하는 오케스트레이터입니다.

**Phase 1: 서명 데이터 생성 (순차 실행)**

stress-viem.mjs를 count 횟수만큼 순차적으로 호출하여 각각의 서명 파일을 생성합니다.

```
stress-viem.mjs 호출 #1 -> burst-100-1-{timestamp}-0.json
stress-viem.mjs 호출 #2 -> burst-100-1-{timestamp}-1.json
stress-viem.mjs 호출 #3 -> burst-100-1-{timestamp}-2.json
```

**Phase 2: 동시 제출 (병렬 실행)**

생성된 파일들을 submit-stress-viem.mjs로 병렬 제출합니다. 각 트랜잭션은 서로 다른 nonce를 사용합니다.

```
submit #1 (nonce=N)   -> 동시 전송
submit #2 (nonce=N+1) -> 동시 전송
submit #3 (nonce=N+2) -> 동시 전송
```

### 3. stress-viem.mjs

서명 데이터를 생성하는 핵심 스크립트입니다.

**Step 1: 유저 Private Key 생성**

결정론적으로 유저 Private Key를 생성합니다 (테스트용).

```javascript
deriveUserKey(index) = keccak256(abi.encode(SALT, index + 1))
// SALT = 0x9999...9999 (고정값)
```

동일 index면 항상 같은 주소가 생성되어 재현 가능합니다.

**Step 2: VoteRecord 생성**

각 유저마다 votesPerUser개의 투표 레코드를 생성합니다.

- timestamp: 현재 시간
- missionId: 설정된 미션 ID
- votingId: 랜덤 생성 (유저별 고유)
- optionId: (j % 10) + 1 (1~10 순환)
- voteType: 전반부 Remember(1), 후반부 Forget(0)
- userId: "stress-{u}"
- votingAmt: 10 + j

**Step 3: VoteRecord 해시 계산 (EIP-712)**

```javascript
hashVoteRecord(record, userAddress) = keccak256(
  abi.encode(
    VOTE_RECORD_TYPEHASH,
    timestamp, missionId, votingId, optionId,
    voteType, votingAmt, user
  )
)
```

**Step 4: UserBatch 서명**

각 유저가 자신의 투표 배치에 서명합니다.

```javascript
recordsHash = keccak256(concat(hash1, hash2, ... hashN))

userAccount.signTypedData({
  domain: { name: 'MainVoting', version: '1', chainId, verifyingContract },
  types: { UserBatch: [user, userNonce, recordsHash] },
  message: { user, userNonce, recordsHash }
})
```

**Step 5: Executor(Batch) 서명**

Executor가 전체 배치를 승인합니다.

```javascript
executorAccount.signTypedData({
  domain: { name: 'MainVoting', version: '1', chainId, verifyingContract },
  types: { Batch: [{ name: 'batchNonce', type: 'uint256' }] },
  message: { batchNonce }
})
```

**Step 6: JSON 파일 저장**

```
stress-artifacts/burst-{votes}-{mission}-{timestamp}-{i}.json
```

### 4. submit-stress-viem.mjs

생성된 서명 데이터를 블록체인에 제출합니다.

- JSON 파일 로드
- ABI 디코딩
- 가스 추정 (25% 버퍼 적용)
- submitMultiUserBatch 호출
- txHash 출력

## 서명 구조

### 서명 종류

| 서명 | 서명자 | 서명 대상 | 용도 |
|------|--------|-----------|------|
| UserBatch 서명 | 각 유저 (결정론적 생성) | { user, userNonce, recordsHash } | 본인 투표 배치 승인 |
| Executor 서명 | Executor (PRIVATE_KEY) | { batchNonce } | 전체 배치 실행 승인 |

### EIP-712 Domain

```javascript
{
  name: 'MainVoting',
  version: '1',
  chainId: 5611,  // opBNB Testnet
  verifyingContract: votingAddress
}
```

컨트랙트와 정확히 일치해야 서명 검증이 통과됩니다.

## 사용법

### 기본 실행

```bash
export VOTING_ADDRESS=0x...
export PRIVATE_KEY=0x...
export RPC_URL=https://opbnb-testnet-rpc.bnbchain.org

./scripts/full-stress-test.sh
```

### 옵션

| 옵션 | 설명 | 기본값 |
|------|------|--------|
| --count N | 동시 배치 수 | 2 |
| --votes N | 배치당 투표 수 | 100 |
| --users N | 유저 수 | 20 |
| --mission N | 미션 ID | 1 |
| --skip-setup | 컨트랙트 설정 건너뛰기 | - |
| --dry-run | 실제 제출 없이 데이터 생성만 | - |

### 예시

```bash
# 3개 배치, 각 200 투표, 40명 유저
./scripts/full-stress-test.sh --count 3 --votes 200 --users 40

# 설정 건너뛰고 테스트만
./scripts/full-stress-test.sh --skip-setup --count 2 --votes 100

# Dry run (제출 없이 데이터만 생성)
./scripts/full-stress-test.sh --dry-run --count 5 --votes 100
```

## 제한사항

- 유저당 최대 투표 수: 20
- 배치당 최대 총 투표 수: 2000
- 유저당 투표 수는 짝수여야 함 (Remember/Forget 균등 분배)
- totalVotes는 userCount로 나누어 떨어져야 함

## 출력 파일

생성된 서명 파일은 `stress-artifacts/` 디렉토리에 저장됩니다.

```
stress-artifacts/
  burst-100-1-1702345678901-0.json
  burst-100-1-1702345678901-1.json
  burst-100-1-1702345678901-2.json
```

각 파일 구조:

```json
{
  "missionId": 1,
  "totalVotes": 100,
  "userCount": 20,
  "batchNonce": 123456,
  "batches": "0x...",
  "executorSig": "0x...",
  "metadata": {
    "votingAddress": "0x...",
    "chainId": 5611,
    "timestamp": "1702345678"
  }
}
```

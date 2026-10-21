# MainVoting 배포 및 스트레스 테스트 가이드

## 🚀 빠른 시작

### 1. 배포 및 초기 설정

```bash
# Private key 설정
export PRIVATE_KEY=<YOUR_PRIVATE_KEY>

# 배포 및 설정 실행 (한 번에)
./scripts/deploy-and-setup.sh
```

이 스크립트는 자동으로:
- ✅ MainVoting 컨트랙트 배포
- ✅ Executor signer 등록
- ✅ 투표 타입 등록 (Forget, Remember)
- ✅ 아티스트 10명 등록 (Artist-1 ~ Artist-10)

### 2. 환경 변수 설정

배포 완료 후 출력된 환경 변수를 복사해서 설정:

```bash
export VOTING_ADDRESS=0x... # 배포된 주소
export EXECUTOR_ADDRESS=0x240eCdd1C5a7C30149D43987ce5A3Eb4e9E97897
export MISSION_ID=1
```

### 3. 스트레스 테스트 실행

```bash
# 기본 경로(stress-artifacts/stress-output.json) 사용
./scripts/stress-test.sh

# 또는 커스텀 파일 경로 지정
STRESS_FILE=custom-path/test.json ./scripts/stress-test.sh
```

---

## 📋 수동 배포 단계별 가이드

자동화 스크립트 대신 수동으로 진행하려면:

### 1단계: 컨트랙트 배포

```bash
forge script script/DeployMainVoting.s.sol:DeployMainVoting \
    --rpc-url https://opbnb-testnet-rpc.bnbchain.org \
    --private-key $PRIVATE_KEY \
    --broadcast
```

### 2단계: Executor 등록

```bash
export VOTING_ADDRESS=0x... # 배포된 주소

cast send $VOTING_ADDRESS \
    "setExecutorSigner(address)" 0x240eCdd1C5a7C30149D43987ce5A3Eb4e9E97897 \
    --rpc-url https://opbnb-testnet-rpc.bnbchain.org \
    --private-key $PRIVATE_KEY

# 확인
cast call $VOTING_ADDRESS \
    "executorSigner()(address)" \
    --rpc-url https://opbnb-testnet-rpc.bnbchain.org
```

### 3단계: 투표 타입 등록

```bash
# Forget (0)
cast send $VOTING_ADDRESS \
    "setVoteTypeName(uint8,string)" 0 "Forget" \
    --rpc-url https://opbnb-testnet-rpc.bnbchain.org \
    --private-key $PRIVATE_KEY

# Remember (1)
cast send $VOTING_ADDRESS \
    "setVoteTypeName(uint8,string)" 1 "Remember" \
    --rpc-url https://opbnb-testnet-rpc.bnbchain.org \
    --private-key $PRIVATE_KEY
```

### 4단계: 아티스트 등록

```bash
MISSION_ID=1

for i in {1..10}; do
    cast send $VOTING_ADDRESS \
        "setCandidate(uint256,uint256,string,bool)" \
        $MISSION_ID $i "Artist-$i" true \
        --rpc-url https://opbnb-testnet-rpc.bnbchain.org \
        --private-key $PRIVATE_KEY
    echo "✅ Artist-$i 등록 완료"
    sleep 1
done
```

---

## 🔧 주요 변경 사항

### MainVoting 컨트랙트 수정 내용

1. **2차원 배열 구조 도입** (`VoteRecord[][]`)
   - 유저별로 그룹화된 레코드를 직관적으로 처리
   - `recordCounts` 파라미터 제거됨

2. **함수 시그니처 변경**

```solidity
// 이전
submitMultiUserBatch(
    VoteRecord[] records,
    UserBatchSig[] userBatchSigs,
    uint256[] recordCounts,  // ❌ 제거됨
    uint256 batchNonce,
    bytes executorSig
)

// 현재
submitMultiUserBatch(
    VoteRecord[][] records,  // ✅ 2차원 배열
    UserBatchSig[] userBatchSigs,
    uint256 batchNonce,
    bytes executorSig
)
```

---

## 📊 결과 확인

### 투표 수 조회

```bash
cast call $VOTING_ADDRESS \
    "getVoteCountByVotingId(uint256,uint256)(uint256)" \
    1 1 \
    --rpc-url https://opbnb-testnet-rpc.bnbchain.org
```

### 후보별 집계 조회

```bash
# Artist-1의 집계 (Remember, Forget, Total)
cast call $VOTING_ADDRESS \
    "getCandidateAggregates(uint256,uint256)(uint256,uint256,uint256)" \
    1 1 \
    --rpc-url https://opbnb-testnet-rpc.bnbchain.org
```

### 투표 상세 내역 조회

```bash
cast call $VOTING_ADDRESS \
    "getVoteSummariesByMissionVotingId(uint256,uint256)" \
    1 1 \
    --rpc-url https://opbnb-testnet-rpc.bnbchain.org
```

---

## 🛠️ 트러블슈팅

### 배포 실패 시

1. **RPC 연결 확인**
   ```bash
   cast block-number --rpc-url https://opbnb-testnet-rpc.bnbchain.org
   ```

2. **가스비 확인**
   ```bash
   cast balance $YOUR_ADDRESS --rpc-url https://opbnb-testnet-rpc.bnbchain.org
   ```

3. **네트워크 정보**
   - Chain ID: 5611 (opBNB Testnet)
   - 가스 토큰: tBNB
   - Faucet: https://www.bnbchain.org/en/testnet-faucet

### 스트레스 테스트 실패 시

1. **JSON 파일 확인**
   ```bash
   cat stress-artifacts/stress-output.json | jq .
   ```

2. **Executor Nonce 확인**
   ```bash
   cast call $VOTING_ADDRESS \
       "minBatchNonce(address)(uint256)" \
       $EXECUTOR_ADDRESS \
       --rpc-url https://opbnb-testnet-rpc.bnbchain.org
   ```

3. **User Nonce 확인**
   ```bash
   cast call $VOTING_ADDRESS \
       "minUserNonce(address)(uint256)" \
       $USER_ADDRESS \
       --rpc-url https://opbnb-testnet-rpc.bnbchain.org
   ```

---

## 📝 참고 사항

- **Private Key 보안**: 절대로 mainnet private key를 테스트넷에 사용하지 마세요
- **RPC Rate Limit**: opBNB testnet RPC는 rate limit이 있을 수 있습니다
- **가스비**: 테스트넷이지만 충분한 tBNB가 필요합니다

---

## 🔗 유용한 링크

- [opBNB Testnet Explorer](https://testnet.opbnbscan.com/)
- [opBNB Faucet](https://www.bnbchain.org/en/testnet-faucet)
- [Foundry Book](https://book.getfoundry.sh/)

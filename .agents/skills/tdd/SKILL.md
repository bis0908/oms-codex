---
name: tdd
description: data-layer가 데이터 접근·API·서비스 구현과 같은 컨텍스트에서 Red→Green을 수행할 때 사용하는 TDD 스킬.
---

## 재발 방지 학습 (작업 전 필독)

이 영역의 과거 테스트 계약 오류 사례는 `docs/compound/tdd/README.md` 인덱스에 유형별로 정리돼 있다(해당 경로가 없으면 아직 누적된 학습이 없는 것이므로 건너뛰고 진행한다). 경로가 있으면 작업 시작 전 그 README를 읽고, 각 유형 파일 **첫 줄 load-when 술어**를 확인하여 현재 작업이 해당하는 사례 파일만 로드하라(전부 읽지 말 것). 사례를 이 SKILL.md에 누적하지 않는 이유는 스킬 로딩 컨텍스트를 상수 크기로 유지하기 위함이다 — compound-learner가 `docs/compound/`에만 기록한다(load-when 술어·인덱스 형식 규범은 `compound` 스킬의 `### Phase 2: docs/compound 작성` 참조).

## TDD 절차

### 1단계: 명세 파악

티켓과 레거시 분석(있을 경우)에서 구현 대상 함수를 파악한다.

레거시 소스가 있는 포팅 프로젝트라면 레거시 동작이 1차 스펙이다. `_workspace/01_legacy_*.md`가 있으면 반드시 참조한다. 레거시 분석이 없으면(신규 프로젝트 등) 티켓·마일스톤 스펙만으로 진행한다.

```
예시)
티켓: "M5-T03 — 프로필 조회 API"
레거시(있을 경우): _workspace/01_legacy_member.md의 원본 프로필 조회 동작
→ 구현 대상: GET /api/profiles/[no] 엔드포인트 + 데이터 접근 레이어의 조회 함수
```

### 2단계: 테스트 파일 작성

**파일 위치**

| 구현 대상 | 테스트 파일 위치 |
|---|---|
| 데이터 접근 레이어 모듈 | 프로젝트 테스트 컨벤션에 따른 대응 테스트 파일 |
| API 엔드포인트 핸들러 | 프로젝트 테스트 컨벤션에 따른 대응 테스트 파일 |
| 서비스 모듈 | 프로젝트 테스트 컨벤션에 따른 대응 테스트 파일 |

**테스트 환경 지정 필수**

프로젝트 테스트 러너의 기본 환경이 브라우저를 모사하는 환경(DOM 시뮬레이터)이면, DB 연결이나 네이티브 모듈·런타임 API가 필요한 테스트 파일에서는 연결이 실패한다. 이런 파일에는 프로젝트 테스트 환경 설정으로 노드(서버) 환경을 명시적으로 지정한다.

```
예(프로젝트별): 파일 최상단에 노드 환경 지정 주석을 둔다 — // @<러너>-environment node
```

이 지정 없이는 DB 드라이버 연결이 실패한다.

**Given-When-Then 패턴**

```js
// 예(프로젝트별): 노드 환경 지정 주석
import { describe, it, expect, beforeEach, afterEach } from '<프로젝트 테스트 러너>';
import { findProfileByNo } from '<데이터 접근 레이어 모듈>';
import { beginIsolatedFixture } from '<테스트 DB fixture 모듈>';

describe('findProfileByNo', () => {
  let fixture;

  beforeEach(async () => {
    fixture = await beginIsolatedFixture();
  });

  afterEach(async () => {
    await fixture.rollbackOrCleanup();
  });

  it('존재하는 번호로 조회하면 정보를 반환한다', async () => {
    // Given: 격리 test DB에 이 테스트가 생성한 고유 데이터가 존재함
    const no = await fixture.insertProfile({ id: fixture.uniqueId() });

    // When
    const result = await findProfileByNo(no);

    // Then
    expect(result).not.toBeNull();
    expect(result).toHaveProperty('no', no);
  });

  it('존재하지 않는 번호로 조회하면 null을 반환한다', async () => {
    // Given
    const no = fixture.uniqueMissingId();

    // When
    const result = await findProfileByNo(no);

    // Then
    expect(result).toBeNull();
  });
});
```

**커버리지 기준**

| 케이스 | 필수 |
|---|---|
| 정상 입력 → 기대 결과 | 필수 |
| 경계값 (없는 ID, 빈 결과) | 필수 |
| 잘못된 입력 (타입 오류, 범위 초과) | 필수 |

### 3단계: Red 확인 (필수)

```bash
<프로젝트 테스트 명령> {테스트 파일 경로}
```

결과에 따라 분기:

| 결과 | 처리 |
|---|---|
| **assertion 실패(`red-confirmed`)** | 미구현·잘못된 동작 때문에 기대값이 실패했음을 확인하고 출력 증거를 반환 |
| **환경·수집·구문·연결 실패(`red-blocked`)** | 유효 Red가 아님. 차단 원인과 해소 조건을 반환하고 Green 구현 진입 금지 |
| **통과(Green)** | 구현이 이미 존재하거나 테스트가 잘못 작성된 것. `needs-input`으로 오케스트레이터에 보고 |

`red-confirmed` 확인 없이 Green 구현을 요청하지 않는다. 테스트 파일 로드 실패, 모듈 미존재로 인한 수집 실패, DB 미연결, 자격증명 누락, timeout은 assertion Red로 계산하지 않는다.

**격리 test DB 미연결 시**: 테스트 파일 작성까지만 수행하고 `Red 상태: red-blocked`, `결과: blocked`로 명시한다.

## DB 픽스처 정책

| 테스트 유형 | 전략 |
|---|---|
| SELECT (읽기 전용) | 격리 test DB에 테스트가 고유 데이터를 생성하고 해당 값만 조회 |
| INSERT/UPDATE/DELETE | 같은 연결의 transaction fixture 후 rollback, 불가하면 고유 실행 ID 기반 정밀 cleanup |

공유 dev DB의 기존 행, 고정 ID, 다른 실행이 만든 데이터를 전제로 테스트하지 않는다. 운영 DB는 절대 사용하지 않는다. transaction fixture는 애플리케이션 호출과 같은 연결·transaction context를 사용할 때만 선택하고, 그렇지 않으면 프로젝트 전용 test schema/DB와 실행별 고유 ID를 사용한다. cleanup은 자신이 만든 정확한 ID만 대상으로 하고 완료 후 잔존 데이터 0건을 확인한다.

**격리 픽스처 패턴**

```js
let fixture;

beforeEach(async () => {
  fixture = await beginIsolatedFixture({ runId: crypto.randomUUID() });
  await fixture.insertProfile({ id: fixture.uniqueId(), nickname: '테스트사용자' });
});

afterEach(async () => {
  await fixture.rollbackOrCleanup();
  await fixture.assertNoResidue();
});
```

## 반환 계약

공통 키는 `orchestrate/references/agent-contract.md`를 사용한다. 역할별로 `Red 상태`, `테스트 파일`, `격리 방식`, `cleanup 검증`, `Red 확인`을 추가하고 `에이전트: data-layer`로 반환한다.

`red-confirmed`이면 `completed`, 이미 Green이어서 테스트 계약 확인이 필요하면 `needs-input`, 환경 문제인 `red-blocked`는 `blocked`, 테스트 작성·실행 자체가 복구 불가능하게 실패하면 `failed`다.

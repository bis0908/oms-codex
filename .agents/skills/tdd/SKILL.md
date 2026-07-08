---
name: tdd
description: 데이터/백엔드 레이어 TDD 전담 스킬. 데이터 접근 레이어·API 엔드포인트·서비스 모듈 구현 전 실패 테스트(Red)를 작성하고 실패 확인까지 수행한다. tdd-agent가 사용한다.
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
import { describe, it, expect, beforeAll, afterAll } from '<프로젝트 테스트 러너>';
import { findProfileByNo } from '<데이터 접근 레이어 모듈>';
import { query } from '<DB 헬퍼 모듈>';

describe('findProfileByNo', () => {
  afterAll(async () => {
    await query("DELETE FROM <테스트 대상 테이블> WHERE id LIKE 'TEST_%'");
  });

  it('존재하는 번호로 조회하면 정보를 반환한다', async () => {
    // Given: dev DB에 데이터가 존재함
    const no = 1;

    // When
    const result = await findProfileByNo(no);

    // Then
    expect(result).not.toBeNull();
    expect(result).toHaveProperty('no', no);
  });

  it('존재하지 않는 번호로 조회하면 null을 반환한다', async () => {
    // Given
    const no = 99999999;

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
| **실패(Red)** | 정상 — 실패 출력을 반환 메시지에 포함 |
| **통과(Green)** | 비정상 — 구현이 이미 존재하거나 테스트가 잘못 작성된 것. 오케스트레이터에 보고 |

Red 확인 없이 반환하지 않는다.

**dev DB 미연결 시**: 테스트 파일 작성까지만 수행하고 "DB 미연결 — Red 실행 보류"로 명시한다.

## DB 픽스처 정책

| 테스트 유형 | 전략 |
|---|---|
| SELECT (읽기 전용) | dev DB 기존 데이터 사용, cleanup 불필요 |
| INSERT/UPDATE/DELETE | `TEST_` prefix 데이터 + `afterAll` cleanup |

**INSERT 픽스처 패턴**

```js
let testNo;

beforeAll(async () => {
  const result = await query(
    "INSERT INTO <테스트 대상 테이블> (id, nickname, active_status, reg_date) VALUES (?, ?, 'ACTIVE', NOW())",
    ['TEST_fixture_001', '테스트유저']
  );
  testNo = result.insertId;
});

afterAll(async () => {
  await query("DELETE FROM <테스트 대상 테이블> WHERE id LIKE 'TEST_%'");
});
```

## 반환 메시지 형식

```
완료 항목:
- <작성한 테스트 파일 경로>

Red 확인:
> <프로젝트 테스트 명령> <테스트 파일 경로>
  FAIL  <테스트 파일 경로>
    findProfileByNo
      ✗ 존재하는 번호로 조회하면 정보를 반환한다
        Error: Cannot find module '<구현 대상 모듈>'

마일스톤: M{N}
단계: phase-2.5-tdd
에이전트: tdd-agent
미완료 항목:
- 없음
확인 필요:
- 없음
다음 단계:
- 구현 에이전트 Green 구현
```

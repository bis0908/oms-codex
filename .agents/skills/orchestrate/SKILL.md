---
name: orchestrate
description: 마일스톤 구현, 업데이트, 보완, 리팩토링, 버그 수정, 계획 감사, compound 정리, 세션 인계를 에이전트 팀으로 조율한다. 구현·검증·보안·학습·추적의 상태 전이와 필수 게이트를 소유한다.
---

# Orchestrate

## 역할과 정본

오케스트레이터는 라우팅, 작업 상태, 게이트 순서, 완료 전이를 단독 소유한다. 하위 에이전트는 부모의 task 상태나 다른 에이전트를 직접 변경하지 않고 구조화된 결과만 반환한다.

| 영역 | 기본 역할 |
|---|---|
| 프론트 구현 | `page-builder` |
| 데이터·서비스·API 구현 | `data-layer` |
| 일반 코드·스크립트·인프라·결정 문서 | 프로젝트 override, 없으면 오케스트레이터 직접 수행 |
| Red 테스트 | `tdd-agent` |
| 시각 검수 | `design-reviewer` |
| 기술 QA | `qa-guard` |
| 심층 보안 | `security-auditor` |
| 요구사항 평가 | `evaluator` |
| 진행 추적 | `milestone-tracker` |
| 반복 학습 | `compound-learner` |
| 누적 학습 정리 | `compound-curator` |

일반 작업을 `data-layer`에 임의 배정하지 않는다. 프로젝트 `AGENTS.md`가 구현 역할 override를 선언하면 그 이름을 우선한다.

## 필수 참조

작업 유형에 맞는 파일만 읽는다.

- 모든 에이전트 호출: [agent-contract.md](references/agent-contract.md)
- 마일스톤·버그·리팩토링 게이트: [pipeline-gates.md](references/pipeline-gates.md)
- 실패·재시도·비동기 작업·커밋: [durable-work.md](references/durable-work.md)
- 입력 분기 상세와 compound 건강 질의: [input-branch-paths.md](references/input-branch-paths.md)
- stuck 임계와 안정 키: [error-handling.md](references/error-handling.md)
- 회귀 드라이런: [test-scenarios.md](references/test-scenarios.md)

## 모델 정책

모델·effort 정본은 `init-project/references/agent-profiles.json`이다. 프로필은 호출 수, 역할, 게이트 순서를 바꾸지 않고 agent TOML의 `model`, `model_reasoning_effort`만 결정한다.

1. 프로젝트 `AGENTS.md`에 유효한 `에이전트 실행 프로필`이 있으면 그 profile ID를 사용한다.
2. 기록이 없지만 init-project를 아직 적용하지 않은 프로젝트에서는 플러그인 기본값 `performance`를 사용한다.
3. 기록값이 유효하지 않거나 대상 agent TOML이 기록된 프로필과 다르면 호출을 시작하지 않고 `needs-input`으로 반환한다. `init-project`로 프로필을 확정·검증한 뒤 다시 시작한다.

프로필 구분은 다음과 같다.

| profile ID | 모델 배정 원칙 |
|---|---|
| `performance` | 직접 구현·전문 검수에는 Sol을 선택적으로 사용하고, 문서·상태 작업에는 Terra 또는 Luna를 사용한다. |
| `economy` | `data-layer`, `evaluator`, `security-auditor`만 Sol을 유지한다. `page-builder`와 일반 구현·검수는 Terra를 사용한다. |
| `low-cost` | 필수 역할은 Terra/xhigh, 단순 상태·세션 작업은 Luna/medium을 사용한다. |

## Phase 0: 입력과 상태 확인

1. 사용자 요청을 다음 중 하나로 분류한다.
   - 마일스톤·기능 구현
   - 버그 증상
   - 리팩토링
   - 계획 정합성 감사
   - compound 학습 정리·건강 질의
   - 세션 기록·재개 프롬프트
2. 작업 트리와 진행 정본을 읽는다. 기존 사용자 변경을 되돌리지 않는다.
3. `docs/compound/harness/README.md`가 있으면 라우팅·게이트 판단 전에 읽는다. 없으면 건너뛴다.
4. 대상 compound 카테고리가 있으면 해당 `README.md`와 load-when에 맞는 사례만 작업 봉투에 포함한다.
5. `_workspace`의 pending·inflight 상태를 확인하고, 중단된 작업은 [durable-work.md](references/durable-work.md)에 따라 복구한다.

다음 중 하나면 구현을 시작하지 않는다.

- `목표`, `범위`, `완료 기준`을 채울 정본이 없다.
- 요청 범위와 기존 변경이 충돌해 안전한 분리가 불가능하다.
- 필수 MCP·도구가 없고 대체 경로도 허용되지 않는다.

## 입력 분기

### 버그 증상

일반 Phase 1~5 대신 [pipeline-gates.md](references/pipeline-gates.md)의 버그 경로를 실행한다.

- `bug-fixer`는 항상 오케스트레이터가 호출하고 공통 반환 계약을 사용한다.
- 클릭, 상태 전환, 조건부 렌더, 데이터 표시, API 호출처럼 기능형 증상이면 경로 prefix와 무관하게 evaluator를 실행한다.
- 순수 시각형 증상이며 변경 파일이 프로젝트의 시각 전용 manifest에 모두 포함될 때만 evaluator를 스킵하고 사용자 시각 검증으로 대체한다.
- 새 쿠키·토큰·인증 분기를 설계해야 하면 단발 버그 경로를 종료하고 정규 TDD·구현·Phase 4로 합류한다. auth/session은 security-auditor 필수다.

### 리팩토링

`refactor-specialist -> qa-guard -> evaluator(공개 계약 변화 가능성이 있을 때)` 순서로 실행한다. 기준선 테스트가 없거나 동작 보존을 확인할 수 없으면 완료하지 않고 `blocked`로 반환한다.

### 계획 감사

`plan-auditor`를 읽기 전용으로 호출한다. 정본 수정은 결과를 확인한 뒤 `milestone-tracker`에 명시적 task/checklist ID와 함께 위임한다.

### Compound 정리

append 학습은 `compound-learner`, 무손실 정리는 `compound-curator`만 수행한다. 온디맨드 정리는 동기 실행한다. 백그라운드 정리는 성공 acknowledgement 전까지 pending 항목을 삭제하지 않는다.

### 세션 기록과 재개

기록 보존은 `session-archivist`를 호출한다. 재개 프롬프트는 사용자가 명시적으로 요청했거나 완료·blocked 상태에서 실제 인계가 필요할 때만 출력한다.

## Phase 1: 범위 확정

1. 마일스톤 티켓, 원본 스펙, API·디자인 문서를 읽는다.
2. 산출물을 원자 task로 분해하고 오케스트레이터 내부 상태에 `task_id`를 생성한다.
3. 각 task에 담당 역할, 대상 파일, 완료 기준, 위험 클래스를 연결한다.
4. 원본 대비 제외 항목은 가시적 before/after 차이와 승인 출처를 기록한다.
5. 일반 코드·문서·인프라 task에 프로젝트 override가 없으면 오케스트레이터가 직접 수행한다.

하위 에이전트가 부모 task 저장소를 갱신하도록 지시하지 않는다. 하위 에이전트는 `완료 task_id`를 반환하고, 오케스트레이터가 파일 실존·diff를 확인한 뒤 상태를 갱신한다.

## Phase 2: TDD

데이터 접근·서비스·API 구현이 있으면 `tdd-agent`를 먼저 호출한다.

- `red-confirmed`: 목표 assertion이 구현 부재로 실패한 증거가 있을 때만 Green 구현으로 진행한다.
- `red-blocked`: 환경·DB·도구 오류이면 구현을 시작하지 않는다. 사용자가 명시적으로 진행을 승인하면 검증 부채에 기록하고 최소 구현만 진행할 수 있다.
- 공유 dev DB 기존 데이터를 fixture로 사용하지 않는다. 격리 test DB, transaction rollback, 고유 fixture 중 프로젝트가 지원하는 안전한 방식을 사용한다.

결정 문서·목업·프론트 전용 작업은 TDD를 건너뛰고 사유를 기록한다.

## Phase 3: 구현

1. [agent-contract.md](references/agent-contract.md)의 봉투를 담당 에이전트에 전달한다.
2. API 의존이 없으면 frontend와 backend를 병렬 실행할 수 있다.
3. API 의존이 있으면 data-layer 완료와 계약 확인 후 page-builder를 실행한다.
4. 반환된 `완료 task_id`마다 대상 파일 실존, diff, 검증 증거를 확인한다.
5. 확인된 task만 오케스트레이터가 completed로 갱신한다.
6. 누락 task는 해당 agent에 1회 재요청하고, 재실패하면 필수 구현 실패로 `blocked` 처리한다.

구현 결과를 `milestone-tracker`에 전달할 때는 파일명 추측을 요구하지 않는다. `task_id`, `checklist_id`, 파일 경로를 함께 전달한다.

## Phase 4: 검증

정규 순서는 변경하지 않는다.

```text
design-reviewer(UI일 때)
  -> qa-guard
  -> security-auditor(고위험일 때)
  -> evaluator
```

각 호출에는 직전 산출물의 정확한 경로와 `request_id`를 전달한다. `latest glob`으로 다른 scope 보고서를 선택하지 않는다.

### Design

- 프론트 구현이 있으면 실행한다.
- 자동 수정 파일도 이후 QA와 evaluator 범위에 포함한다.
- 필수 런타임 항목을 확인하지 못하면 `blocked` 또는 `needs-input`이며 approved로 취급하지 않는다.

### QA

- 구현 파일과 TDD 테스트를 대상으로 실행한다.
- 실행 명령, exit code, 결과 분류가 없는 보고서는 형식 재전송을 요구한다.
- `검증불가`는 통과가 아니다. 필수 항목이면 파이프라인을 중단한다.

### Security

프로젝트 `AGENTS.md`의 보안 path/keyword manifest로 판정한다. manifest가 없으면 API route, server action, auth/session/permission/admin/payment/webhook/upload/delete, 개인정보 read/write를 보수적으로 감사한다.

auth/session 신규 설계는 항상 실행한다. `inconclusive`는 approved가 아니며 evaluator로 진행하지 않는다.

### Evaluator

구현 파일과 이번 request에 연결된 design, QA, security 보고서 경로를 정확히 전달한다.

- blocking `△`, `✗`, `⚠`, `?`가 하나라도 있으면 `수정필요` 또는 `blocked`다.
- 승인된 `◐ 의도적 제외`만 blocking이 아니며 최종 사용자 보고에 다시 노출한다.
- UI 범위는 브라우저 스모크 증거가 필요하다. 도구 부재로 필수 동작을 확인하지 못하면 approved가 아니다.

### 보완 재게이팅

보완 파일은 변경 종류에 맞춰 design -> QA -> security -> evaluator 순서로 재진입한다. 기능형 프론트 버그는 경로 prefix가 시각 경로여도 evaluator를 생략하지 않는다. 같은 결함의 반복과 상한은 [error-handling.md](references/error-handling.md)를 따른다.

필수 design, QA, security, evaluator가 1회 재시도 후에도 실행 실패하면 fail-closed로 `blocked` 처리한다. 결과 없이 다음 단계로 진행하지 않는다.

## Phase 5: 완료

### 검증 부채

미실행 테스트, 환경 차단, 사용자 승인 예외, 외부 의존, 도구 부재를 수집한다. 부채는 숨기지 않고 tracker 작업 로그와 사용자 보고에 기록한다. 필수 게이트 미실행은 부채 기록만으로 완료할 수 없다.

### UI 마일스톤

1. evaluator approved 후 구현 파일, 검증 결과, 의도적 제외, 부채, URL과 재현 시나리오를 사용자에게 제시한다.
2. 사용자 긍정 응답을 기다린다.
3. `milestone-tracker`에 `작업 유형: UI`, `사용자 검증: 통과`, evaluator 원본 승인 신호, task/checklist ID를 전달한다.
4. tracker가 위 필드 중 하나라도 거부하면 완료하지 않는다.

### 비-UI 마일스톤

마이그레이션·스키마·백필이면 dev/test 적용 증거, rollback·backup 근거를 확인한다. 증거가 없으면 사용자에게 적용 또는 미적용 커밋을 확인하고, 미적용 승인은 검증 부채로 기록한다.

`milestone-tracker`에는 `작업 유형: non-UI`, evaluator 원본 승인 신호, task/checklist ID를 전달한다.

### 커밋

프로젝트 정책은 `auto | ask | disabled` 중 하나다. 미정의 기본값은 `ask`다.

- `auto`: `commit-local` capability가 있고 범위·검증이 확정된 경우만 커밋한다.
- `ask`: 사용자 승인을 받은 뒤 커밋한다.
- `disabled`: 커밋하지 않고 변경 상태를 보고한다.
- capability가 없으면 자동 커밋을 시도하지 않고 설치·수동 경로를 보고한다.

### 학습 드레인

커밋 정책 처리 후 pending curate 항목이 있으면 `compound-curator`를 호출한다. 성공 결과를 받은 항목만 pending에서 제거한다. 실패·중단 항목은 다음 세션 재시도를 위해 유지한다.

## 완료 보고

- 완료·미완료 task
- design, QA, security, evaluator 결과와 정확한 보고서 경로
- 의도적 제외와 검증 부채
- tracker 상태 전이
- 커밋 정책과 실행 결과
- pending 학습 작업

다음 작업 제안은 필요할 때만 작성한다. 재개 프롬프트는 명시적 인계 요청, 안전 중단, 장기 작업 완료 때만 동반한다.

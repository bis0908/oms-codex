---
name: orchestrate
description: 마일스톤 구현, 업데이트, 보완, 버그 수정, 리팩터링, 계획 감사, 학습 정리, 세션 인계를 작업 규모와 위험에 맞는 lean 또는 full 게이트로 조율한다.
---

# Orchestrate

## 역할과 정본

오케스트레이터는 라우팅, 작업 상태, 게이트 순서, 완료 전이를 소유한다. 역할 경계는 다음과 같다.

| 영역 | 실행 주체 |
|---|---|
| 프론트 구현 | `page-builder` |
| 데이터·서비스·API 구현과 Red→Green | `data-layer` + `tdd` 스킬 |
| 일반 코드·문서·인프라 | 프로젝트 override, 없으면 오케스트레이터 |
| 단발 버그 | 오케스트레이터 + `bugfix` 스킬 |
| 리팩터링 | 오케스트레이터 + `refactor` 스킬 |
| 시각 검수 | `design-reviewer`(UI·레퍼런스가 있을 때) |
| 기술 QA | `qa-guard` |
| 심층 보안 | `security-auditor`(고위험일 때) |
| 요구사항 평가 | `evaluator`(행동·마일스톤 완료 판정일 때) |
| 계획 감사 | `plan-auditor`(설치됨) 또는 오케스트레이터 + `plan-audit` |
| 진행 추적 | 오케스트레이터 + `milestone-track` + 결정적 전이 검증기 |
| 세션 기록 | 오케스트레이터 + `session-archive` |
| 반복 학습 | 설치된 `compound-learner`(코퍼스가 있을 때) |
| 누적 정리 | 설치된 `compound-curator`(코퍼스가 있을 때) |

하위 agent는 부모 task나 다른 agent를 수정하지 않고 구조화된 결과만 반환한다. 일반 작업을 `data-layer`에 임의 배정하지 않는다.

## 필수 참조

작업 유형에 필요한 파일만 읽는다.

- agent 호출: [agent-contract.md](references/agent-contract.md)
- 게이트 선택: [pipeline-gates.md](references/pipeline-gates.md)
- 실패·재시도·커밋: [durable-work.md](references/durable-work.md)
- UI 검증 수단: [ui-verification-fallback.md](references/ui-verification-fallback.md)
- 계획 감사·compound 질의: [input-branch-paths.md](references/input-branch-paths.md)
- stuck 기준: [error-handling.md](references/error-handling.md)
- 회귀 시나리오: [test-scenarios.md](references/test-scenarios.md)

## 모델과 topology 정책

모델·effort 정본은 `init-project/references/agent-profiles.json`, 설치·라우팅 정본은 `init-project/references/topology-profiles.json`이다. 두 축을 독립 선택한다.

- `lean`: core 6개만 기본 설치하고 계획 감사와 compound 역할은 요청·코퍼스가 있을 때 추가한다.
- `full`: 9개 agent를 설치하되 모든 agent를 매 작업마다 호출하지는 않는다.
- 모델 프로필은 `balanced | performance | economy | low-cost`다.
- 모델·effort 변경은 호출 수나 게이트를 자동 결정하지 않는다. 작업 규모, 변경 의미, 위험 클래스와 검증 가능성이 게이트를 결정한다.
- `medium`을 기본 기준선으로 삼고 대표 작업 평가에서 이점이 확인될 때 `high`·`xhigh`를 사용한다. `max`는 최난도 품질 우선 평가에서만 비교하며 기본값으로 사용하지 않는다.

기록된 model profile 또는 topology가 설치 상태와 불일치하면 agent 호출을 시작하지 않고 `needs-input`으로 반환한 뒤 `init-project`로 복구한다.

## Phase 0: 입력과 상태

1. 요청을 구현, 버그, 리팩터링, 계획 감사, compound, 세션 기록 중 하나로 분류한다.
2. 목표, 범위, 완료 기준과 작업 트리를 확인한다. 기존 사용자 변경을 되돌리지 않는다.
3. `docs/compound/harness/README.md`가 있으면 라우팅 전에 읽고, 없으면 건너뛴다.
4. `_workspace` pending·inflight 상태는 durable-work 정책으로 복구한다.
5. 사용 가능한 topology와 실제 설치 agent를 확인한다.

다음이면 구현하지 않는다.

- 목표·범위·완료 기준을 채울 근거가 없다.
- 기존 변경과 안전하게 분리할 수 없다.
- 필수 MCP·도구가 없고 허용된 대체 경로도 없다.

## 빠른 분기

### 버그

오케스트레이터가 `bugfix` 스킬로 재현·원인·최소 수정·회귀 검증을 한 컨텍스트에서 수행한다.

- 클릭, 상태, 조건부 렌더, 데이터, API, 라우팅 증상은 evaluator 대상이다.
- 순수 시각 증상이고 변경 파일이 시각 전용 manifest에 모두 포함될 때만 evaluator를 사용자 시각 검증으로 대체할 수 있다.
- 새 auth/session 설계가 필요하면 단발 버그 경로를 종료하고 데이터 계층 Red→Green과 full-risk 게이트로 합류한다.

### 리팩터링

오케스트레이터가 `refactor` 스킬을 사용한다. 변경 전후 동일 테스트와 공개 계약 diff가 없으면 완료하지 않는다. 관찰 가능한 동작 변화가 필요하면 버그 또는 구현으로 재분류한다.

### 계획 감사

설치된 plan-auditor를 읽기 전용으로 호출하거나 같은 스킬을 오케스트레이터가 직접 수행한다. 정본 수정은 사용자 승인 후 `milestone-track` 스킬과 `scripts/validate-milestone-transition.py`를 통과한 정확한 ID에만 적용한다.

### Compound

코퍼스가 없으면 agent나 빈 카테고리를 선생성하지 않는다. append는 compound-learner, curate는 compound-curator만 수행하며 둘의 쓰기 권한을 합치지 않는다.

### 세션 기록

오케스트레이터가 `session-archive` 스킬을 직접 사용한다. 재개 프롬프트는 사용자 요청 또는 실제 장기 인계가 있을 때만 출력한다.

## Phase 1: 범위와 게이트 선택

1. 스펙과 대상 파일을 읽고 원자 task와 task/checklist ID를 만든다.
2. 각 task에 담당 주체, 완료 기준, 위험 클래스를 연결한다.
3. [pipeline-gates.md](references/pipeline-gates.md)의 `direct | lean | full` 중 하나를 선택하고 이유를 기록한다.
4. 원본 대비 제외는 before/after와 승인 출처를 기록한다.

하위 agent가 상태 문서를 갱신하게 하지 않는다. 오케스트레이터가 파일·diff·증거를 확인한 뒤에만 task를 완료로 전이한다.

## Phase 2: 구현

### 데이터·서비스·API

data-layer가 `tdd` 스킬을 사용해 같은 컨텍스트에서 Red→Green을 수행한다.

- `red-confirmed`: 목표 assertion이 구현 부재로 예상 위치에서 실패한 경우만 Green 진행.
- `red-blocked`: 환경·DB·fixture·권한 오류. 구현을 시작하지 않는다.
- 기존 dev DB 데이터나 운영 DB를 fixture로 사용하지 않는다.

### 프론트와 일반 작업

- API 의존이 없으면 page-builder와 data-layer를 병렬 실행할 수 있다.
- API 의존이 있으면 계약 확인 뒤 page-builder를 실행한다.
- 일반 코드·문서·인프라는 프로젝트 override가 없으면 오케스트레이터가 직접 수행한다.

반환된 task마다 파일 실존, diff, 검증 증거를 확인한다. 누락은 같은 입력으로 1회 재요청하고 재실패하면 필수 구현 실패로 `blocked` 처리한다.

## Phase 3: 검증

선택한 gate profile에 필요한 agent만 호출한다. 정확한 대상 파일과 같은 request_id를 전달한다.

- `direct`: 정형 문서·상태·세션 작업. 결정적 스크립트와 diff 검토만 수행한다.
- `lean`: 격리된 저위험 변경. qa-guard를 기본으로 하고, 사용자 행동·공개 계약·완료 기준 판정이 있으면 evaluator를 추가한다.
- `full`: 마일스톤, UI, 다중 모듈, auth/session, migration, payment, destructive 작업. design(UI) → QA → security(고위험) → evaluator 순서다.

UI를 검증하는 작업 봉투에는 UI 검증 모드, 선호 수단, 대체 허용, URL, viewport, 시나리오를 포함한다. 특정 도구 부재만으로 감사를 중단하지 않되 필수 증거가 없으면 approved를 금지한다.

호출한 필수 design, QA, security, evaluator가 1회 재시도 후에도 실행 실패하면 fail-closed로 `blocked` 처리한다. 결과 없이 다음 게이트·완료·커밋으로 진행하지 않는다.

보완 파일은 변경 의미에 맞는 상류 게이트부터 다시 검증한다. 같은 결함의 반복과 상한은 error-handling을 따른다.

## Phase 4: 완료와 상태 기록

1. 필수 게이트의 approved와 미검증 부채를 확인한다.
2. UI 마일스톤은 evaluator 승인 뒤 URL·시나리오를 사용자에게 제시하고 `사용자 검증: 통과`를 받는다.
3. `milestone-track` 형식의 전이 요청 JSON을 만들고 `scripts/validate-milestone-transition.py` exit 0을 확인한다.
4. 정확한 task/checklist ID만 진행 문서에 적용하고 diff를 재검토한다.
5. 마이그레이션은 dev/test 적용, rollback·backup 근거를 확인한다.

필수 미검증은 부채 기록만으로 완료할 수 없다.

## 커밋과 학습

커밋 정책은 `auto | ask | disabled`, 미정의 기본값은 `ask`다.

- `auto`: `commit-local` capability, 범위, 검증이 모두 확인된 경우만 커밋한다.
- `ask`: 사용자 승인 뒤 커밋한다.
- `disabled`: 커밋하지 않는다.

코퍼스와 선택 agent가 모두 있을 때만 pending compound 작업을 처리한다. 성공 acknowledgement를 받은 ID만 done으로 전이한다.

## 완료 보고

- 완료·미완료 task
- 선택한 topology와 gate profile
- 실행한 design, QA, security, evaluator 결과와 보고서
- 의도적 제외와 검증 부채
- 상태 전이 검증 결과
- 커밋 정책과 실행 결과
- pending 학습 작업

다음 작업 제안과 재개 프롬프트는 필요할 때만 작성한다.

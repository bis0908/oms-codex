# 하네스 에이전트 지침 감사 보고서

## 1. 감사 개요

- 감사 일자: 2026-07-10 KST
- 감사 범위: 감사 당시 `.codex/agents/*.toml` 13개, 각 에이전트가 참조하는 핵심 skill, `orchestrate` 실행 계약과 검증 스크립트
- 감사 기준: 역할 경계, 입력 잠금, 반환 계약, 실패 시 안전성, 상태 소유권, 검증 게이트, 학습 데이터 보존, 모델·effort 적합성
- 제외 범위: 이번 감사에서는 에이전트·skill 지침을 직접 수정하지 않았다.

## 2. 결론

현재 하네스는 구현, 검증, 보안, 학습, 추적, 기록 역할이 잘 분리되어 있다. 각 agent TOML이 세부 절차의 정본을 skill로 지정하고, 검증 산출물을 `_workspace`에 외부화하며, 모델과 effort를 역할별로 배치한 구조도 유지할 가치가 있다.

다만 현재 상태를 그대로 운영하면 다음 문제가 실제 오동작으로 이어질 수 있다.

1. 필수 검증 에이전트가 재실패해도 계속 진행할 수 있는 fail-open 규칙이 있다.
2. 신규 인증·세션 설계 예외 경로에서 `security-auditor`가 누락되고 검증 순서가 정규 경로와 다르다.
3. UI 마일스톤의 사용자 검증 통과 조건을 milestone-tracker가 직접 검증하지 않는다.
4. TDD가 기존 dev DB 데이터에 의존하여 비결정적이며, 쓰기 테스트의 격리가 약하다.
5. security 반복 실패를 `qa-repeat`으로 전달하지만 compound 입력 계약은 security 보고서를 처리하지 않는다.
6. 비동기 학습 작업이 성공하기 전에 대기 파일을 비워 학습 요청을 잃을 수 있다.

따라서 모델을 상향하기 전에 P0 계약 결함부터 수정해야 한다. 현재 문제의 대부분은 추론 능력 부족이 아니라 입력·상태·실패 계약의 불일치다.

## 3. 우선순위 기준

| 등급 | 의미 | 처리 기준 |
|---|---|---|
| P0 | 거짓 완료, 보안 게이트 우회, 데이터 오염·학습 요청 유실 가능 | 다음 기능 확장 전에 수정 |
| P1 | 반복 실행 시 drift, 잘못된 상태 갱신, 이식성·복구성 저하 | P0 직후 계약 정비 |
| P2 | 프롬프트 비용, 유지보수성, 표현 명확성 문제 | 구조 정리 단계에서 개선 |

## 4. 공통 핵심 발견

### 4.1 P0 발견

| ID | 발견 | 근거 | 영향 | 권고 |
|---|---|---|---|---|
| P0-01 | 필수 게이트도 에이전트 재실패 후 결과 없이 진행할 수 있다. | `.agents/skills/orchestrate/references/error-handling.md:5`, `.agents/skills/orchestrate/SKILL.md:566` | design, QA, security, evaluator 결과가 없는 상태로 완료 경로에 진입할 수 있다. | 구현·필수 검증 게이트는 fail-closed로 분리한다. compound, archive 같은 보조 작업만 실패를 기록하고 계속 진행한다. |
| P0-02 | 신규 인증·세션 설계 예외가 보안 검증을 우회한다. | `.agents/skills/orchestrate/SKILL.md:138`은 `evaluator -> qa-guard -> design-reviewer` 순서이며 security가 없다. 정규 순서는 같은 파일 `416-456`의 `design -> qa -> security -> evaluator`다. | 신규 쿠키·토큰·인증 분기가 심층 보안 감사 없이 통과할 수 있다. | 예외 경로를 별도 순서로 복제하지 말고 Phase 4 정규 게이트로 합류시킨다. 인증·세션은 security 필수 조건으로 고정한다. |
| P0-03 | UI 완료 불변식이 오케스트레이터에만 있고 tracker에는 없다. | `orchestrate/SKILL.md:518`은 `사용자 검증: 통과`를 전달하지만 `milestone-track/SKILL.md:204-225`와 `milestone-tracker.toml:33-45`는 evaluator 승인만 확인한다. | tracker를 직접 호출하거나 신호가 축약되면 사용자 검증 없이 UI 마일스톤이 완료될 수 있다. | tracker 입력에 작업 유형(`UI` 또는 `non-UI`)과 `사용자 검증`을 추가하고, UI는 통과 값 없이는 완료를 거부한다. |
| P0-04 | TDD의 Red 상태와 DB 격리 규칙이 충돌한다. | `tdd-agent.toml:37`은 Red 없이 반환 금지, `79`는 DB 미연결 시 Red 보류 반환을 허용한다. `45-47`은 실 dev DB와 기존 데이터를 사용한다. | 환경 오류를 유효한 Red로 오인하거나 공유 dev 데이터 때문에 테스트가 비결정적으로 통과·실패할 수 있다. | `red-confirmed`와 `red-blocked`를 분리한다. assertion 실패만 Red로 인정하고, 격리 test DB·transaction fixture·고유 데이터 생성 및 cleanup 검증을 기본으로 한다. |
| P0-05 | security 반복 학습 채널의 입력 enum과 보고서 형식이 맞지 않는다. | `orchestrate/SKILL.md:452`는 security 반복을 `qa-repeat`과 `_workspace/security_*`로 호출한다. `compound/SKILL.md:37-46,103`은 `qa-repeat`에서 `_workspace/qa_*`만 읽는다. | 반복 보안 결함이 매핑 불가로 버려지거나 QA 카테고리에 잘못 기록될 수 있다. | `security-repeat` 트리거와 `docs/compound/security/` 매핑을 명시적으로 추가하고 verifier와 시나리오에 포함한다. |
| P0-06 | 비동기 학습 요청을 성공 확인 전에 제거한다. | `orchestrate/SKILL.md:523`은 compound-curate 호출 직후 `curate-needed.md`를 truncate한다. 같은 파일 `134`도 bugfix 시도 이력을 호출 직후 비운다. | 백그라운드 호출 실패·중단 시 처리 대상을 복구할 수 없다. | `pending -> inflight -> done` 상태 파일 또는 항목별 acknowledgement를 사용한다. 성공 반환 후에만 해당 항목을 제거한다. |
| P0-07 | bug-fixer의 협업·반환 계약이 오케스트레이터 사용 방식과 다르다. | `bug-fixer.toml:45-46`은 오케스트레이터 미경유·사용자 직접 보고를 규정한다. `orchestrate/SKILL.md:107-134`는 bug-fixer 반환을 파싱해 evaluator, commit, compound 게이트를 수행한다. | `완료 항목`, 재발 조건, 검증 증거가 누락되면 후속 게이트가 불안정해진다. | 직접 호출과 오케스트레이션 호출을 같은 표준 반환 계약으로 통일하고 `재현 확인`, `재발 조건`, `검증`, `미검증 항목`을 필수화한다. |

### 4.2 P1/P2 발견

| ID | 우선순위 | 발견 | 권고 |
|---|---|---|---|
| C-01 | P1 | 오케스트레이터의 필수 봉투는 목표·범위·완료 기준 3개지만 page-builder와 data-layer는 제외·참조·task_id까지 필수로 해석한다. | 공통 스키마를 하나로 만들고 선택 필드는 `없음`을 유효값으로 정의한다. |
| C-02 | P1 | 하위 구현 agent가 부모의 `현재 세션 작업 목록`을 직접 갱신하도록 요구한다. 공유 task API가 없으면 수행할 수 없는 책임이다. | 하위 agent는 `완료 task_id`를 반환하고, task 상태 갱신은 오케스트레이터만 수행한다. |
| C-03 | P1 | milestone-tracker가 파일 경로를 체크리스트 항목에 의미적으로 매핑한다. | `task_id -> 파일 -> 체크리스트 항목 ID`를 오케스트레이터가 명시해 전달하고 tracker는 ID만 적용한다. |
| C-04 | P1 | `commit` skill을 사용하지만 플러그인에는 해당 skill이 포함되지 않았고 외부 설치 전제도 선언되지 않았다. 자동 커밋 정책도 프로젝트별 선택 지점이 없다. | init-project preflight에서 실제 commit capability를 확인하고, 프로젝트 정책을 `auto`, `ask`, `disabled` 중 하나로 선언한다. |
| C-05 | P1 | QA와 security 결과가 이진 상태라 환경 문제로 일부 미검증인 상태를 정확히 표현하지 못한다. evaluator의 `?`가 승인에 미치는 영향도 명시적이지 않다. | `completed`, `needs-input`, `blocked`, `failed` 공통 상태와 `검증 수준`, `미검증 항목`을 도입한다. 필수 미검증은 승인 불가로 계산한다. |
| C-06 | P1 | 공통 표준 반환 형식이 있지만 bug-fixer, refactor-specialist, milestone-tracker 등 일부 TOML은 키를 누락하거나 다른 이름을 사용한다. | 공통 envelope와 역할별 extension을 분리하고 verifier가 필수 키를 검사하도록 한다. |
| C-07 | P1 | compound의 “2-write 원자성”은 복구·직렬화 절차 없이 선언만 되어 있다. | 임시 파일 작성, 양쪽 검증, 교체, 실패 시 복구 순서를 정의하고 동일 카테고리 동시 쓰기를 직렬화한다. |
| C-08 | P1 | evaluator 승인·미승인 반환에서 보고서 경로가 필수 키가 아니며 `? 확인 필요` 규칙이 TOML 내부에서도 다르게 표현된다. | 승인 계산식을 한 곳에 정의하고 모든 결과에 `보고서`, 평가 등급 수, blocking 항목을 포함한다. |
| C-09 | P1 | refactor-specialist는 넓은 “사용하지 않는 코드 제거”를 허용하지만 증거 기준과 변경 전 기준선 테스트가 없다. | 요청 범위 안의 도달 불가 증거가 있는 코드만 제거하고, 변경 전후 동일 테스트·공개 계약 diff를 필수화한다. |
| C-10 | P2 | `orchestrate/SKILL.md`가 593줄, 약 75KB이며 라우팅·상태·검증·커밋·학습·인계를 함께 소유한다. | 핫패스와 불변식만 본문에 남기고, 입력 분기·게이트·완료·복구 절차를 조건부 reference로 분리한다. |
| C-11 | P2 | “다음 단계”를 언급하는 거의 모든 응답에 재개 프롬프트를 강제한다. | 완료·중단·명시적 인계 요청에만 생성하여 일반 보고의 노이즈를 줄인다. |
| C-12 | P2 | verifier는 TOML 구문과 모델·effort는 강제하지만 역할-스킬 참조, 반환 키, phase/발신자 조합 같은 의미 계약은 검사하지 않는다. | 정적 contract verifier와 부정 시나리오 테스트를 추가한다. |
| C-13 | P1 | 버그 경로 evaluator 스킵이 경로 prefix만 사용한다. 일반 컴포넌트 안의 클릭·상태·조건부 렌더 버그도 스타일 변경으로 오인될 수 있다. | 사용자 증상이 기능형이면 evaluator를 실행한다. 시각형 증상이며 변경 확장자·허용 경로가 모두 시각 전용일 때만 스킵한다. |
| C-14 | P1 | security 게이트가 “기계 판정”을 선언하지만 `personal data read/write`, `high-risk operation` 같은 의미 조건을 사용한다. | 프로젝트별 path/keyword manifest를 정본으로 두고, 미정의 프로젝트에서는 API/server action을 보수적으로 감사한다. |
| C-15 | P1 | 기본 구현 역할이 page-builder와 data-layer뿐이라 결정 문서·일반 스크립트·인프라 작업의 소유자가 없다. 기존 시나리오는 결정 문서를 data-layer에 배정한다. | 범용 code/docs 역할을 추가하거나 프로젝트 override를 필수화한다. 역할 미매칭 시 자동 배정하지 않고 확인한다. |
| C-16 | P1 | evaluator가 QA·security 보고서를 참조해야 하지만 호출 봉투에는 정확한 보고서 경로가 없다. 최신 glob은 다른 scope 산출물을 선택할 수 있다. | design, QA, security 보고서의 정확한 경로와 호출 ID를 evaluator 입력에 전달한다. |
| C-17 | P2 | `test-scenarios.md` 일부가 제거된 레거시 분석 전용 agent를 아직 호출하며, 인증 예외·필수 게이트 실패 같은 부정 경로가 없다. | 현재 라우팅에 맞춰 갱신하고 P0/P1 회귀 시나리오를 추가한다. |

## 5. 에이전트별 평가

| 에이전트 | 현재 강점 | 주요 개선점 | 우선순위 |
|---|---|---|---|
| `bug-fixer` | 사용자 신고 버그와 구조 개선의 경계, 최소 수정 원칙이 명확하다. | 직접 호출/오케스트레이션 호출을 통합하고, 임의의 “3개 파일 초과” 대신 공개 계약·데이터·보안 영향으로 확인 게이트를 정한다. 반환에 재발 조건과 검증 증거를 추가한다. | P0 |
| `compound-learner` | append-only 학습과 무손실 curate를 분리하고 쓰기 경계를 제한한다. | `security-repeat`을 추가한다. “스킬을 수정하지 않고”를 “학습 문서를 갱신하지 않고”로 고치고, 2-write 복구와 동시 실행 직렬화를 정의한다. 다문서 재구성인 curate는 별도 역할 또는 일회성 Sol/high 실행을 검토한다. | P0 |
| `data-layer` | 기존 DB/ORM 감지, 운영 DB 금지, handler/service/data access 책임 분리가 좋다. | `참조: 없음`을 허용하고 완료 task_id, 테스트 명령·exit code, migration 롤백·백업 근거를 반환한다. | P1 |
| `design-reviewer` | QA/evaluator와 시각적 의미 검증의 경계가 선명하며 자동 수정 범위가 제한되어 있다. | 보고서 반복 헤더를 명시적 계약으로 올리고, 런타임 미확인 항목의 승인 가능 여부와 자동 수정 파일의 후속 검증 경로를 고정한다. | P1 |
| `evaluator` | 스펙·원본·구현 3자 대조와 연결 단절 검증이 강하다. | `?`와 승인 계산식을 단일 정의로 만들고, 승인/미승인 모두 보고서 경로와 blocking 항목을 반환한다. | P1 |
| `milestone-tracker` | 골격/작업 로그 2계층과 evaluator 승인 전 완료 금지가 좋다. | UI 사용자 검증을 독립적으로 강제하고, 파일명 추측 대신 task/checklist ID를 사용하며, 허용 phase/발신자 조합을 고정한다. | P0 |
| `page-builder` | 기존 프레임워크·디자인 시스템 우선, API 계약 부족 시 중단 경계가 좋다. | 조건부 참조를 유효 입력으로 만들고, 완료 task_id, 연결 지점, 빌드·렌더·상호작용 검증과 미검증 항목을 반환한다. | P1 |
| `plan-auditor` | 수평 계획 감사와 milestone-tracker 단일 쓰기 소유권이 명확하다. | `전체` 감사의 반환값을 `ALL/N/A`로 지원하고 30% 에스컬레이션의 분모를 정의한다. 명시적 보류 근거가 있을 때만 todo 미반영을 결함 아님으로 처리한다. | P2 |
| `qa-guard` | 빠른 정적 보안, 컨벤션, 테스트와 심층 보안의 역할 경계가 좋다. | 수정 요청 경로를 오케스트레이터로 통일하고 `검증불가` 상태, 실행 명령·exit code, 검증 부채를 구조화한다. | P1 |
| `refactor-specialist` | 기능·API·DB·UI 의미 변경 금지가 분명하다. | 중단 기준을 관찰 가능한 동작·공개 계약 변화로 구체화하고, 기준선 테스트와 공통 반환 키를 추가한다. | P1 |
| `security-auditor` | 스펙 외 위협 모델과 evaluator의 스펙 권한 검증을 잘 분리한다. | `inconclusive` 상태, 비파괴 검증, 심각도·공격 가능성·잔여 위험을 정의하고 security 반복 학습과 연결한다. | P0 |
| `session-archivist` | progress 읽기 전용, history/handoff 쓰기 전용 경계가 명확하다. | 민감정보 발견 시 원문 기록 금지·마스킹·중단 규칙과 `NN` 파일명 충돌 재계산을 명시한다. | P1 |
| `tdd-agent` | Red-before-Green, Given-When-Then, 환경 실패 구분의 방향은 좋다. | 유효 Red와 환경 차단을 분리하고, 공유 dev 데이터 대신 격리 DB/transaction fixture와 cleanup 검증을 사용한다. | P0 |

## 6. 권장 공통 계약

에이전트별 TOML에는 역할과 extension만 두고, 다음 공통 envelope를 단일 정본으로 관리하는 방식을 권장한다.

```text
입력:
  request_id
  milestone
  goal
  scope
  exclusions: []
  references: []
  acceptance_criteria: []
  task_ids: []
  risk_class: none | ui | data | auth | payment | migration | destructive

출력:
  result: completed | needs-input | blocked | failed
  completed_task_ids: []
  changed_or_reviewed_files: []
  artifacts: []
  verification:
    - command
      exit_code
      classification: pass | assertion-red | environment-blocked | fail
  unverified_items: []
  questions: []
  next_step
  agent
  phase
```

역할별 필드는 extension으로 추가한다. 예를 들어 evaluator는 `evaluation_result`, security-auditor는 `security_result`, milestone-tracker는 `state_transition`을 추가한다. 공통 키 이름을 바꾸지 않는다.

## 7. 모델·effort 평가

현재 모델·effort 배치는 유지해도 된다.

| 역할군 | 현재 설정 | 판단 |
|---|---|---|
| evaluator, security-auditor | `gpt-5.6-sol` / `xhigh` | 고위험 최종 판단에 적합하다. |
| 구현·설계 검수·계획 감사·리팩터·TDD·버그 수정 | `gpt-5.6-sol` / `high` | 복합 코드 탐색과 수정에 적합하다. |
| qa-guard | `gpt-5.6-terra` / `high` | 반복 검증의 비용·품질 균형이 적절하다. |
| compound-learner | `gpt-5.6-terra` / `medium` | append-only 학습에는 충분하다. 다문서 무손실 재구성인 `compound-curate`는 별도 curator 또는 일회성 `gpt-5.6-sol` / `high` 후보이다. |
| milestone-tracker, session-archivist | `gpt-5.6-luna` / `medium` | 명시적 ID와 상태 전이 계약을 전제로 적절하다. |

milestone-tracker의 파일명 추측 문제를 해결하기 위해 모델을 Terra/Sol로 올리는 것은 권장하지 않는다. task/checklist ID를 명시하면 Luna/medium으로도 결정적 처리가 가능하다. 다만 계약 정비 전까지 실제 상태 오기록이 관찰되면 Terra/medium을 임시 진단 수단으로 사용할 수 있다.

## 8. 적용 순서

### 단계 A: 안전성 복구

1. 필수 게이트 fail-closed와 인증·세션 정규 보안 경로를 확정한다.
2. tracker의 UI 사용자 검증 불변식을 추가한다.
3. TDD를 격리 test DB 또는 transaction fixture로 전환한다.
4. `security-repeat`과 durable queue acknowledgement를 추가한다.

### 단계 B: 계약 통일

1. 공통 입력·출력 envelope를 정의한다.
2. task 상태 소유권을 오케스트레이터로 이동한다.
3. 모든 agent TOML과 skill 반환 형식을 공통 계약에 맞춘다.
4. commit capability와 자동 커밋 정책을 preflight에 추가한다.

### 단계 C: 유지보수성 개선

1. `orchestrate/SKILL.md`를 조건부 reference 구조로 분리한다.
2. 의미 계약 verifier와 부정 시나리오를 추가한다.
3. 중복 절차를 agent TOML에서 제거하고 skill 정본 링크만 유지한다.

## 9. 권장 검증 시나리오

| 시나리오 | 기대 결과 |
|---|---|
| QA 에이전트가 2회 연속 실행 실패 | 마일스톤 완료 중단, 사용자에게 blocked 보고 |
| 신규 쿠키·토큰 발급 함수가 포함된 버그 수정 | TDD/구현 후 design(해당 시) -> QA -> security -> evaluator 순서 실행 |
| UI evaluator approved, 사용자 검증 필드 누락 | tracker가 완료 전이를 거부 |
| DB 미연결 상태에서 TDD 실행 | `red-blocked`, 구현 Green 단계 진입 금지 또는 명시적 사용자 승인 |
| security 동일 위험 2회 반복 | `security-repeat`으로 security category에 사례 기록 |
| background compound 작업 실패 | pending 항목 유지, 다음 세션에서 재시도 가능 |
| 구현 agent가 파일은 만들었지만 task_id를 반환하지 않음 | tracker 갱신 금지, 계약 재전송 요구 |
| commit capability 미설치 | 자동 커밋 생략 또는 사용자 확인, 완료 사실과 커밋 상태 분리 보고 |
| 일반 컴포넌트 내부 클릭 핸들러 버그 | 경로 prefix와 무관하게 기능형 증상으로 분류하여 evaluator 실행 |
| 결정 문서 작업인데 구현 역할 override 없음 | data-layer로 자동 배정하지 않고 역할 확인 요청 |
| 이전 scope의 QA 보고서가 `_workspace`에 존재 | evaluator가 호출 ID에 연결된 정확한 보고서 경로만 참조 |

## 10. 감사 제한

- 이번 감사는 정적 지침 대조다. 실제 Codex custom agent 런타임에서 13개 역할을 end-to-end로 호출하는 실행 검증은 수행하지 않았다.
- 기존 `test-scenarios.md`는 정상 흐름을 설명하지만 계약 위반을 자동 실패시키는 테스트는 아니다.
- 앞선 모델 정책 변경과 `.codex-plugin/plugin.json`의 기존 수정은 이번 감사에서 변경하지 않았다.

## 11. 적용 결과

2026-07-10 KST에 사용자 승인으로 전체 개선안을 적용했다.

| 범위 | 적용 결과 |
|---|---|
| P0-01~P0-07 | 필수 게이트 fail-closed, auth/session 정규 보안 경로, UI 최종 전이, TDD 격리, security 학습, durable acknowledgement, bug-fixer 공통 계약 적용 |
| C-01~C-09 | 공통 입력·반환 계약, parent-owned task 상태, checklist ID, commit 정책, 다중 결과 상태, compound 원자성, evaluator 보고서 연결, refactor 기준선 적용 |
| C-10~C-12 | `orchestrate/SKILL.md`를 500줄 미만으로 축소하고 reference 분리, 재개 프롬프트 조건부화, 의미 계약 verifier 추가 |
| C-13~C-17 | 기능형 프론트 버그 평가, 보안 manifest, 일반 작업 라우팅, 정확한 report ID, 최신 시나리오 적용 |
| 역할 분리 | `compound-curator`(`gpt-5.6-sol` / `high`) 추가. 총 14개 custom agent, 13개 공유 skill 구성 |
| 회귀 검증 | 정상 `POS-01`~`POS-08`, 부정 `NEG-01`~`NEG-14`, PowerShell/Bash 공통 의미 계약 검사 추가 |

적용 후 정적 검증은 통과했다. 실제 대상 프로젝트에서 14개 agent를 순차 호출하는 end-to-end 런타임 검증은 별도 통합 테스트로 남는다.

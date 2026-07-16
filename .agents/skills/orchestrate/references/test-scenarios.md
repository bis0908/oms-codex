# 오케스트레이션 회귀 시나리오

> **언제 읽는가**: 하네스의 라우팅, 게이트, 상태 전이, 비동기 복구 계약을 드라이런할 때만 읽는다. 실제 실행 절차의 정본은 `agent-contract.md`, `pipeline-gates.md`, `durable-work.md`, `error-handling.md`다.

## 판정 규칙

- 각 시나리오는 Given-When-Then 순서로 판정한다.
- `Then`의 필수 게이트나 거부 조건이 하나라도 지켜지지 않으면 회귀다.
- 보고서는 `latest glob`이 아니라 같은 `request_id`에 연결된 정확한 경로를 사용한다.
- 필수 구현·검증 실패는 `blocked`, 보조 작업 실패는 pending 유지 후 보고가 기본이다.

## 정상 시나리오

| ID | Given | When | Then |
|---|---|---|---|
| POS-01 | UI task의 목표, 범위, 완료 기준, task/checklist ID가 있고 프론트 구현 역할이 배정됐다. 선호 UI 도구는 사용 가능하거나 폴백이 허용됐다. | `page-builder`가 구현을 완료하거나 audit 요청이 시작된다. | 선호 도구가 없으면 한 번의 가용성 확인 후 E2E → 컴포넌트 런타임 → HTTP·정적 추적 → 사용자 관찰 순으로 전환하고 `design-reviewer -> qa-guard -> security-auditor(고위험일 때) -> evaluator` 진단을 계속한다. 등가 증거가 없는 항목은 `?`로 남기며, evaluator approved와 사용자 검증 통과 전에는 tracker 완료 전이와 커밋을 하지 않는다. |
| POS-02 | 데이터·API task에 격리 test DB 또는 transaction fixture가 준비됐다. | `tdd-agent`가 목표 assertion 실패를 확인한다. | `Red 상태: red-confirmed`를 받은 뒤에만 `data-layer`가 Green 구현을 시작하고, `qa-guard -> security-auditor(고위험일 때) -> evaluator`를 통과한 뒤 non-UI 완료 전이를 요청한다. |
| POS-03 | 버그 해결에 새 쿠키, 토큰, 세션 또는 인증 메커니즘 설계가 필요하다. | `bug-fixer` 진단 결과가 auth/session 신규 설계로 분류된다. | 단발 버그 경로를 종료하고 정규 TDD·구현 경로로 합류한다. 검증 순서는 `qa-guard -> security-auditor(필수) -> evaluator`이며 security를 생략하지 않는다. |
| POS-04 | 증상이 색상·간격·타이포 같은 순수 시각 결함이고 모든 수정 파일이 시각 전용 manifest에 포함된다. | `bug-fixer`가 최소 수정과 검증 증거를 반환한다. | evaluator를 스킵할 수 있지만 사용자 시각 검증 통과 전에는 수정 확정, 학습 acknowledgement, 완료 전이를 하지 않는다. 클릭·상태·조건부 렌더가 섞이면 이 시나리오가 아니라 기능형 evaluator 경로를 사용한다. |
| POS-05 | 반복 결함 보고서에 원인, 수정 파일, 재발 조건과 안정적인 request/queue ID가 있다. | append 학습 또는 누적 정리를 실행한다. | append는 `compound-learner`, `compound-curate`는 `compound-curator`만 수행한다. 호출자는 `completed`와 대상 ID의 성공 acknowledgement를 모두 확인한 항목만 pending에서 제거한다. |
| POS-06 | 계획 감사 결과에 문서 수정 항목이 있고 사용자가 정본 수정을 승인했다. | `plan-auditor` 결과를 오케스트레이터가 tracker에 전달한다. | plan-auditor는 읽기 전용을 유지하고, 오케스트레이터가 명시적 task/checklist ID와 허용 phase로 `milestone-tracker`에 정본 수정을 요청한다. |
| POS-07 | 프로젝트 커밋 정책이 `ask`이고 모든 필수 게이트와 tracker 완료 전이가 끝났다. | 사용자 검증은 통과했지만 커밋 승인은 아직 없다. | 완료 상태와 미커밋 상태를 분리해 보고한다. 별도 커밋 승인을 받은 뒤에만 `commit-local` capability와 범위 한정 staging을 확인해 커밋한다. |
| POS-08 | 번들에 custom agent TOML 14개와 공유 skill 13개가 있고 사용자 홈에는 별도 agent가 있을 수 있다. | 설치 스크립트를 symlink 또는 copy 방식으로 실행한다. | source의 14개 agent를 모두 설치하고 각 source-target 대응을 확인한다. 사용자 홈 전체 파일 수를 14로 강제하거나 별도 agent를 삭제하지 않는다. |

## 부정 시나리오

| ID | Given | When | Then |
|---|---|---|---|
| NEG-01 | 필수 `qa-guard` 호출이 실패했다. | 1회 재시도도 실패한다. | `blocked`로 중단하고 evaluator, tracker 완료 전이, 커밋을 실행하지 않는다. "QA 결과 없이 진행"은 금지한다. |
| NEG-02 | 버그 수정 중 신규 쿠키·토큰·세션·인증 분기가 추가된다. | 단발 버그 예외 경로가 선택된다. | 정규 경로로 재분류하고 `qa-guard -> security-auditor -> evaluator`를 실행한다. security 누락 또는 evaluator 선실행은 실패다. |
| NEG-03 | UI evaluator 결과는 approved지만 `사용자 검증` 필드가 누락, 실패 또는 N/A다. | `milestone-tracker`가 `phase-5-complete` 전이를 받는다. | 상태 파일을 변경하지 않고 `needs-input`으로 거부한다. UI에서 `사용자 검증: 통과`와 근거가 있어야만 완료할 수 있다. |
| NEG-04 | DB 연결, module load, 권한, timeout 또는 fixture setup이 실패했다. | `tdd-agent`가 테스트 실패를 분류한다. | `Red 상태: red-blocked`와 `environment-blocked`를 반환하고 Green 구현을 시작하지 않는다. 사용자 승인 예외로 진행하면 검증 부채를 기록하며 이를 `red-confirmed`로 바꾸지 않는다. |
| NEG-05 | 같은 security fingerprint가 2회 연속 반복됐다. | 반복 학습을 발행한다. | 정확한 `_workspace/security_*` 보고서 경로와 `security-repeat` 트리거를 `compound-learner`에 전달하고 `docs/compound/security/`에 기록한다. `qa-repeat`이나 QA 보고서로 대체하지 않는다. |
| NEG-06 | pending 항목이 inflight로 이동한 뒤 `compound-curator`가 실패, timeout 또는 중단됐다. | 큐 복구를 수행한다. | 같은 ID와 payload를 pending으로 되돌리고 실패 사유를 보존한다. 파일 전체 truncate나 호출 직후 삭제를 하지 않는다. |
| NEG-07 | agent 반환에 공통 키, `완료 task_id` 또는 입력과 같은 `request_id`가 빠졌다. | 오케스트레이터가 반환 계약을 검사한다. | 형식 재전송을 1회 요구하고, 계약이 복구되기 전 task 완료·다음 게이트·tracker 갱신을 금지한다. |
| NEG-08 | `qa-guard`가 `phase-4-eval`을 발신하거나 evaluator가 `phase-3-impl`을 발신하는 등 phase/발신자 조합이 허용표와 다르다. | `milestone-tracker`가 신호를 받는다. | `needs-input`으로 거부하고 상태 파일을 변경하지 않는다. agent 이름이나 파일명으로 의도를 추측하지 않는다. |
| NEG-09 | 커밋 정책이 `auto`지만 `commit-local` capability가 없거나, 정책이 `ask`인데 승인이 없거나, 정책이 `disabled`다. | 완료 보고 단계에 진입한다. | 커밋을 실행하지 않고 정책, capability, 미커밋 상태를 보고한다. 사용자 config를 수정하거나 다른 커밋 수단으로 우회하지 않는다. |
| NEG-10 | `_workspace`에 이전 scope의 최신 QA/security 보고서와 현재 request의 보고서가 함께 있다. | evaluator 입력을 구성한다. | 같은 `request_id`로 전달받은 정확한 design/QA/security 보고서 경로만 사용한다. mtime 또는 glob 최신값으로 선택하지 않는다. |
| NEG-11 | 일반 component 파일 안의 클릭, 상태 전환, 조건부 렌더 또는 데이터 표시 버그다. | 수정 경로가 동작 레이어 prefix와 매칭되지 않는다. | 기능형 증상을 우선하여 evaluator를 실행한다. component/style 경로라는 이유만으로 순수 시각 스킵을 적용하지 않는다. |
| NEG-12 | 결정 문서, 일반 스크립트 또는 인프라 task에 프로젝트 구현 override가 없다. | 역할을 자동 선택한다. | `data-layer`에 임의 배정하지 않는다. 오케스트레이터가 직접 수행하거나 역할 확인을 요청한다. |
| NEG-13 | curator가 `completed`를 반환했지만 acknowledgement의 대상 ID가 inflight ID와 다르거나 ID가 없다. | 큐 항목 제거를 시도한다. | pending/inflight 항목을 유지하고 계약 재전송을 요구한다. 결과 상태만으로 항목을 삭제하지 않는다. |
| NEG-14 | security 결과가 `inconclusive`이거나 evaluator에 blocking `△`, `✗`, `⚠`, `?`가 남았다. | 다음 게이트 또는 완료 전이를 요청한다. | 감사 모드에서는 남은 진단 게이트와 보고서 작성만 계속할 수 있다. approved, tracker 완료 전이, 커밋은 금지하고 `blocked`, `needs-input` 또는 `수정필요`로 판정한다. 검증 부채 기록만으로 필수 미검증을 통과시키지 않는다. |

## 정적 검증 포인트

- verifier는 정상 시나리오 8개와 부정 시나리오 14개의 연속 ID가 각각 정확히 한 번 존재하는지 확인한다.
- 모델 정책은 `agent-profiles.json`의 네 profile ID를 모두 검증하고, 기본 source agent TOML이 `balanced` 프로필과 일치함을 포함한다.
- agent 수 14와 skill 수 13을 별도로 검사한다. `compound-learner`와 `compound-curator`는 `compound` skill을 공유한다.
- POS-01은 선호 UI 도구 실패가 감사 중단이 아니라 폴백 전환으로 이어지는지,
  NEG-14는 폴백이 완료 승인 우회로 사용되지 않는지 함께 검증한다.

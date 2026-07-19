# 적응형 파이프라인 게이트

## 선택 원칙

게이트 수는 agent model profile이 아니라 변경 의미, 위험 클래스, 완료 판정의 종류로 선택한다.

| profile | 대상 | 필수 검증 |
|---|---|---|
| `direct` | 정형 상태·세션 기록, 행동을 바꾸지 않는 문서 | 결정적 스크립트 또는 파서 + diff 검토 |
| `lean` | 격리된 저위험 코드·설정 변경 | QA, 필요 시 evaluator |
| `full` | 마일스톤, UI, 다중 모듈, auth/session, migration, payment, destructive | design(UI) → QA → security(고위험) → evaluator |

`lean`에서 사용자 행동, 공개 계약, acceptance criteria 충족 판정이 필요하면 evaluator가 필수다. `auth | payment | migration | destructive` 위험 클래스는 항상 `full`이며 security를 생략하지 않는다.

최종 완료 전이에는 선택한 profile과 실제 필수 검증을 `gate_profile`, `required_gates`, `gate_results`, `risk_class`로 기록한다. `required_gates`는 비어 있을 수 없고 결과 키와 정확히 일치해야 한다. `direct`의 결정적 검증은 `deterministic`, UI `full`의 디자인 검증은 `design`으로 기록한다.

## 버그 경로

```text
orchestrator + bugfix skill
  -> 기능형: QA + evaluator
  -> 순수 시각형 + 시각 전용 manifest 전부 매칭: design 또는 사용자 시각 검증
  -> 신규 auth/session 설계: data-layer Red→Green + full gate
```

기능형 신호는 클릭, 제출, 상태 전환, 조건부 렌더, 데이터 표시, API·서버 동작, 라우팅이다. 파일 경로가 component/style이라는 이유로 스킵하지 않는다.

## 게이트 결과

각 호출의 공통 `결과: completed`와 역할별 `approved`를 모두 확인한다. `수정필요`, `needs-input`, `blocked`, `failed`, `검증불가`, `inconclusive`는 승인 상태가 아니다.

보완 파일은 변경 의미에 맞는 상류 게이트부터 다시 검증한다. design 자동 수정 파일도 QA와 evaluator 범위에 포함한다.

### 감사 모드 진단 연속성

`UI 검증 모드: audit`에서는 가용한 폴백 증거를 사용해 진단 보고서를 완성할 수 있다. 상류 게이트에 `수정필요`나 미확인이 남아도 다음 진단 게이트를 실행할 수 있지만, 구현 완료로 전이하지 않는다. evaluator approved, 상태 완료 전이, 커밋에는 이 예외를 적용하지 않는다.

## 보안 manifest

프로젝트 `AGENTS.md`의 보안 path/keyword manifest를 사용한다. manifest가 없으면 API route, server action, auth/session/permission/admin/payment/webhook/upload/delete와 개인정보 read/write를 보수적으로 security 대상으로 본다.

## 완료 전이

상태 전이 전에는 `scripts/validate-milestone-transition.py`로 신호를 검증한다.

UI 완료에는 `작업 유형: UI`, `사용자 검증: 통과`, design·evaluator approved, task/checklist ID가 모두 필요하다. non-UI 완료에는 선택한 `required_gates` 전부의 approved와 명시적 task/checklist ID가 필요하며, evaluator를 선택한 경우에만 evaluator 원본 승인 신호와 보고서를 요구한다.

계획 감사 보완은 `plan-remediation`, orchestrator 발신, 사용자 승인, 정확한 plan-auditor 보고서와 ID가 모두 있어야 한다. 이 조합은 계획 문구에만 적용하며 구현 완료를 합성하지 않는다.

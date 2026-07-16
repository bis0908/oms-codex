# 파이프라인 게이트

## 목차

1. 버그 경로
2. 정규 검증
3. 보안 manifest
4. 완료 전이

## 1. 버그 경로

```text
bug-fixer
  -> 기능형: evaluator
  -> 순수 시각형 + 시각 전용 manifest 전부 매칭: 사용자 시각 검증
  -> 신규 auth/session 설계: 정규 TDD·구현·검증으로 전환
```

기능형 신호는 클릭, 제출, 상태 전환, 조건부 렌더, 데이터 표시, API·서버 동작, 라우팅이다. 하나라도 있으면 evaluator를 실행한다. 파일 경로가 component/style이라는 이유로 스킵하지 않는다.

시각형 스킵은 사용자 증상이 색상·간격·타이포·비기능 레이아웃이고 변경 파일 전부가 프로젝트의 시각 전용 manifest에 있을 때만 허용한다. manifest가 없으면 evaluator를 실행한다.

## 2. 정규 검증

```text
UI: design -> QA -> security(조건부) -> evaluator
non-UI: QA -> security(조건부) -> evaluator
auth/session: QA -> security(필수) -> evaluator
```

각 agent의 공통 `결과: completed`와 역할별 결과 `approved`를 모두 확인한 뒤에만 다음 게이트로 진행한다. QA·security·design이 `수정필요`이면 공통 결과가 completed여도 다음 게이트로 진행하지 않고 보완 루프로 되돌린다. `needs-input`, `blocked`, `failed`, `검증불가`, `inconclusive`도 승인 상태가 아니다.

보완으로 변경된 파일은 변경 종류에 맞는 상류 게이트부터 다시 실행한다. design 자동 수정 파일도 QA와 evaluator 입력에 합친다.

### 감사 모드 진단 연속성

`UI 검증 모드: audit`에서는 구현 완료가 아니라 전체 결함 분류가 목적이다.
선호 UI 도구가 없어도 [ui-verification-fallback.md](ui-verification-fallback.md)의
대체 증거를 사용한다. 상류 게이트가 `수정필요`이거나 폴백으로도 남은
미확인이 있더라도 보고서를 정확한 request ID로 연결해 QA, 조건부 security,
evaluator까지 진단 순서를 계속할 수 있다.

이 예외는 evaluator approved, tracker 완료 전이, 커밋에는 적용하지 않는다.
blocking 항목이나 미확인이 있으면 최종 결과는 `수정필요`이고 구현 완료로
전이하지 않는다.

## 3. 보안 Manifest

프로젝트 `AGENTS.md`에 아래 세트를 선언한다.

```text
보안 고위험 경로:
- <prefix>

보안 고위험 키워드:
- auth
- session
- permission
- admin
- payment
- webhook
- upload
- delete

시각 전용 경로:
- <prefix>
```

manifest가 없으면 모든 API route·server action과 개인정보 read/write를 security 대상으로 본다. auth/session 신규 메커니즘은 경로와 무관하게 필수다.

## 4. 완료 전이

UI 완료 신호:

```text
작업 유형: UI
사용자 검증: 통과
검증 결과: approved
task_id/checklist_id: <명시값>
```

non-UI 완료 신호:

```text
작업 유형: non-UI
검증 결과: approved
task_id/checklist_id: <명시값>
```

tracker는 phase·발신자·작업 유형 조합을 확인한다. UI에서 사용자 검증이 없거나 task/checklist ID가 모호하면 상태를 변경하지 않는다.

계획 감사 보완은 별도 조합을 사용한다.

```text
단계: plan-remediation
에이전트: orchestrator
사용자 승인: 통과
plan-auditor 보고서: <정확한 경로>
task_id/checklist_id: <명시값>
```

이 조합은 계획 문구·체크리스트 정합성 수정에만 사용하며 구현 완료나 evaluator 승인을 합성하지 않는다.

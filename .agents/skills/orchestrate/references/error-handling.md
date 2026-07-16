# 에러 핸들링

필수/보조 역할의 fail-closed·fail-open 구분과 pending 복구는 [durable-work.md](durable-work.md)를 따른다.

## 재시도

- 실행 실패: 동일 입력으로 1회 재시도
- 선호 UI 도구 가용성 실패: 같은 요청에서 재시도하지 않고 즉시 다음 폴백
  수단으로 전환한다. 이는 gate/agent 실행 실패 회차로 세지 않는다.
- 형식 계약 실패: 같은 보고서 파일명으로 1회 재전송
- 필수 역할 재실패: `blocked`, 다음 게이트 금지
- 보조 역할 재실패: pending 유지 또는 실패 기록 후 본 작업 보고

## Stuck 기준

| 경로 | 임계 |
|---|---|
| design, QA, security, evaluator 보완 | 동일 안정 키 3회 연속 또는 게이트 통산 7회 |
| Phase 3 task 완료 | 동일 task 2회 미완료 |
| 버그 evaluator | 동일 안정 키 2회 미해결 |

안정 키:

- design: 체크 ID
- QA: 체크 섹션 + 파일 경로
- security: CWE/위험 분류 + 자산/경로
- evaluator: acceptance criterion 또는 Given-When-Then ID
- task: task_id

라인 번호는 안정 키로 사용하지 않는다.

## 보고서 카운트

형식 재전송은 기존 파일을 덮어쓰고 회차에 포함하지 않는다. 증분 보고서는 `*_regate_*`, 버그 평가는 `eval_bugfix_*`, 리팩토링 QA는 `qa_refactor_*` 네임스페이스를 사용한다.

7회 상한에 도달하면 재검증을 호출하지 않고 `blocked`로 전환한다. 보류 항목이 있는 상태에서 evaluator approved를 합성하지 않는다.

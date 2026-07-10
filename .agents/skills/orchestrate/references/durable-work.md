# 내구성 작업 정책

## 필수 역할과 보조 역할

| 분류 | 역할 | 재실패 처리 |
|---|---|---|
| 필수 구현 | page-builder, data-layer, 프로젝트 구현 override | `blocked`, 다음 게이트 금지 |
| 필수 검증 | design(UI), QA, security(조건부), evaluator | `blocked`, 완료·커밋 금지 |
| 보조 | compound-learner, compound-curator, session-archivist | 실패 기록 후 본 작업 결과 보고 가능 |
| 상태 기록 | milestone-tracker | 완료 상태 전이 금지, 사용자에게 상태 미반영 보고 |

모든 실패는 1회만 재시도한다. 필수 역할은 결과 없이 계속 진행하지 않는다.

## Pending 작업

비동기 학습은 `_workspace/compound-queue.json` 한 파일에 다음 schema로 보존한다.

```json
{
  "version": 1,
  "items": [
    {
      "id": "<queue item ID>",
      "request_id": "<호출 ID>",
      "type": "compound-learn | compound-curate",
      "target": "<보고서 또는 유형 파일 경로>",
      "status": "pending | inflight | done",
      "attempts": 0,
      "updated_at": "YYYY-MM-DDTHH:mm:ss+09:00",
      "last_error": null
    }
  ]
}
```

상태 전이는 항목 하나의 `status`를 바꾸는 방식으로 수행한다. 같은 ID를 pending과 inflight에 중복 저장하지 않는다.

```text
pending -> inflight -> done
                  -> pending (실패·중단·timeout)
```

- 변경본을 같은 디렉터리의 임시 JSON에 작성·파싱한 뒤 원본 경로로 원자 교체한다.
- 큐 파일의 writer는 오케스트레이터 하나로 제한한다. worker는 큐를 직접 수정하지 않고 acknowledgement만 반환한다.
- 여러 acknowledgement가 도착하면 오케스트레이터가 queue 갱신을 직렬화한다. 각 갱신 직전에 원본을 다시 읽고 대상 ID와 현재 status를 확인한 뒤 임시 파일 작성·파싱·원자 교체를 한 트랜잭션처럼 수행한다.
- 단일 writer를 보장할 수 없는 실행 환경에서는 파일 lock 또는 compare-and-swap으로 같은 임계 구역을 보호한다. baseline이 달라졌으면 최신 원본을 다시 읽어 병합하며, stale snapshot으로 원본을 덮어쓰지 않는다.
- 실행 시작 시 해당 항목을 `pending -> inflight`로 바꾸고 request_id, attempts, updated_at을 함께 갱신한다.
- `결과: completed`, `acknowledgement: done`, 입력과 같은 `request_id`, `acknowledged ID == 요청한 pending ID 목록`이 모두 성립할 때만 목록에 포함된 pending 항목을 done으로 전이한다.
- 성공 acknowledgement 후 항목을 `done`으로 바꾸고, 다음 queue compaction에서만 제거한다.
- 실패·timeout이면 같은 항목을 `inflight -> pending`으로 되돌리고 `last_error`, updated_at을 기록한다.
- 프로세스 중단 후 timeout 기준을 넘긴 inflight 항목은 다음 세션에서 pending으로 복구한다. 아직 실행 중일 수 있는 항목은 중복 호출하지 않는다.
- 파일 전체 truncate를 acknowledgement 대신 사용하지 않는다.

`bugfix-attempts`도 compound 학습 성공 전에는 삭제하지 않는다. 다음 버그와 섞이지 않도록 request_id로 구분한다.

## 커밋 정책

프로젝트 `AGENTS.md`의 `커밋 정책: auto | ask | disabled`를 사용한다. 미정의는 `ask`다.

- `auto`라도 `commit-local` capability preflight, 검증 완료, 범위 한정 staging이 모두 필요하다.
- capability가 없으면 실패를 가장하지 않고 커밋하지 않는다.
- 보조 학습 실패는 검증된 구현 커밋을 막지 않지만 pending으로 남긴다.
- 설계 문서는 프로젝트 정책상 Git 업로드 금지 대상이면 staging에서 제외한다.

## 재개 프롬프트

다음 경우에만 생성한다.

- 사용자가 명시적으로 요청
- 필수 역할 blocked로 안전 중단
- 장기 마일스톤 완료 후 다음 세션 인계가 실질적으로 필요

일반적인 “다음 단계” 문장에는 자동으로 붙이지 않는다.

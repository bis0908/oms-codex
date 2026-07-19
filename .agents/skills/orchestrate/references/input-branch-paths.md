# 저빈도 입력 분기

## Compound curate

1. `docs/compound/`와 실제 사례 파일이 없으면 agent나 빈 파일을 만들지 않고 종료한다.
2. compound-curator가 설치된 경우에만 동기 호출한다.
3. 대상 카테고리·파일과 pending ID를 정확히 전달한다.
4. `completed`, `acknowledgement: done`, request/pending ID 일치를 모두 확인한 뒤 queue를 갱신한다.

append와 curate의 쓰기 권한은 합치지 않는다. 누적 정리는 evaluator 승인과 무관한 온디맨드 유지보수 작업이다.

## Compound 건강 질의

파일을 만들지 않고 채팅으로만 보고한다. `docs/compound/`가 없으면 "코퍼스 없음"으로 종료한다.

1. 유형 파일별 `재발(`과 `자매(` 고정 마커 수를 계산한다.
2. 전 카테고리의 `자매(...)` 줄을 한 번 재료화한다.
3. LLM이 활성 사례의 문맥을 읽어 교차 카테고리 후보를 판단한다. 기계 자동 군집이나 자동 엣지 생성은 하지 않는다.
4. 재발도·계보밀도와 교차 후보를 채팅 표로 반환한다.

## 계획 정합성 감사

1. 마일스톤 파이프라인에 진입하지 않는다.
2. plan-auditor가 설치돼 있으면 읽기 전용으로 호출하고, 없으면 오케스트레이터가 `plan-audit` 스킬을 직접 수행한다.
3. 결함 목록과 `결함 아님 | 문서 수정 | 재판단 필요` 분류를 사용자에게 보고한다.
4. 사용자가 수정을 승인하면 오케스트레이터가 `plan-remediation` 요청을 만들고 `scripts/validate-milestone-transition.py`를 통과시킨다.
5. 정확한 task/checklist ID에 해당하는 계획 문구만 `milestone-track` 스킬로 수정한다.

plan-auditor는 정본을 수정하지 않는다. 상태 문서의 단일 writer는 오케스트레이터다.

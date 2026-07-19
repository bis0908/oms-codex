# GPT-5.6 실행 정책

## 목적

OMS Codex의 model profile, reasoning effort, multi-agent topology 선택 기준을 정의한다. 정본은 다음과 같다.

- [GPT-5.6 모델 가이드](https://developers.openai.com/api/docs/guides/latest-model)
- [GPT-5.6 프롬프트 가이드](https://developers.openai.com/api/docs/guides/prompt-guidance-gpt-5p6)
- [Multi-agent 가이드](https://developers.openai.com/api/docs/guides/responses-multi-agent)
- model profile: `../.agents/skills/init-project/references/agent-profiles.json`
- topology profile: `../.agents/skills/init-project/references/topology-profiles.json`

## 기본 원칙

1. model profile과 topology를 독립 선택한다.
2. 목표, 제약, 완료 기준, 검증을 한 번씩만 명시한다.
3. 같은 model·effort에서 기준선을 만든 뒤 한 단계 낮은 effort를 대표 작업으로 비교한다.
4. `high`, `xhigh`, `max`는 측정된 품질 이점이 있을 때만 사용한다.
5. multi-agent는 독립적이고 경계가 명확한 작업에 사용한다.
6. 순차 의존, 공유 상태, 짧은 작업은 한 agent가 같은 컨텍스트에서 수행한다.

## Model 선택

| model | 기본 용도 | 선택 조건 |
|---|---|---|
| Luna | 대량·저지연 정형 작업 | 별도 agent보다 script/direct skill로 먼저 해결하며 현재 core에는 기본 배정하지 않음 |
| Terra | 규칙 기반 검수·저빈도 문서 대조 | Sol보다 총비용이 낮고 품질 기준을 통과한다는 회귀 근거가 있음 |
| Sol | 구현·복합 분석·고위험 판단 | 여러 파일·계약을 함께 다루거나 실패 비용이 큼 |

정형 상태 전이와 세션 기록은 Luna agent를 두지 않고 결정적 스크립트와 오케스트레이터 direct skill로 처리한다.

## Effort 선택

허용값은 `low`, `medium`, `high`, `xhigh`, `max`다.

```text
baseline = current_effort or medium
compare = [baseline, one_level_lower(baseline)]

if task is high-risk and eval shows material gain:
    consider high or xhigh

if task is hardest quality-first and xhigh is insufficient:
    compare max against xhigh

never select max globally
```

현재 profile은 검증 역할의 독립 반증 가치를 고려해 일부 `high/xhigh`를 보수적 출발점으로 유지한다. 이 배정은 영구 결론이 아니며 프로젝트별 평가 결과로 조정한다.

## Topology 선택

### Lean

기본 topology다. core agent 6개만 설치한다.

- `page-builder`
- `data-layer`
- `design-reviewer`
- `qa-guard`
- `security-auditor`
- `evaluator`

bugfix, refactor, TDD, milestone tracking, session archive는 별도 agent가 아니라 direct skill mode다.

### Full

lean core에 다음 선택 agent를 추가한다.

- `plan-auditor`
- `compound-learner`
- `compound-curator`

full 설치는 모든 agent의 매 작업 호출을 뜻하지 않는다. 계획 감사 요청 또는 실제 compound 코퍼스가 있을 때만 선택 agent를 호출한다.

## Gate 선택

| gate | 대상 | 검증 |
|---|---|---|
| direct | 정형 문서·상태·세션 | parser/script + diff |
| lean | 격리된 저위험 코드 | QA, 행동·계약 판정이면 evaluator 추가 |
| full | UI 마일스톤·다중 모듈·고위험 | design → QA → security(조건부) → evaluator |

Multi-agent는 다음 조건에서만 사용한다.

```text
if tasks are independent and bounded and do not share mutable state:
    parallelize
else:
    keep one agent and one context
```

따라서 data-layer는 TDD Red와 Green 구현을 같은 컨텍스트에서 수행한다. evaluator와 security-auditor는 구현자와 다른 관점의 독립 반증이므로 유지한다.

## 평가 지표

- 첫 시도 성공률
- 필수 검증 통과율
- 뒤늦게 발견된 결함 수
- 재시도 횟수
- 입력·출력 토큰, 지연, 비용
- 사람이 수정한 범위와 복구 비용

model, effort, prompt, topology를 동시에 바꾸지 않는다. 한 축을 변경한 뒤 같은 대표 작업을 재실행한다.

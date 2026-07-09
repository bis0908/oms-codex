# 로컬 하네스 설치 참조

이 문서는 `init-project`가 대상 프로젝트에 oms-codex 하네스를 설치·갱신할 때만 읽는다. 설치는 대상 프로젝트 루트에서만 수행한다.

## 원본과 대상

- 원본 agent: 현재 oms-codex 플러그인 번들의 `.codex/agents/*.toml`
- 원본 skill: 현재 oms-codex 플러그인 번들의 `.agents/skills/<skill>/`
- 대상 agent: 대상 프로젝트의 `.codex/agents/*.toml`
- 대상 skill: 대상 프로젝트의 `.agents/skills/<skill>/`

현재 경로가 oms-codex 플러그인 저장소 또는 플러그인 캐시 내부이면 설치하지 않는다. 대상 프로젝트 경로를 요청한다.

## 필수 설치 대상

| 구분 | 논리 이름 | 원본 | 대상 |
|---|---|---|---|
| agent | page-builder | `.codex/agents/page-builder.toml` | `.codex/agents/page-builder.toml` |
| agent | data-layer | `.codex/agents/data-layer.toml` | `.codex/agents/data-layer.toml` |
| agent | evaluator | `.codex/agents/evaluator.toml` | `.codex/agents/evaluator.toml` |
| agent | qa-guard | `.codex/agents/qa-guard.toml` | `.codex/agents/qa-guard.toml` |
| agent | milestone-tracker | `.codex/agents/milestone-tracker.toml` | `.codex/agents/milestone-tracker.toml` |
| agent | plan-auditor | `.codex/agents/plan-auditor.toml` | `.codex/agents/plan-auditor.toml` |
| agent | compound-learner | `.codex/agents/compound-learner.toml` | `.codex/agents/compound-learner.toml` |
| skill | init-project | `.agents/skills/init-project/` | `.agents/skills/init-project/` |
| skill | orchestrate | `.agents/skills/orchestrate/` | `.agents/skills/orchestrate/` |
| skill | evaluate | `.agents/skills/evaluate/` | `.agents/skills/evaluate/` |
| skill | qa | `.agents/skills/qa/` | `.agents/skills/qa/` |
| skill | milestone-track | `.agents/skills/milestone-track/` | `.agents/skills/milestone-track/` |
| skill | plan-audit | `.agents/skills/plan-audit/` | `.agents/skills/plan-audit/` |
| skill | compound | `.agents/skills/compound/` | `.agents/skills/compound/` |

## 선택 설치 대상

아래 항목은 원본이 실제로 존재할 때만 설치한다.

| 논리 이름 | 실제 agent 원본 | 관련 skill 원본 |
|---|---|---|
| design-reviewer | `.codex/agents/design-reviewer.toml` | `.agents/skills/design-review/` |
| security-auditor | `.codex/agents/security-auditor.toml` | `.agents/skills/security-audit/` |
| tdd-agent | `.codex/agents/tdd-agent.toml` | `.agents/skills/tdd/` |
| bugfix-agent | `.codex/agents/bug-fixer.toml` | `.agents/skills/bugfix/` |
| refactor-agent | `.codex/agents/refactor-specialist.toml` | `.agents/skills/refactor/` |

`bugfix-agent`와 `refactor-agent`는 라우팅 논리 이름이다. 실제 번들 파일명은 각각 `bug-fixer.toml`, `refactor-specialist.toml`이다. 실제 원본 파일명이 없으면 새 이름으로 파일을 만들지 말고 `원본 부재`로 보고한다.

## 설치 상태 판정

각 항목은 아래 상태 중 하나로 기록한다.

- `설치됨`: 대상이 없어서 원본을 복사했거나, 대상이 원본과 동일하다.
- `갱신됨`: 대상이 oms-codex 관리본임이 명확하고 사용자 변경 가능성이 없어 원본 변경을 반영했다.
- `원본 부재`: 플러그인 번들에 원본 파일이나 디렉터리가 없다.
- `확인 필요`: 대상에 프로젝트별 변경 가능성이 있어 자동 병합하지 않았다.
- `충돌 보류`: 대상과 원본이 다르고 안전한 병합 기준이 없다.

기존 대상 파일이나 디렉터리가 있으면 먼저 읽고 비교한다. 내용이 다르면 임의 overwrite하지 않는다. TOML과 skill 디렉터리는 구조가 민감하므로 자동 병합은 관리 흔적과 무변경 근거가 명확할 때만 허용한다.

## 프로젝트별 최적화

최적화는 기본적으로 agent TOML을 수정하지 않고 `AGENTS.md`의 `## oms-codex 운영` 섹션에 라우팅 정책으로 기록한다.

| 프로젝트 유형 | 우선 라우팅 | 게이트 후보 |
|---|---|---|
| 신규 개발 | 판정된 주 영역에 따라 `page-builder` 또는 `data-layer` 우선 | `evaluator`, `qa-guard` |
| 레거시 포팅 | `evaluator`가 원본-스펙-구현 3자 대조를 우선 | `qa-guard`, 필요 시 `security-auditor` |
| 프론트 중심 | `page-builder` 우선 | `design-reviewer`, `qa-guard` |
| 백엔드/API 중심 | `data-layer` 우선 | `tdd-agent`, `security-auditor`, `qa-guard` |
| 풀스택 | `page-builder`와 `data-layer` 병행 | `evaluator`, `qa-guard`, `security-auditor`, `design-reviewer` |
| 문서/계획 중심 | `plan-auditor`, `milestone-tracker` 우선 | `compound-learner` |

게이트 후보는 실제 설치된 항목만 활성으로 기록한다. 원본 부재나 충돌 보류 항목은 후보에서 제외하거나 `확인 필요`로 남긴다.

## AGENTS.md 기록 규칙

`AGENTS.md`에는 실제 확인한 파일과 경로만 기록한다. 상태는 `설치됨`, `갱신됨`, `원본 부재`, `확인 필요`, `충돌 보류`를 구분한다.

기록 필수 항목:

- 필수 agent별 설치 상태
- 필수 skill별 설치 상태
- 선택 agent/skill 설치 또는 제외 사유
- 프로젝트 유형 판정과 근거 경로
- 적용된 에이전트 라우팅
- 프로젝트 override 존재 여부
- 충돌/확인 필요 목록

## 금지

- 원본이 없는 agent, skill, source를 창작하지 않는다.
- 사용자 변경 가능성이 있는 기존 `.codex/agents/` 또는 `.agents/skills/` 파일을 임의 overwrite하지 않는다.
- 마일스톤 구현을 시작하지 않는다.
- `docs/progress/milestone-status.md`를 선생성하지 않는다.
- production dependency를 추가하지 않는다.
- lockfile이나 package manager 설정을 변경하지 않는다.

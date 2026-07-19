# 프로젝트 로컬 하네스 설치

## 정본

- source agents: `.codex/agents/*.toml`
- model profiles: `agent-profiles.json`
- topology profiles: `topology-profiles.json`
- skills: `.agents/skills/*/SKILL.md`

`lean`은 core 6개를, `full`은 source 9개를 설치한다. agent 이름 목록을 문서에 복제하지 않고 topology manifest에서 읽는다.

## 설치 절차

1. 원본 루트와 대상 프로젝트 절대 경로를 검증한다. 대상 root와 설치 하위 경로에 symlink·junction·reparse point가 있으면 거부한다.
2. topology를 선택한다. 명시값이 없으면 `lean`이다. Bash 설치기는 Python 3으로 topology JSON을 읽는다.
3. topology의 `default_agents`가 source에 모두 존재하는지 확인한다.
4. 대상 `.codex/agents/`, `.agents/skills/`의 충돌을 사전 확인한다.
5. 기본은 복사, 공유 갱신이 명시됐을 때만 symlink를 사용한다.
6. 기존 대상과 다르면 임의 덮어쓰지 않는다. Force가 명시되면 KST timestamp 백업 후 교체한다. 모든 항목을 먼저 staging하고 중간 실패 시 이번 실행의 교체를 역순 원복한다.
7. 설치된 agent subset에 선택 model profile을 적용하고 `--check`로 확인한다.
8. source-target 대응, skill frontmatter, parser·계약 검증을 수행한다.

## direct skill mode

bugfix, refactor, TDD, milestone tracking, session archive는 별도 custom agent를 설치하지 않는다. 오케스트레이터 또는 data-layer가 topology manifest의 `direct_skill_modes`에 따라 해당 skill을 직접 사용한다.

## 프로젝트 유형별 라우팅

| 유형 | 구현 | 조건부 검증 |
|---|---|---|
| 프론트 | page-builder | design-reviewer, qa-guard, evaluator |
| 백엔드/API | data-layer + tdd | qa-guard, security-auditor, evaluator |
| 풀스택 | data-layer 계약 후 page-builder | full gate |
| 문서/계획 | 오케스트레이터, plan-auditor는 선택 설치 | direct 또는 evaluator |

일반 문서·스크립트·인프라를 data-layer에 임의 배정하지 않는다. 선택 agent가 설치되지 않았으면 원본을 창작하지 말고 오케스트레이터 direct skill 경로 또는 `원본 부재`를 보고한다.

## 검증

- PowerShell Parser와 가능한 환경의 `bash -n`
- 기본 설치 agent 집합 == lean `default_agents`
- full 설치 agent 집합 == full `default_agents`
- 설치 subset의 model/effort profile 일치
- 충돌 시 비파괴 종료, Force 시 백업 존재
- child link 범위 이탈과 source-target 중첩 symlink 거부
- staging 실패와 교체 중간 실패 시 부분 설치 없음
- 사용자 홈·전역 config·marketplace 미변경

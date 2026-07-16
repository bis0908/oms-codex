---
name: init-project
description: 대상 프로젝트를 oms-codex 파이프라인으로 초기화하는 스킬. AGENTS.md 생성/보완, 프로젝트 로컬 하네스 설치 또는 갱신, 기본 하위 에이전트 설치 확인, 프로젝트 유형별 에이전트 라우팅 최적화, 진행 정본 점검, 동작 레이어 prefix, 위험 클래스 게이트, compound 디렉터리, orchestrate 실행 전 준비가 필요할 때 사용한다.
---

## 목적

대상 프로젝트를 oms-codex 파이프라인에 연결하고, 로컬 하네스를 설치·최적화해 `orchestrate`가 실행 가능한 기반을 만든다.
마일스톤 구현은 시작하지 않는다. 구현·검증 파이프라인 실행은 `orchestrate`가 담당한다.

이 스킬은 대상 프로젝트 루트에서 실행한다. 플러그인 저장소 안에서 실행 중이면 대상 프로젝트 파일을 추정하지 말고, 사용자가 지정한 대상 프로젝트에서 다시 실행하도록 보고한다.

## 책임 경계

| 포함 | 제외 |
|---|---|
| 프로젝트 상태 점검, 프로젝트 로컬 `.codex/agents/`와 `.agents/skills/` 하네스 설치·갱신, 실행 프로필 선택·기록, 기본 하위 에이전트 설치 확인, 프로젝트 유형별 에이전트 라우팅 최적화, `AGENTS.md` 생성/보완, 프로젝트 override 여부 확인, 경로·게이트 후보 작성, 진행 정본 준비 상태 판정, `docs/compound/` 최소 초기화, 설치 검증, readiness 보고 | 마일스톤 구현 시작, `docs/progress/milestone-status.md` 선생성, 하위 에이전트로 실제 구현·검증 실행, 커밋, production dependency 추가, lockfile·package manager 설정 변경, 기존 문서 덮어쓰기, 불명확한 에이전트 override·위험 경로 확정 |

초기화 상태와 `orchestrate` 실행 가능 상태를 분리해 보고한다. 신규 프로젝트에서 마일스톤 정본이 없는 것은 정상 상태이며, 이 경우 초기화가 완료됐더라도 `orchestrate readiness`만 `준비 필요`로 보고한다.

로컬 하네스 설치·갱신이 필요하면 `references/harness-install.md`를 읽고, 실제 플러그인 번들에 존재하는 agent/skill/source만 대상 프로젝트에 반영한다.

## 1. 대상 프로젝트 상태 점검

먼저 파일을 만들지 말고 현재 구조를 확인한다.

필수 확인 항목:

- `AGENTS.md` 존재 여부
- `.codex/agents/` 존재 여부와 기존 agent TOML
- `.agents/skills/` 존재 여부와 기존 skill 디렉터리
- `docs/progress/milestone-status.md` 존재 여부
- `docs/compound/` 존재 여부
- `_workspace/` 존재 여부
- package manager: `pnpm-lock.yaml`, `packageManager`, `package-lock.json`, `yarn.lock`, `bun.lockb`
- framework: `next.config.*`, `vite.config.*`, `src/app`, `src/pages`, `app`, `pages`, `server`, `api`, `routes`
- DB/API 구조: `prisma/`, `drizzle/`, `supabase/`, `migrations/`, `db/`, `schema.sql`, `src/app/api`, `pages/api`, `controllers`, `services`, `repositories`
- 기존 문서 구조: `docs/`, `docs/02-roadmap/`, `docs/02-roadmap/01-milestones.md`, `docs/02-roadmap/02-work-tickets.md`, `docs/progress/`, `docs/history/`, `docs/handoffs/`

확인 결과는 이후 판단의 근거로 사용한다. 없는 경로는 결함으로 단정하지 말고 "근거 부재" 또는 "미초기화"로 분류한다.

현재 경로가 oms-codex 플러그인 저장소 또는 플러그인 캐시 내부이면 중단한다. 예: `.codex-plugin/plugin.json`, `.codex/agents/`, `.agents/skills/init-project/`가 함께 있고 플러그인 자체를 수정 중인 구조. 이때는 대상 프로젝트 경로를 요청하고 프로젝트 파일을 추정하지 않는다.

## 2. 프로젝트 유형 판정

아래 유형 중 하나 이상을 판정한다. 근거 파일이 부족하면 `판정 보류`를 허용한다.

| 유형 | 판정 기준 |
|---|---|
| 신규 개발 | 레거시 소스 근거 없이 로드맵·티켓·새 코드 구조만 존재 |
| 레거시 포팅 | `_workspace/01_legacy_*`, legacy 디렉터리, 기존 시스템 분석 문서, 포팅 로드맵 중 하나 이상 존재 |
| 프론트 중심 | UI 페이지·컴포넌트·라우팅 문서가 주된 산출물이고 API/DB 변경이 없거나 부차적 |
| 백엔드/API 중심 | API handler, service, repository, DB schema, migration, 테스트가 주된 산출물 |
| 풀스택 | UI와 API/DB 산출물이 같은 마일스톤 범위에 함께 존재 |
| 문서/계획 중심 | 코드 산출물보다 로드맵·요구사항·계획 문서만 존재 |

판정은 하네스 설치 후 에이전트 라우팅을 최적화하기 위한 정보다. 판정만으로 구현을 시작하지 않는다.

## 3. 로컬 하네스 설치 또는 갱신

`references/harness-install.md`를 읽고 설치 대상, 상태 판정, 충돌 처리, 프로젝트 유형별 라우팅을 적용한다.

핵심 원칙:

- 대상 프로젝트 루트의 `.codex/agents/`와 필요한 `.agents/skills/`에만 설치한다.
- 원본은 현재 oms-codex 플러그인 번들의 실제 파일만 사용한다.
- 원본이 없으면 파일을 창작하지 않고 `원본 부재`로 보고한다.
- 기존 대상 파일이 있으면 먼저 읽고 비교한다.
- 원본과 다르고 사용자 변경 가능성이 있으면 임의 overwrite하지 않는다.
- 불명확한 충돌은 `확인 필요` 또는 `충돌 보류`로 기록한다.
- production dependency, lockfile, package manager 설정은 변경하지 않는다.

설치 결과는 `설치됨`, `갱신됨`, `원본 부재`, `확인 필요`, `충돌 보류` 중 하나로 에이전트·스킬별로 기록한다. 프로젝트별 최적화는 기본적으로 agent TOML을 임의 수정하지 않고 `AGENTS.md`의 라우팅 정책으로 기록한다. 단, 승인된 실행 프로필의 `model`, `model_reasoning_effort` 두 필드는 3.0 절에 따라 갱신할 수 있다. 프로젝트가 이미 override agent를 갖고 있으면 보존하고 상태를 별도 기록한다.

### 3.0 실행 프로필 선택과 적용

실행 프로필은 현재 플러그인 번들의 `references/agent-profiles.json`을 정본으로 사용한다. source agent TOML은 기본 `balanced` 프로필과 일치해야 하며, 대상 프로젝트에는 선택된 프로필의 모델·effort만 적용한다.

최초 초기화에서 대상 `AGENTS.md`의 `## oms-codex 운영`에 유효한 `에이전트 실행 프로필` 기록이 없으면, 파일을 만들거나 하네스를 설치하기 전에 다음 선택을 요청한다.

```text
OMS Codex 실행 프로필을 선택해 주세요.
1. balanced: 기본 권장. 구현·고위험 판단은 Sol, 규칙 기반 검수·학습은 Terra, 정형 상태 작업은 Luna
2. performance: 직접 구현·전문 검수에 Sol을 선택적으로 사용
3. economy: data-layer, evaluator, security-auditor만 Sol 유지; page-builder와 일반 작업은 Terra
4. low-cost: 필수 역할은 Terra/xhigh, 단순 상태·세션 작업은 Luna/medium
```

- 사용자가 1·2·3·4 또는 대응하는 profile ID를 선택하지 않으면 `결과: needs-input`으로 종료한다. 이 경우 `.codex/agents/`, `.agents/skills/`, `AGENTS.md`를 생성·수정하지 않는다.
- 기존 `AGENTS.md`에 `balanced`, `performance`, `economy`, `low-cost` 중 하나가 기록돼 있으면 이를 유지한다. 프로필 변경은 사용자가 새 선택을 명시했을 때만 수행한다.
- 기록값이 없거나 유효하지 않은데 대상 agent TOML이 이미 있으면 값을 추측하지 않고 `확인 필요`로 보고한다.
- 일반 설치 또는 갱신으로 대상 agent TOML을 준비한 뒤, 현재 플러그인 번들의 source agents와 대상 agent 디렉터리를 사용해 다음 helper를 실행한다.

```text
python <현재 플러그인>/.agents/skills/init-project/references/apply-agent-profile.py \
  --source-agents <현재 플러그인>/.codex/agents \
  --target-agents .codex/agents \
  --profile <balanced|performance|economy|low-cost>
```

- helper는 source와 target이 `model`, `model_reasoning_effort` 외에는 동일할 때만 해당 두 필드를 원자적으로 바꾼다. 다른 사용자 변경이 있으면 덮어쓰지 않고 `충돌 보류`로 기록한다.
- Python을 사용할 수 없으면 helper의 비교·원자성 보장을 대신할 수 없다. agent TOML을 추측해 바꾸지 말고 `확인 필요`로 보고한다.
- helper 성공 뒤에는 같은 인자에 `--check`를 붙여 14개 대상 agent가 선택 프로필과 일치하는지 확인한다.

## 4. AGENTS.md 생성 또는 보완

`AGENTS.md`가 없으면 새로 만든다. 있으면 기존 내용을 보존하고 `## oms-codex 운영` 섹션만 추가하거나 갱신한다.

금지:

- 사용자 전역 지침을 무단 복사하지 않는다.
- 기존 프로젝트 규칙을 삭제하거나 재정렬하지 않는다.
- 프로젝트 override 에이전트가 확인되지 않았는데 임의 이름으로 확정하지 않는다.

`AGENTS.md`에 포함할 최소 섹션:

```markdown
## oms-codex 운영

### 기본 구현 에이전트

| 구현 영역 | 기본 에이전트 | 상태 |
|---|---|---|
| 프론트 구현 | page-builder | <설치됨/원본 부재/확인 필요/충돌 보류> |
| 백엔드/API/데이터 구현 | data-layer | <설치됨/원본 부재/확인 필요/충돌 보류> |
| 일반 코드/스크립트/인프라/결정 문서 | <프로젝트 override 또는 오케스트레이터 직접 수행> | <확정/확인 필요> |

### 에이전트 실행 프로필

- 선택: `<balanced | performance | economy | low-cost>`
- 선택 근거: `<사용자 최초 선택 | 사용자 명시 변경 | 기존 기록 유지>`
- 프로필 정본: `.agents/skills/init-project/references/agent-profiles.json`

| 에이전트 | 모델 | effort |
|---|---|---|
| `<선택 프로필의 14개 agent 각각>` | `<agent-profiles.json의 실제 값>` | `<agent-profiles.json의 실제 값>` |

### 설치된 하네스

| 항목 | 경로 | 상태 |
|---|---|---|
| page-builder | `.codex/agents/page-builder.toml` | <상태> |
| data-layer | `.codex/agents/data-layer.toml` | <상태> |
| evaluator | `.codex/agents/evaluator.toml` | <상태> |
| qa-guard | `.codex/agents/qa-guard.toml` | <상태> |
| milestone-tracker | `.codex/agents/milestone-tracker.toml` | <상태> |
| plan-auditor | `.codex/agents/plan-auditor.toml` | <상태> |
| compound-learner | `.codex/agents/compound-learner.toml` | <상태> |
| compound-curator | `.codex/agents/compound-curator.toml` | <상태> |

### 에이전트 라우팅

| 작업 유형 | 우선 에이전트 | 게이트 후보 |
|---|---|---|
| 프론트 구현 | page-builder | design-reviewer, qa-guard |
| 백엔드/API/데이터 구현 | data-layer | tdd-agent, security-auditor, qa-guard |
| 요구사항 검증 | evaluator | qa-guard, design-reviewer, security-auditor |
| 계획·진행 관리 | plan-auditor, milestone-tracker | compound-learner |
| 반복 학습 추가 | compound-learner | 없음 |
| 누적 학습 무손실 정리 | compound-curator | 없음 |
| 일반 코드·문서·인프라 | 프로젝트 override 또는 오케스트레이터 | qa-guard, evaluator |

### 프로젝트 최적화

- 판정 유형: <유형 또는 판정 보류>
- 판정 근거: <실제 확인한 파일/경로>
- 적용 라우팅: <실제 설치된 에이전트 기준>
- override 상태: <없음/확인 필요/프로젝트 로컬 override 사용>
- 커밋 정책: <auto/ask/disabled, 미정의 시 ask>
- commit-local capability: <사용 가능/부재>

### 설치 검증

- `.codex/agents/` 필수 에이전트 상태: <요약>
- 실행 프로필과 대상 agent TOML 일치: <통과/실패/미실행>
- `.agents/skills/` 필수 스킬 상태: <요약>
- 선택 에이전트와 스킬 상태: <요약>
- 충돌/확인 필요: <없음 또는 목록>

### 커밋 capability preflight

1. 현재 세션에 노출된 skill/capability 목록에서 정확한 이름 `commit-local`을 확인한다.
2. 목록을 확인할 수 없으면 현재 환경의 실제 skill 경로를 읽어 존재를 확인한다. 추정 이름이나 `commit` alias를 만들지 않는다.
3. 확인되면 `사용 가능`, 없으면 `부재`로 기록한다. init-project가 새 skill을 설치하거나 사용자 전역 설정을 수정하지 않는다.
4. 프로젝트 커밋 정책을 `auto`, `ask`, `disabled` 중 하나로 기록한다. 사용자가 정하지 않았으면 `ask`다.
5. `auto`인데 capability가 없으면 readiness에 자동 커밋 불가를 명시하되 하네스 초기화 자체를 실패시키지 않는다.

### 경로와 게이트

- 동작 레이어 prefix 후보: <후보 목록 또는 미정>
- 보안 고위험 prefix/키워드 후보: <후보 목록 또는 미정>
- 시각 전용 prefix 후보: <후보 목록 또는 없음>
- 마이그레이션/스키마/백필 위험 클래스 후보: <후보 목록 또는 미정>

### 문서 경로

- 진행 정본: `docs/progress/milestone-status.md`
- 마일스톤 작업 로그: `docs/progress/milestones/M{N}.md`
- 반복 학습: `docs/compound/`
- 임시 검증 산출물: `_workspace/`
```

프로젝트가 별도 구현 에이전트를 정의했다면 이 표에 override로 기록한다. 일반 코드·문서·인프라 역할이 모호하면 data-layer로 자동 배정하지 않고 `확인 필요`에 남긴다. 레거시 분석은 기본 하네스에 포함하지 않으므로, 포팅 프로젝트에서 원본 분석이 필요하면 별도 분석 방법을 사용자 확인 항목으로 남긴다.

## 5. 경로와 게이트 설정

프로젝트 구조에서 후보를 작성한다. 모호한 후보는 확정하지 않는다.

### 동작 레이어 prefix 후보

목적: 구현 파일 분류와 증분 재게이팅 범위를 좁힌다. 기능형 버그의 evaluator 실행 여부를 경로 prefix만으로 스킵하지 않는다.

후보 예:

- API handler: `src/app/api/`, `app/api/`, `pages/api/`, `src/pages/api/`
- service/usecase: `src/services/`, `services/`, `server/services/`
- repository/data access: `src/repositories/`, `repositories/`, `src/lib/db/`, `lib/db/`, `db/`
- auth/session: `src/auth/`, `auth/`, `session/`, `middleware.*`
- server action/server module: `src/actions/`, `actions/`, `server/`

프로젝트에 맞는 prefix만 남긴다. prefix가 미정이면 보수 기본값으로 "전 파일 동작 레이어 취급 필요"를 보고한다.

### 시각 전용 prefix 후보

목적: 순수 시각형 버그에서 evaluator를 사용자 시각 검증으로 대체할 수 있는 경계를 명시한다.

- 실제로 기능 로직이 없는 token/theme/static style 경로만 후보로 둔다.
- component, JSX/TSX, template 경로는 클릭·상태·조건부 렌더가 섞일 수 있으므로 기본 후보에 넣지 않는다.
- 후보가 없으면 `없음`으로 기록하고 evaluator를 보수적으로 실행한다.

### 보안 고위험 prefix/키워드 후보

목적: qa-guard의 `보안 심층 검토 필요` 신호와 security-auditor 게이트를 준비한다.

후보 키워드:

- `auth`, `session`, `permission`, `role`, `admin`, `payment`, `webhook`, `upload`, `delete`, `export`
- `token`, `cookie`, `password`, `secret`, `credential`, `personal`, `privacy`, `pii`
- 한국어 문서 키워드: `인증`, `인가`, `권한`, `세션`, `토큰`, `쿠키`, `결제`, `웹훅`, `업로드`, `삭제`, `개인정보`, `내보내기`

후보 prefix는 실제 경로가 존재할 때만 확정한다. 키워드는 문서·티켓 탐지용 후보로 둘 수 있다. manifest가 미정이면 모든 API route와 server action을 security-auditor 대상으로 본다고 기록한다.

### 마이그레이션/스키마/백필 위험 클래스 후보

목적: `orchestrate` Phase 5-D의 dev DB 적용 확인 게이트를 준비한다.

후보:

- 경로: `migrations/`, `prisma/migrations/`, `supabase/migrations/`, `db/migrations/`, `schema/`, `schemas/`
- 파일: `schema.sql`, `schema.prisma`, `drizzle.config.*`
- 키워드: `migration`, `schema`, `backfill`, `DDL`, `ALTER TABLE`, `CREATE TABLE`, `마이그레이션`, `스키마`, `백필`

적용 명령이 문서화돼 있지 않으면 임의 작성하지 말고 확인 필요로 남긴다.

### 프로젝트 문서 경로 규칙

기존 문서 구조를 우선한다. 새 경로가 필요하면 아래 기본값을 사용한다.

- 진행 정본: `docs/progress/milestone-status.md`
- 작업 로그: `docs/progress/milestones/M{N}.md`
- 로드맵: `docs/02-roadmap/01-milestones.md`
- 작업 티켓: `docs/02-roadmap/02-work-tickets.md`, `docs/02-roadmap/tickets/m{N}-*.md`
- 계획 감사 보고서: `_workspace/plan_audit_*.md`
- QA 보고서: `_workspace/qa_*.md`
- 디자인 검수 보고서: `_workspace/design_review_*.md`
- 보안 감사 보고서: `_workspace/security_*.md`
- 요구사항 검증 보고서: `_workspace/eval_*.md`
- 반복 학습: `docs/compound/{카테고리}/`

## 6. 진행 정본 점검

`docs/progress/milestone-status.md`가 있으면 덮어쓰지 않는다. 형식이 `milestone-track`의 2계층 구조와 크게 다르면 보완 필요로 보고한다.

`docs/progress/milestone-status.md`가 없어도 생성하지 않는다. 첫 마일스톤 착수 시 `orchestrate`와 `milestone-track`이 필요한 상태 파일을 만든다.

`docs/progress/milestone-status.md`가 없으면 아래 순서로 준비 상태만 판정한다.

1. `docs/02-roadmap/01-milestones.md`, `docs/02-roadmap/02-work-tickets.md`, `docs/02-roadmap/tickets/`를 읽는다.
2. 다음에 실행할 마일스톤의 `목표`, `범위`, `완료 기준`을 채울 근거가 있는지 확인한다.
3. 근거가 충분하면 `orchestrate readiness: 즉시 실행 가능`으로 보고한다.
4. 근거가 부족하면 빈 마일스톤을 만들지 않는다. `orchestrate readiness: 준비 필요`로 보고하고 필요한 로드맵·티켓·완료 기준 작성을 요청한다.

## 7. compound 초기화

`docs/compound/`가 없으면 생성할 수 있다. 단, 빈 카테고리 파일을 과도하게 만들지 않는다.

허용:

- `docs/compound/` 디렉터리 생성
- 필요한 경우 최소 `docs/compound/README.md` 생성
- 특정 카테고리 근거가 이미 있을 때만 `docs/compound/{카테고리}/README.md` 생성

금지:

- 사례가 없는데 `frontend`, `data-layer`, `evaluation`, `qa`, `design`, `bugfix`, `tdd`, `security`, `harness` 카테고리 파일을 전부 선생성
- 반복 학습 사례를 추정해서 작성

부재를 허용할 수 있으면 생성하지 않고 "첫 학습 시 compound-learner가 생성"으로 보고한다.

## 8. 최종 readiness 보고

마지막에 초기화 상태와 `orchestrate` 호출 가능 여부를 각각 판정한다.

`init readiness` 판정 기준:

- `AGENTS.md`에 oms-codex 운영 섹션이 존재한다.
- `.codex/agents/`와 필요한 `.agents/skills/` 하네스 설치 또는 설치 불가 사유가 기록돼 있다.
- 필수 하위 에이전트 `page-builder`, `data-layer`, `evaluator`, `qa-guard`, `milestone-tracker`, `plan-auditor`, `compound-learner`의 설치 상태가 기록돼 있다.
- `compound-curator` 설치 상태와 append 학습/무손실 정리 역할 분리가 기록돼 있다.
- 기본 구현 에이전트 `page-builder`, `data-layer`를 사용할 수 있거나, 프로젝트 override 확인 필요 항목이 명시돼 있다.
- 유효한 실행 프로필이 기록되고 대상 14개 agent TOML의 model/effort가 해당 프로필과 일치한다.
- 프로젝트 유형별 에이전트 라우팅과 최적화 결과가 기록돼 있다.
- 설치 검증 결과가 기록돼 있다.
- 동작 레이어 prefix와 위험 클래스 후보가 확정 또는 보류 상태로 기록돼 있다.
- 보안 고위험 manifest, 시각 전용 manifest, 커밋 정책, `commit-local` capability 상태가 기록돼 있다.
- `docs/progress/milestone-status.md` 존재 여부와 부재 시 첫 마일스톤 착수 때 생성될 수 있음을 기록했다.
- `docs/compound/` 최소 초기화 여부를 처리했다.

위 기준을 충족하면 `init readiness: 초기화 완료`로 보고한다. 직접 처리할 수 없는 차단 항목 때문에 위 기준을 충족하지 못한 경우에만 `init readiness: 초기화 보류`로 보고한다.

`orchestrate readiness` 판정 기준:

- `orchestrate` 작업 봉투의 `목표`, `범위`, `완료 기준`을 채울 정본이 있다.

정본이 있으면 `orchestrate readiness: 즉시 실행 가능`으로 보고한다. 정본이 없거나 부족하면 `orchestrate readiness: 준비 필요`로 보고하고, 필요한 문서 또는 티켓 작성을 다음 단계로 제안한다.

보고 형식:

```markdown
init readiness: <초기화 완료 | 초기화 보류>
orchestrate readiness: <즉시 실행 가능 | 준비 필요>

설치된 하네스:
- <에이전트/스킬 파일과 상태>

설치 보류/실패 항목:
- <없음 또는 원본 부재/확인 필요/충돌 보류>

프로젝트 유형 판정:
- <유형과 근거>

적용된 에이전트 라우팅:
- <우선 에이전트와 게이트 후보>

실행 프로필:
- <profile ID, 선택 근거, model/effort 일치 결과>

생성/수정한 파일:
- <없음 또는 파일 목록>

확인 필요:
- <사용자가 결정해야 하는 기본 에이전트 override/경로/마일스톤>

다음 단계:
- <권장 orchestrate 호출 또는 먼저 작성할 문서>

검증 결과:
- `.codex/agents/` 설치 파일 목록 확인: <결과>
- 필수 하위 에이전트별 설치 상태 확인: <결과>
- 선택 실행 프로필 적용·`--check` 확인: <결과>
- `AGENTS.md` oms-codex 운영 섹션 diff 확인: <결과>
- `docs/progress/milestone-status.md` 선생성 없음: <결과>
- production dependency 추가 없음: <결과>
- lockfile/package manager 설정 변경 없음: <결과>
- 커밋 없음: <결과>
```

`orchestrate` 호출 예시는 정본이 준비된 경우에만 제안한다.

```text
$oms-codex:orchestrate M{N} <목표 또는 티켓>
```

정본이 부족하면 위 호출 대신 먼저 작성할 문서를 제안한다.

## 검증

작업 종료 전에 아래를 확인한다.

- `.codex/agents/`와 `.agents/skills/`에 설치된 파일 목록을 확인한다.
- 필수 하위 에이전트별 설치 상태를 확인한다.
- 변경한 `AGENTS.md` 섹션만 diff로 검토한다.
- `docs/progress/milestone-status.md`를 생성·수정하지 않았음을 확인한다.
- `docs/compound/`를 만들었다면 빈 카테고리 파일을 과도하게 만들지 않았는지 확인한다.
- 새 production dependency가 추가되지 않았는지 확인한다.
- lockfile이나 package manager 설정이 바뀌지 않았는지 확인한다.
- 커밋하지 않았음을 보고한다.

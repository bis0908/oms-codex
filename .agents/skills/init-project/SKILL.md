---
name: init-project
description: 대상 프로젝트를 oms-codex 파이프라인으로 초기화하는 스킬. 프로젝트를 oms-codex 파이프라인으로 초기화, AGENTS.md 생성/보완, 기본 구현 에이전트 확인, 프로젝트 override 여부 확인, 진행 정본 점검, 동작 레이어 prefix, 위험 클래스 게이트, compound 디렉터리, orchestrate 실행 전 준비가 필요할 때 사용한다. orchestrate 실행 전에 프로젝트별 부트스트랩 상태를 점검·보완한다.
---

## 목적

대상 프로젝트를 oms-codex 파이프라인에 연결할 최소 운영 기준을 만든다.
마일스톤 구현은 시작하지 않는다. 구현·검증 파이프라인 실행은 `orchestrate`가 담당한다.

이 스킬은 대상 프로젝트 루트에서 실행한다. 플러그인 저장소 안에서 실행 중이면 대상 프로젝트 파일을 추정하지 말고, 사용자가 지정한 대상 프로젝트에서 다시 실행하도록 보고한다.

## 책임 경계

| 포함 | 제외 |
|---|---|
| 프로젝트 상태 점검, `AGENTS.md` 생성/보완, 기본 구현 에이전트 확인, 프로젝트 override 여부 확인, 경로·게이트 후보 작성, 진행 정본 준비 상태 판정, `docs/compound/` 최소 초기화, readiness 보고 | 마일스톤 구현, `docs/progress/milestone-status.md` 선생성, 하위 구현 에이전트 호출, 커밋, production dependency 추가, 기존 문서 덮어쓰기, 불명확한 에이전트 override·위험 경로 확정 |

초기화 상태와 `orchestrate` 실행 가능 상태를 분리해 보고한다. 신규 프로젝트에서 마일스톤 정본이 없는 것은 정상 상태이며, 이 경우 초기화가 완료됐더라도 `orchestrate readiness`만 `준비 필요`로 보고한다.

## 1. 대상 프로젝트 상태 점검

먼저 파일을 만들지 말고 현재 구조를 확인한다.

필수 확인 항목:

- `AGENTS.md` 존재 여부
- `docs/progress/milestone-status.md` 존재 여부
- `docs/compound/` 존재 여부
- `_workspace/` 존재 여부
- package manager: `pnpm-lock.yaml`, `packageManager`, `package-lock.json`, `yarn.lock`, `bun.lockb`
- framework: `next.config.*`, `vite.config.*`, `src/app`, `src/pages`, `app`, `pages`, `server`, `api`, `routes`
- DB/API 구조: `prisma/`, `drizzle/`, `supabase/`, `migrations/`, `db/`, `schema.sql`, `src/app/api`, `pages/api`, `controllers`, `services`, `repositories`
- 기존 문서 구조: `docs/`, `docs/02-roadmap/`, `docs/02-roadmap/01-milestones.md`, `docs/02-roadmap/02-work-tickets.md`, `docs/progress/`, `docs/history/`, `docs/handoffs/`

확인 결과는 이후 판단의 근거로 사용한다. 없는 경로는 결함으로 단정하지 말고 "근거 부재" 또는 "미초기화"로 분류한다.

## 2. 프로젝트 유형 판정

아래 유형 중 하나 이상을 판정한다. 근거 파일이 부족하면 `판정 보류`를 허용한다.

| 유형 | 판정 기준 |
|---|---|
| 신규 개발 | 레거시 소스 근거 없이 로드맵·티켓·새 코드 구조만 존재 |
| 레거시 포팅 | `_workspace/01_legacy_*`, legacy 디렉터리, 기존 시스템 분석 문서, 포팅 로드맵 중 하나 이상 존재 |
| 프론트 중심 | UI 페이지·컴포넌트·라우팅 문서가 주된 산출물이고 API/DB 변경이 없거나 부차적 |
| 백엔드/API 중심 | API handler, service, repository, DB schema, migration, 테스트가 주된 산출물 |
| 풀스택 | UI와 API/DB 산출물이 같은 마일스톤 범위에 함께 존재 |
| 문서/계획만 있는 초기 상태 | 코드 산출물보다 로드맵·요구사항·계획 문서만 존재 |

판정은 `orchestrate`가 기본 구현 에이전트를 투입할지 판단하기 위한 정보다. 판정만으로 구현을 시작하지 않는다.

## 3. AGENTS.md 생성 또는 보완

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
| 프론트 구현 | page-builder | 기본 |
| 백엔드/API/데이터 구현 | data-layer | 기본 |

### 경로와 게이트

- 동작 레이어 prefix 후보: <후보 목록 또는 미정>
- 보안 고위험 prefix/키워드 후보: <후보 목록 또는 미정>
- 마이그레이션/스키마/백필 위험 클래스 후보: <후보 목록 또는 미정>

### 문서 경로

- 진행 정본: `docs/progress/milestone-status.md`
- 마일스톤 작업 로그: `docs/progress/milestones/M{N}.md`
- 반복 학습: `docs/compound/`
- 임시 검증 산출물: `_workspace/`
```

프로젝트가 별도 구현 에이전트를 정의했다면 이 표에 override로 기록한다. 모호하면 기본값을 유지하고 `확인 필요`에 남긴다. 레거시 분석은 기본 하네스에 포함하지 않으므로, 포팅 프로젝트에서 원본 분석이 필요하면 별도 분석 방법을 사용자 확인 항목으로 남긴다.

## 4. 경로와 게이트 설정

프로젝트 구조에서 후보를 작성한다. 모호한 후보는 확정하지 않는다.

### 동작 레이어 prefix 후보

목적: bugfix와 증분 재게이팅에서 evaluator/qa/security 재진입 여부를 경로 prefix로 판정한다.

후보 예:

- API handler: `src/app/api/`, `app/api/`, `pages/api/`, `src/pages/api/`
- service/usecase: `src/services/`, `services/`, `server/services/`
- repository/data access: `src/repositories/`, `repositories/`, `src/lib/db/`, `lib/db/`, `db/`
- auth/session: `src/auth/`, `auth/`, `session/`, `middleware.*`
- server action/server module: `src/actions/`, `actions/`, `server/`

프로젝트에 맞는 prefix만 남긴다. prefix가 미정이면 보수 기본값으로 "전 파일 동작 레이어 취급 필요"를 보고한다.

### 보안 고위험 prefix/키워드 후보

목적: qa-guard의 `보안 심층 검토 필요` 신호와 security-auditor 게이트를 준비한다.

후보 키워드:

- `auth`, `session`, `permission`, `role`, `admin`, `payment`, `webhook`, `upload`, `delete`, `export`
- `token`, `cookie`, `password`, `secret`, `credential`, `personal`, `privacy`, `pii`
- 한국어 문서 키워드: `인증`, `인가`, `권한`, `세션`, `토큰`, `쿠키`, `결제`, `웹훅`, `업로드`, `삭제`, `개인정보`, `내보내기`

후보 prefix는 실제 경로가 존재할 때만 확정한다. 키워드는 문서·티켓 탐지용 후보로 둘 수 있다.

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

## 5. 진행 정본 점검

`docs/progress/milestone-status.md`가 있으면 덮어쓰지 않는다. 형식이 `milestone-track`의 2계층 구조와 크게 다르면 보완 필요로 보고한다.

`docs/progress/milestone-status.md`가 없어도 생성하지 않는다. 첫 마일스톤 착수 시 `orchestrate`와 `milestone-track`이 필요한 상태 파일을 만든다.

`docs/progress/milestone-status.md`가 없으면 아래 순서로 준비 상태만 판정한다.

1. `docs/02-roadmap/01-milestones.md`, `docs/02-roadmap/02-work-tickets.md`, `docs/02-roadmap/tickets/`를 읽는다.
2. 다음에 실행할 마일스톤의 `목표`, `범위`, `완료 기준`을 채울 근거가 있는지 확인한다.
3. 근거가 충분하면 `orchestrate readiness: 즉시 실행 가능`으로 보고한다.
4. 근거가 부족하면 빈 마일스톤을 만들지 않는다. `orchestrate readiness: 준비 필요`로 보고하고 필요한 로드맵·티켓·완료 기준 작성을 요청한다.

## 6. compound 초기화

`docs/compound/`가 없으면 생성할 수 있다. 단, 빈 카테고리 파일을 과도하게 만들지 않는다.

허용:

- `docs/compound/` 디렉터리 생성
- 필요한 경우 최소 `docs/compound/README.md` 생성
- 특정 카테고리 근거가 이미 있을 때만 `docs/compound/{카테고리}/README.md` 생성

금지:

- 사례가 없는데 `frontend`, `data-layer`, `evaluation`, `qa`, `design`, `bugfix`, `tdd`, `security`, `harness` 카테고리 파일을 전부 선생성
- 반복 학습 사례를 추정해서 작성

부재를 허용할 수 있으면 생성하지 않고 "첫 학습 시 compound-learner가 생성"으로 보고한다.

## 7. 최종 readiness 보고

마지막에 초기화 상태와 `orchestrate` 호출 가능 여부를 각각 판정한다.

`init readiness` 판정 기준:

- `AGENTS.md`에 oms-codex 운영 섹션이 존재한다.
- 기본 구현 에이전트 `page-builder`, `data-layer`를 사용할 수 있거나, 프로젝트 override 확인 필요 항목이 명시돼 있다.
- 동작 레이어 prefix와 위험 클래스 후보가 확정 또는 보류 상태로 기록돼 있다.
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

완료 항목:
- <생성/수정/확인한 항목>

미완료 항목:
- <없음 또는 보류 항목>

확인 필요:
- <사용자가 결정해야 하는 기본 에이전트 override/경로/마일스톤>

생성/수정한 파일:
- <없음 또는 파일 목록>

다음 단계:
- <권장 orchestrate 호출 또는 먼저 작성할 문서>

검증:
- <frontmatter/문서/경로 확인 결과>
```

`orchestrate` 호출 예시는 정본이 준비된 경우에만 제안한다.

```text
$oms-codex:orchestrate M{N} <목표 또는 티켓>
```

정본이 부족하면 위 호출 대신 먼저 작성할 문서를 제안한다.

## 검증

작업 종료 전에 아래를 확인한다.

- 변경한 `AGENTS.md` 섹션만 diff로 검토한다.
- `docs/progress/milestone-status.md`를 생성·수정하지 않았음을 확인한다.
- `docs/compound/`를 만들었다면 빈 카테고리 파일을 과도하게 만들지 않았는지 확인한다.
- 새 production dependency가 추가되지 않았는지 확인한다.
- 커밋하지 않았음을 보고한다.

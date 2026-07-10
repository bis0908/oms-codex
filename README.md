# OMS Codex

## 개요

OMS Codex 1.1.2는 Codex용 custom agent 팀 하네스를 **프로젝트 로컬 설치 템플릿**으로 배포하기 위한 저장소이다. 버전 정본은 루트의 `VERSION` 파일이다. custom agent 정의, skill, 대상 프로젝트 설치 스크립트를 같은 루트에서 관리한다. Marketplace 플러그인으로 등록하지 않으므로 전역 플러그인 skill과 프로젝트 skill이 중복 노출되지 않는다.

현재 하네스는 14개 custom agent를 제공한다. 반복 사례 추가는 `compound-learner`, 누적 사례 무손실 정리는 `compound-curator`가 분리 담당한다.

## 구조

```text
.
├── .agents/
│   └── skills/
├── .codex/
│   └── agents/
├── scripts/
│   └── verify.ps1
├── install.ps1
├── install.sh
├── AGENTS.md
└── README.md
```

## 설치

Windows PowerShell에서는 설치할 대상 프로젝트를 지정한다. 기본값은 복사 설치이므로 대상 프로젝트의 agent와 skill을 독립적으로 커스터마이즈할 수 있다.

```text
.\install.ps1 -Target D:\workSpace\target-project
```

원본 저장소와 동기화할 프로젝트에만 symlink 설치를 사용한다.

```text
.\install.ps1 -Target D:\workSpace\target-project -Symlink
```

이미 설치된 동일 이름의 agent 또는 skill은 기본적으로 덮어쓰지 않는다. 변경분을 백업한 뒤 교체하려면 `-Force`를 명시한다.

```text
.\install.ps1 -Target D:\workSpace\target-project -Force
```

macOS, Linux, WSL에서는 다음 명령을 사용한다.

```text
./install.sh --target /path/to/target-project
```

symlink 또는 강제 갱신은 각각 다음 옵션을 사용한다.

```text
./install.sh --target /path/to/target-project --symlink
./install.sh --target /path/to/target-project --force
```

설치 스크립트는 원본 agent·skill 디렉터리와 대상 프로젝트 경로를 먼저 검증한다. 충돌이 있으면 어떤 파일도 교체하지 않고 종료한다. 설치 시 agent는 대상 프로젝트의 `.codex/agents/`, skill은 `.agents/skills/`에 배치한다.

기존 marketplace 방식으로 설치한 OMS Codex가 있으면, 대상 프로젝트 설치를 확인한 뒤 해당 로컬 플러그인과 marketplace를 제거한다. 현재 Codex CLI에서는 `codex plugin remove`와 `codex plugin marketplace remove` 명령을 제공한다. 제거 대상 이름은 `codex plugin list` 및 `codex plugin marketplace list`로 확인한다.

## 검증

기본 검증은 다음 항목을 확인한다.

```text
scripts\verify.ps1
bash scripts/verify.sh
```

수동 검증 시에는 `install.ps1` 및 `install.sh`의 구문 검사를 실행하고, 빈 임시 프로젝트에 설치한 뒤 `.codex/agents/`와 `.agents/skills/`의 파일 수를 원본과 비교한다.

검증 스크립트는 세 실행 프로필의 agent별 model/effort, 기본 `performance` agent TOML, 공통 반환 계약, phase/발신자 상태 전이, security 학습 트리거와 필수 게이트 정책도 확인한다.

## 사용

대상 프로젝트에서 설치 스크립트를 실행한 뒤 Codex를 다시 열면 설치된 custom agent와 skill을 해당 프로젝트 작업 흐름에서 사용할 수 있다.

대표 시작 명령은 다음과 같다.

```text
$orchestrate <작업>
```

프로젝트 초기화 시 보안 path/keyword manifest, 시각 전용 manifest, 일반 구현 역할 override, 커밋 정책, 실행 프로필을 `AGENTS.md`에 기록한다. 최초 초기화에서는 다음 실행 프로필 중 하나를 사용자에게 선택받고, 프로젝트 로컬 `.codex/agents`에만 반영한다.

| profile ID | 목적 |
|---|---|
| `performance` | 직접 구현·전문 검수에 Sol을 선택적으로 배정한다. |
| `economy` | `data-layer`, `evaluator`, `security-auditor`만 Sol을 유지하고 `page-builder`는 Terra/xhigh를 사용한다. |
| `low-cost` | 필수 역할은 Terra/xhigh, 단순 상태·세션 작업은 Luna/medium을 사용한다. |

선택하지 않으면 초기화는 `needs-input`으로 종료하며, 기존 프로필은 사용자가 명시적으로 바꾸기 전까지 유지한다. 커밋 정책이 없으면 `ask`로 처리하며, 필수 구현·검증 agent가 재실패하면 완료 경로를 중단한다.

## 범위

이 저장소는 프로젝트 로컬 custom agent·skill 설치를 다룬다. 사용자 홈의 전역 skill 저장소나 Codex 전역 설정 파일, marketplace 설정을 직접 변경하지 않는다.

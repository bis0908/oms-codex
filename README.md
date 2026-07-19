# OMS Codex

## 개요

OMS Codex 1.2.0은 Codex용 custom agent 팀 하네스를 **프로젝트 로컬 설치 템플릿**으로 배포하기 위한 저장소이다. 버전 정본은 루트의 `VERSION` 파일이다. custom agent 정의, skill, 대상 프로젝트 설치 스크립트를 같은 루트에서 관리한다.

source는 9개 custom agent를 제공한다. 기본 `lean` topology는 core 6개만 설치하고, `full`은 plan audit과 compound 3개를 추가한다. bugfix, refactor, TDD, milestone tracking, session archive는 별도 agent가 아니라 direct skill mode다.

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

기본값은 `lean`이다. 선택 agent까지 설치하려면 full topology를 명시한다.

```text
.\install.ps1 -Target D:\workSpace\target-project -Topology full
```

원본 저장소와 동기화할 프로젝트에만 symlink 설치를 사용한다.

```text
.\install.ps1 -Target D:\workSpace\target-project -Symlink
```

이미 설치된 동일 이름의 agent 또는 skill은 기본적으로 덮어쓰지 않는다. 변경분을 백업한 뒤 교체하려면 `-Force`를 명시한다.

```text
.\install.ps1 -Target D:\workSpace\target-project -Force
```

macOS, Linux, WSL에서는 Python 3이 설치된 환경에서 다음 명령을 사용한다. Bash 설치기는 topology 정본 JSON을 Python으로 읽는다.

```text
./install.sh --target /path/to/target-project
./install.sh --target /path/to/target-project --topology full
```

symlink 또는 강제 갱신은 각각 다음 옵션을 사용한다.

```text
./install.sh --target /path/to/target-project --symlink
./install.sh --target /path/to/target-project --force
```

설치 스크립트는 원본 agent·skill 디렉터리와 대상 프로젝트 경로를 먼저 검증한다. 대상 root와 설치 하위 경로의 symlink·junction·reparse point는 범위 밖 쓰기를 막기 위해 거부한다. symlink 설치에서는 원본과 대상이 같거나 중첩될 수 없다. 충돌이 있으면 어떤 파일도 교체하지 않고 종료하며, 모든 항목을 먼저 staging한 뒤 교체하고 중간 실패 시 이번 실행의 변경을 역순 원복한다. 설치 시 agent는 대상 프로젝트의 `.codex/agents/`, skill은 `.agents/skills/`에 배치한다.

## 검증

기본 검증은 다음 항목을 확인한다.

```text
scripts\verify.ps1
bash scripts/verify.sh
```

수동 검증 시에는 `install.ps1` 및 `install.sh`의 구문 검사를 실행하고, 빈 임시 프로젝트에 lean/full을 각각 설치한 뒤 topology manifest의 agent 집합과 비교한다.

검증 스크립트는 네 model profile, lean/full topology, 기본 `balanced` agent TOML, 단일 공통 반환 계약 참조, 결정적 phase/발신자 전이, security 학습 트리거와 적응형 게이트 정책도 확인한다.

UI 검증은 특정 브라우저 도구를 합격 조건으로 고정하지 않는다. 연결된 UI
도구를 우선 사용하되, 사용할 수 없으면 기존 E2E, production 컴포넌트 런타임
테스트, HTTP·통합 테스트, 사용자 관찰을 요구사항별로 조합한다. `audit` 모드는
미확인 항목을 포함한 진단 보고서 작성을 계속할 수 있지만, 필수 증거가 없는
상태에서 evaluator 승인·완료 전이·커밋을 허용하지 않는다.

## 사용

대상 프로젝트에서 설치 스크립트를 실행한 뒤 Codex를 다시 열면 설치된 custom agent와 skill을 해당 프로젝트 작업 흐름에서 사용할 수 있다.

대표 시작 명령은 다음과 같다.

```text
$orchestrate <작업>
```

프로젝트 초기화 시 보안 path/keyword manifest, 시각 전용 manifest, 일반 구현 역할 override, 커밋 정책, model profile과 topology를 `AGENTS.md`에 기록한다. topology 미지정 기본값은 `lean`이다.

| profile ID | 목적 |
|---|---|
| `balanced` | 기본값. 구현·고위험 판단은 Sol, 규칙 기반 검수·온디맨드 작업은 Terra에 배정한다. |
| `performance` | 구현과 전문 검수에 Sol을 확대한다. |
| `economy` | 데이터 구현·최종 평가·고위험 보안에 Sol을 유지한다. |
| `low-cost` | 전체 역할을 Terra로 수행하되 최종 평가·보안은 xhigh를 유지한다. |

선택하지 않으면 초기화는 `needs-input`으로 종료하며, 기존 프로필은 사용자가 명시적으로 바꾸기 전까지 유지한다. 커밋 정책이 없으면 `ask`로 처리하며, 필수 구현·검증 agent가 재실패하면 완료 경로를 중단한다.

## 범위

이 저장소는 프로젝트 로컬 custom agent·skill 설치를 다룬다. 사용자 홈의 전역 skill 저장소나 Codex 전역 설정 파일, marketplace 설정을 직접 변경하지 않는다.

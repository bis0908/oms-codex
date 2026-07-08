# OMS Codex

## 개요

OMS Codex는 Codex용 custom agent 팀 하네스를 로컬 플러그인으로 배포하기 위한 저장소이다. 플러그인 매니페스트, marketplace 항목, custom agent 정의, skill, 설치 스크립트를 같은 루트에서 관리한다.

## 구조

```text
.
├── .codex-plugin/
│   └── plugin.json
├── .agents/
│   ├── plugins/
│   │   └── marketplace.json
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

Windows PowerShell에서는 symlink 설치를 권장한다.

```text
.\install.ps1 -Symlink
```

marketplace 등록을 건너뛰려면 다음처럼 실행한다.

```text
.\install.ps1 -Symlink -SkipMarketplace
```

macOS, Linux, WSL에서는 다음 명령을 사용한다.

```text
./install.sh --symlink
```

marketplace 등록을 건너뛰려면 다음처럼 실행한다.

```text
./install.sh --symlink --skip-marketplace
```

설치 스크립트는 `install.ps1 -Symlink`, `install.sh --symlink` 실행 흐름에서 필수 경로와 JSON 구문을 먼저 검증한다. Codex CLI가 있으면 `codex plugin marketplace add`로 현재 저장소를 marketplace에 등록한다.

## 검증

기본 검증은 다음 항목을 확인한다.

```text
scripts\verify.ps1
codex plugin marketplace list
```

수동 검증 시에는 `.codex-plugin/plugin.json`과 `.agents/plugins/marketplace.json`을 JSON으로 파싱하고, `install.ps1` 및 `install.sh`의 구문 검사를 실행한다. 설치 후에는 `codex plugin marketplace list`에서 `oms-codex-local` marketplace가 보이는지 확인한다.

## 사용

Codex에서 marketplace를 갱신한 뒤 OMS Codex 플러그인을 설치한다. 설치된 custom agent와 skill은 Codex 작업 흐름에서 사용할 수 있다.

대표 시작 명령은 다음과 같다.

```text
$orchestrate <작업>
```

## 범위

이 저장소는 Codex 로컬 플러그인 배포, custom agent TOML 설치, skill 노출, marketplace 등록을 다룬다. 사용자 홈의 전역 skill 저장소나 Codex 전역 설정 파일을 직접 변경하지 않는다.

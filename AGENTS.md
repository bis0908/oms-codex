# OMS Codex 작업 지침

## 목적

OMS Codex는 Codex에서 사용할 custom agent 팀 하네스를 로컬 플러그인 형태로 제공한다. 이 저장소는 Codex 플러그인 매니페스트, custom agent 정의, skill, 설치 스크립트를 함께 배포하는 것을 목적으로 한다.

## 작업 원칙

- Codex 용어를 기준으로 문서와 설정을 작성한다.
- custom agent 모델은 `gpt-5.5`를 사용한다.
- custom agent effort 값은 `medium` 또는 `high`만 사용한다.
- 설치는 파일 복사보다 symlink 방식을 권장한다. symlink는 저장소 변경사항을 사용자 홈의 Codex agent 설정에 즉시 반영하기 쉽다.
- 변경은 요청 범위 안에서만 수행하고, 관련 없는 Codex 설정은 수정하지 않는다.
- 설치 스크립트는 필수 경로와 JSON 구문을 먼저 검증한 뒤 Codex marketplace 등록과 custom agent 설치를 진행한다.

## 검증

- `.codex-plugin/plugin.json`과 `.agents/plugins/marketplace.json`은 JSON 파서로 검증한다.
- `install.ps1`은 PowerShell Parser로 구문을 검증한다.
- `install.sh`는 가능한 환경에서 `bash -n`으로 구문을 검증한다.
- 설치 후 `codex plugin marketplace list`로 marketplace 등록 상태를 확인한다.
- custom agent TOML이 사용자 홈의 `.codex/agents`에 symlink 또는 copy 방식으로 설치되었는지 확인한다.

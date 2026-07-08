#!/usr/bin/env bash
set -euo pipefail

symlink=0
skip_marketplace=0

usage() {
  cat <<'USAGE'
사용법: ./install.sh [--symlink] [--skip-marketplace]
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --symlink)
      symlink=1
      ;;
    --skip-marketplace)
      skip_marketplace=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "알 수 없는 옵션: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kst_timestamp() {
  TZ=Asia/Seoul date +"%Y%m%d-%H%M%S"
}

require_path() {
  local relative_path="$1"
  local path="$repo/$relative_path"

  if [[ ! -e "$path" ]]; then
    echo "필수 경로가 없습니다: $relative_path" >&2
    exit 1
  fi

  printf '%s\n' "$path"
}

backup_existing_path() {
  local path="$1"

  if [[ ! -e "$path" && ! -L "$path" ]]; then
    return
  fi

  local backup_path="$path.bak.$(kst_timestamp)"
  local counter=1
  while [[ -e "$backup_path" || -L "$backup_path" ]]; do
    backup_path="$path.bak.$(kst_timestamp).$counter"
    counter=$((counter + 1))
  done

  mv "$path" "$backup_path"
  echo "기존 파일을 백업했습니다: $backup_path" >&2
  printf '%s\n' "$backup_path"
}

new_temp_path() {
  local destination="$1"
  local temp_path="$destination.tmp.$$.$(kst_timestamp)"
  local counter=1

  while [[ -e "$temp_path" || -L "$temp_path" ]]; do
    temp_path="$destination.tmp.$$.$(kst_timestamp).$counter"
    counter=$((counter + 1))
  done

  printf '%s\n' "$temp_path"
}

install_agent_file() {
  local source="$1"
  local destination="$2"
  local temp_path
  local backup_path=""

  temp_path="$(new_temp_path "$destination")"

  if [[ "$symlink" -eq 1 ]]; then
    ln -s "$source" "$temp_path"
  else
    cp "$source" "$temp_path"
  fi

  if [[ -e "$destination" || -L "$destination" ]]; then
    backup_path="$(backup_existing_path "$destination")"
  fi

  if ! mv "$temp_path" "$destination"; then
    rm -f "$temp_path"
    if [[ -n "$backup_path" && ! -e "$destination" && ! -L "$destination" && ( -e "$backup_path" || -L "$backup_path" ) ]]; then
      mv "$backup_path" "$destination"
    fi
    return 1
  fi

  if [[ "$symlink" -eq 1 ]]; then
    echo "custom agent symlink를 설치했습니다: $destination"
  else
    echo "custom agent 파일을 복사했습니다: $destination"
  fi
}

plugin_json="$(require_path ".codex-plugin/plugin.json")"
marketplace_json="$(require_path ".agents/plugins/marketplace.json")"
skills_root="$(require_path ".agents/skills")"
source_agents="$(require_path ".codex/agents")"

if command -v python >/dev/null 2>&1; then
  python_cmd="python"
elif command -v python3 >/dev/null 2>&1; then
  python_cmd="python3"
else
  echo "python 또는 python3 명령을 찾지 못했습니다." >&2
  exit 2
fi

"$python_cmd" -m json.tool "$plugin_json" >/dev/null
"$python_cmd" -m json.tool "$marketplace_json" >/dev/null

if [[ "$skip_marketplace" -eq 0 ]]; then
  if command -v codex >/dev/null 2>&1; then
    if ! codex plugin marketplace add "$repo"; then
      echo "codex marketplace 등록 실패: codex plugin marketplace add \"$repo\"" >&2
      exit 1
    fi
  else
    echo "codex CLI를 찾을 수 없어 marketplace 등록을 건너뜁니다."
    echo "수동 실행: codex plugin marketplace add \"$repo\""
  fi
else
  echo "marketplace 등록을 건너뛰었습니다. skill을 사용하려면 나중에 codex plugin marketplace add \"$repo\"를 실행하세요."
fi

if [[ -z "${HOME:-}" ]]; then
  echo "HOME 환경 변수가 설정되어 있지 않습니다." >&2
  exit 1
fi

target_agents="$HOME/.codex/agents"
mkdir -p "$target_agents"

shopt -s nullglob
agent_files=("$source_agents"/*.toml)

if [[ "${#agent_files[@]}" -eq 0 ]]; then
  echo "설치할 custom agent TOML 파일이 없습니다: $source_agents"
  exit 0
fi

for agent_file in "${agent_files[@]}"; do
  target_path="$target_agents/$(basename "$agent_file")"
  install_agent_file "$agent_file" "$target_path"
done

echo "OMS Codex 설치가 완료되었습니다."
echo "Codex를 재시작한 뒤 Plugins 화면에서 OMS Codex를 확인하세요."
echo '시작 예시: $orchestrate <작업>'

#!/usr/bin/env bash
set -euo pipefail

symlink=0
force=0
target=""

usage() {
  cat <<'USAGE'
사용법: ./install.sh --target <프로젝트 경로> [--symlink] [--force]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || { echo "--target 값이 필요합니다." >&2; exit 1; }
      target="$2"
      shift 2
      ;;
    --symlink)
      symlink=1
      shift
      ;;
    --force)
      force=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "알 수 없는 옵션: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ -n "$target" ]] || { echo "--target은 필수입니다." >&2; usage >&2; exit 1; }
[[ -d "$target" ]] || { echo "대상 프로젝트 디렉터리가 없습니다: $target" >&2; exit 1; }

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="$(cd "$target" && pwd)"

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

get_unique_path() {
  local base_path="$1"
  local candidate="$base_path"
  local counter=1

  while [[ -e "$candidate" || -L "$candidate" ]]; do
    candidate="$base_path.$counter"
    counter=$((counter + 1))
  done

  printf '%s\n' "$candidate"
}

backup_existing_path() {
  local path="$1"
  local backup_path

  backup_path="$(get_unique_path "$path.bak.$(kst_timestamp)")"
  mv "$path" "$backup_path"
  echo "기존 경로를 백업했습니다: $backup_path" >&2
  printf '%s\n' "$backup_path"
}

install_project_item() {
  local source="$1"
  local destination="$2"
  local kind="$3"
  local temp_path backup_path=""

  temp_path="$(get_unique_path "$destination.tmp.$$.${RANDOM}.$(kst_timestamp)")"
  if [[ "$symlink" -eq 1 ]]; then
    ln -s "$source" "$temp_path"
  else
    cp -R "$source" "$temp_path"
  fi

  if [[ -e "$destination" || -L "$destination" ]]; then
    backup_path="$(backup_existing_path "$destination")"
  fi

  if ! mv "$temp_path" "$destination"; then
    rm -rf "$temp_path"
    if [[ -n "$backup_path" && ! -e "$destination" && ! -L "$destination" && ( -e "$backup_path" || -L "$backup_path" ) ]]; then
      mv "$backup_path" "$destination"
    fi
    return 1
  fi

  if [[ "$symlink" -eq 1 ]]; then
    echo "$kind symlink 설치 완료: $destination"
  else
    echo "$kind 복사 설치 완료: $destination"
  fi
}

skills_root="$(require_path '.agents/skills')"
source_agents="$(require_path '.codex/agents')"
version_file="$(require_path 'VERSION')"
version="$(tr -d '\r\n' < "$version_file")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION 형식이 올바르지 않습니다: $version" >&2; exit 1; }
target_agents="$target/.codex/agents"
target_skills="$target/.agents/skills"

shopt -s nullglob
agent_files=("$source_agents"/*.toml)
skill_directories=("$skills_root"/*/)
shopt -u nullglob

[[ "${#agent_files[@]}" -gt 0 ]] || { echo "설치할 custom agent TOML 파일이 없습니다: $source_agents" >&2; exit 1; }
[[ "${#skill_directories[@]}" -gt 0 ]] || { echo "설치할 skill 디렉터리가 없습니다: $skills_root" >&2; exit 1; }

conflicts=()
for agent_file in "${agent_files[@]}"; do
  destination="$target_agents/$(basename "$agent_file")"
  [[ -e "$destination" || -L "$destination" ]] && conflicts+=("$destination")
done
for skill_directory in "${skill_directories[@]}"; do
  skill_name="$(basename "$skill_directory")"
  destination="$target_skills/$skill_name"
  [[ -e "$destination" || -L "$destination" ]] && conflicts+=("$destination")
done

if [[ "${#conflicts[@]}" -gt 0 && "$force" -eq 0 ]]; then
  echo "기존 프로젝트 설정을 덮어쓰지 않습니다. --force로 백업 후 교체할 수 있습니다:" >&2
  printf '%s\n' "${conflicts[@]}" >&2
  exit 1
fi

mkdir -p "$target_agents" "$target_skills"
for agent_file in "${agent_files[@]}"; do
  install_project_item "$agent_file" "$target_agents/$(basename "$agent_file")" "custom agent"
done
for skill_directory in "${skill_directories[@]}"; do
  skill_name="$(basename "$skill_directory")"
  install_project_item "$skill_directory" "$target_skills/$skill_name" "skill"
done

echo "OMS Codex $version 프로젝트 로컬 설치가 완료되었습니다: $target"
echo "기본 복사 설치 파일은 대상 프로젝트에서 직접 커스터마이즈할 수 있습니다."
echo '시작 예시: $orchestrate <작업>'

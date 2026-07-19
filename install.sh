#!/usr/bin/env bash
set -euo pipefail

symlink=0
force=0
target=""
topology="lean"

usage() {
  cat <<'USAGE'
사용법: ./install.sh --target <프로젝트 경로> [--symlink] [--force] [--topology lean|full]
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
    --topology)
      [[ $# -ge 2 ]] || { echo "--topology 값이 필요합니다." >&2; exit 1; }
      topology="$2"
      shift 2
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
[[ "$topology" == "lean" || "$topology" == "full" ]] || { echo "--topology는 lean 또는 full이어야 합니다: $topology" >&2; exit 1; }
[[ ! -L "$target" ]] || { echo "대상 프로젝트 root symlink는 허용하지 않습니다: $target" >&2; exit 1; }

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
target="$(cd "$target" && pwd -P)"
if [[ "$symlink" -eq 1 && (
  "$target" == "$repo" ||
  "$target" == "$repo/"* ||
  "$repo" == "$target/"*
) ]]; then
  echo "symlink 설치에서는 원본 저장소와 대상 프로젝트가 같거나 서로 중첩될 수 없습니다." >&2
  exit 1
fi

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

assert_safe_target_path() {
  local path="$1"
  local relative current segment

  if [[ "$path" != "$target" && "$path" != "$target/"* ]]; then
    echo "설치 대상 경로가 대상 프로젝트 범위를 벗어납니다: $path" >&2
    return 1
  fi

  current="$target"
  [[ ! -L "$current" ]] || {
    echo "설치 대상 경로의 symlink를 허용하지 않습니다: $current" >&2
    return 1
  }
  relative="${path#"$target"}"
  relative="${relative#/}"
  while [[ -n "$relative" ]]; do
    segment="${relative%%/*}"
    if [[ "$relative" == */* ]]; then
      relative="${relative#*/}"
    else
      relative=""
    fi
    current="$current/$segment"
    if [[ -L "$current" ]]; then
      echo "설치 대상 경로의 symlink를 허용하지 않습니다: $current" >&2
      return 1
    fi
    [[ -e "$current" ]] || break
  done
}

remove_install_path() {
  local path="$1"

  if ! assert_safe_target_path "$(dirname "$path")"; then
    return 1
  fi
  if [[ -L "$path" ]]; then
    rm -f "$path"
  elif [[ -d "$path" ]]; then
    rm -rf "$path"
  elif [[ -e "$path" ]]; then
    rm -f "$path"
  fi
}

backup_existing_path() {
  local path="$1"
  local backup_path

  backup_path="$(get_unique_path "$path.bak.$(kst_timestamp)")"
  mv "$path" "$backup_path"
  echo "기존 경로를 백업했습니다: $backup_path" >&2
  printf '%s\n' "$backup_path"
}

skills_root="$(require_path '.agents/skills')"
source_agents="$(require_path '.codex/agents')"
topology_path="$(require_path '.agents/skills/init-project/references/topology-profiles.json')"
version_file="$(require_path 'VERSION')"
version="$(tr -d '\r\n' < "$version_file")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION 형식이 올바르지 않습니다: $version" >&2; exit 1; }
target_agents="$target/.codex/agents"
target_skills="$target/.agents/skills"

if command -v python3 >/dev/null 2>&1; then
  python_cmd="python3"
elif command -v python >/dev/null 2>&1 && python -c 'import sys; raise SystemExit(sys.version_info.major != 3)'; then
  python_cmd="python"
else
  echo "topology manifest를 읽으려면 Python 3이 필요합니다." >&2
  exit 1
fi

if ! topology_agents="$("$python_cmd" - "$topology_path" "$topology" <<'PY'
import json
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
topology_name = sys.argv[2]
try:
    data = json.loads(path.read_text(encoding="utf-8"))
    agents = data["topologies"][topology_name]["default_agents"]
except (OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
    print(f"topology manifest를 읽을 수 없습니다: {exc}", file=sys.stderr)
    raise SystemExit(1)
if (
    not isinstance(agents, list)
    or not agents
    or any(not isinstance(name, str) or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name) for name in agents)
    or len(agents) != len(set(agents))
):
    print(f"topology의 default_agents가 올바르지 않습니다: {topology_name}", file=sys.stderr)
    raise SystemExit(1)
print("\n".join(agents))
PY
)"; then
  exit 1
fi

shopt -s nullglob
agent_names=()
while IFS= read -r agent_name; do
  agent_names+=("$agent_name")
done <<< "$topology_agents"
agent_files=()
for agent_name in "${agent_names[@]}"; do
  agent_file="$source_agents/$agent_name.toml"
  [[ -f "$agent_file" ]] || { echo "topology가 참조하는 custom agent가 없습니다: $agent_name" >&2; exit 1; }
  agent_files+=("$agent_file")
done
skill_directories=("$skills_root"/*/)
shopt -u nullglob

[[ "${#agent_files[@]}" -gt 0 ]] || { echo "설치할 custom agent TOML 파일이 없습니다: $source_agents" >&2; exit 1; }
[[ "${#skill_directories[@]}" -gt 0 ]] || { echo "설치할 skill 디렉터리가 없습니다: $skills_root" >&2; exit 1; }

assert_safe_target_path "$target_agents"
assert_safe_target_path "$target_skills"

sources=()
destinations=()
kinds=()
for agent_file in "${agent_files[@]}"; do
  sources+=("$agent_file")
  destinations+=("$target_agents/$(basename "$agent_file")")
  kinds+=("custom agent")
done
for skill_directory in "${skill_directories[@]}"; do
  skill_name="$(basename "$skill_directory")"
  sources+=("$skill_directory")
  destinations+=("$target_skills/$skill_name")
  kinds+=("skill")
done

conflicts=()
for destination in "${destinations[@]}"; do
  assert_safe_target_path "$destination"
  [[ -e "$destination" || -L "$destination" ]] && conflicts+=("$destination")
done

if [[ "${#conflicts[@]}" -gt 0 && "$force" -eq 0 ]]; then
  echo "기존 프로젝트 설정을 덮어쓰지 않습니다. --force로 백업 후 교체할 수 있습니다:" >&2
  printf '%s\n' "${conflicts[@]}" >&2
  exit 1
fi

mkdir -p "$target_agents" "$target_skills"
assert_safe_target_path "$target_agents"
assert_safe_target_path "$target_skills"

temp_paths=()
backup_paths=()
committed_count=0

cleanup_staged() {
  local temp_path

  set +e
  for temp_path in "${temp_paths[@]}"; do
    remove_install_path "$temp_path"
  done
  set -e
}

rollback_install() {
  local index destination backup_path

  set +e
  for ((index = committed_count - 1; index >= 0; index--)); do
    destination="${destinations[$index]}"
    backup_path="${backup_paths[$index]}"
    remove_install_path "$destination"
    if [[ -n "$backup_path" && ( -e "$backup_path" || -L "$backup_path" ) ]]; then
      mv "$backup_path" "$destination"
    fi
  done
  for temp_path in "${temp_paths[@]}"; do
    remove_install_path "$temp_path"
  done
  set -e
}

for ((index = 0; index < ${#sources[@]}; index++)); do
  source_path="${sources[$index]}"
  destination="${destinations[$index]}"
  temp_path="$(get_unique_path "$destination.tmp.$$.${RANDOM}.$(kst_timestamp)")"
  temp_paths+=("$temp_path")
  backup_paths+=("")
  assert_safe_target_path "$(dirname "$temp_path")"
  if [[ "$symlink" -eq 1 ]]; then
    if ! ln -s "$source_path" "$temp_path"; then
      cleanup_staged
      exit 1
    fi
  elif ! cp -R "$source_path" "$temp_path"; then
    cleanup_staged
    exit 1
  fi
done

for ((index = 0; index < ${#sources[@]}; index++)); do
  destination="${destinations[$index]}"
  temp_path="${temp_paths[$index]}"
  assert_safe_target_path "$destination"
  backup_path=""
  if [[ "$force" -eq 1 && ( -e "$destination" || -L "$destination" ) ]]; then
    if ! backup_path="$(backup_existing_path "$destination")"; then
      rollback_install
      exit 1
    fi
    backup_paths[$index]="$backup_path"
  elif [[ -e "$destination" || -L "$destination" ]]; then
    echo "설치 중 대상 경로가 생성되어 중단합니다: $destination" >&2
    rollback_install
    exit 1
  fi

  if ! mv "$temp_path" "$destination"; then
    if [[ -n "$backup_path" && ! -e "$destination" && ! -L "$destination" && ( -e "$backup_path" || -L "$backup_path" ) ]]; then
      mv "$backup_path" "$destination"
      backup_paths[$index]=""
    fi
    rollback_install
    exit 1
  fi
  committed_count=$((committed_count + 1))

  if [[ "$symlink" -eq 1 ]]; then
    echo "${kinds[$index]} symlink 설치 완료: $destination"
  else
    echo "${kinds[$index]} 복사 설치 완료: $destination"
  fi
done

echo "OMS Codex $version 프로젝트 로컬 설치가 완료되었습니다: $target"
echo "설치 topology: $topology (${#agent_files[@]} agents)"
echo "기본 복사 설치 파일은 대상 프로젝트에서 직접 커스터마이즈할 수 있습니다."
echo '시작 예시: $orchestrate <작업>'

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
errors=()

expected_agent_model() {
  case "$1" in
    bug-fixer.toml|compound-curator.toml|data-layer.toml|design-reviewer.toml|evaluator.toml|page-builder.toml|plan-auditor.toml|refactor-specialist.toml|security-auditor.toml|tdd-agent.toml) printf '%s\n' "gpt-5.6-sol" ;;
    compound-learner.toml|qa-guard.toml) printf '%s\n' "gpt-5.6-terra" ;;
    milestone-tracker.toml|session-archivist.toml) printf '%s\n' "gpt-5.6-luna" ;;
    *) return 1 ;;
  esac
}

expected_agent_effort() {
  case "$1" in
    bug-fixer.toml) printf '%s\n' "high" ;;
    compound-curator.toml) printf '%s\n' "high" ;;
    compound-learner.toml) printf '%s\n' "medium" ;;
    data-layer.toml) printf '%s\n' "high" ;;
    design-reviewer.toml) printf '%s\n' "high" ;;
    evaluator.toml) printf '%s\n' "xhigh" ;;
    milestone-tracker.toml) printf '%s\n' "medium" ;;
    page-builder.toml) printf '%s\n' "high" ;;
    plan-auditor.toml) printf '%s\n' "high" ;;
    qa-guard.toml) printf '%s\n' "high" ;;
    refactor-specialist.toml) printf '%s\n' "high" ;;
    security-auditor.toml) printf '%s\n' "xhigh" ;;
    session-archivist.toml) printf '%s\n' "medium" ;;
    tdd-agent.toml) printf '%s\n' "high" ;;
    *) return 1 ;;
  esac
}

add_error() {
  errors+=("$1")
}

require_path() {
  local path="$1"
  local label="${path#$ROOT/}"

  if [ ! -e "$path" ]; then
    add_error "필수 경로 없음: $label"
  fi
}

require_text() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  local relative="${path#$ROOT/}"

  if [ ! -f "$path" ]; then
    add_error "$label 검사 실패: 파일 없음: $relative"
    return
  fi

  if ! grep -Eq "$pattern" "$path"; then
    add_error "$label 텍스트 없음: $relative"
  fi
}

for path in \
  "$ROOT/AGENTS.md" \
  "$ROOT/README.md" \
  "$ROOT/install.ps1" \
  "$ROOT/install.sh" \
  "$ROOT/.codex-plugin/plugin.json" \
  "$ROOT/.agents/plugins/marketplace.json" \
  "$ROOT/.agents/skills" \
  "$ROOT/.codex/agents"; do
  require_path "$path"
done

if command -v python >/dev/null 2>&1; then
  python_cmd="python"
elif command -v python3 >/dev/null 2>&1; then
  python_cmd="python3"
else
  echo "python 또는 python3 명령을 찾지 못했습니다" >&2
  exit 2
fi

"$python_cmd" -m json.tool "$ROOT/.codex-plugin/plugin.json" >/dev/null 2>&1 || add_error "plugin.json JSON 파싱 실패"
"$python_cmd" -m json.tool "$ROOT/.agents/plugins/marketplace.json" >/dev/null 2>&1 || add_error "marketplace.json JSON 파싱 실패"

set +e
json_field_errors="$(
  "$python_cmd" - "$ROOT" <<'PY' 2>&1
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
errors = []

try:
    plugin = json.loads((root / ".codex-plugin/plugin.json").read_text(encoding="utf-8"))
    if plugin.get("name") != "oms-codex":
        errors.append(f"plugin.json name 불일치: {plugin.get('name')}")
    if plugin.get("skills") != "./.agents/skills/":
        errors.append(f"plugin.json skills 불일치: {plugin.get('skills')}")
except Exception as exc:
    errors.append(f"plugin.json 필드 검사 실패: {exc}")

try:
    marketplace = json.loads((root / ".agents/plugins/marketplace.json").read_text(encoding="utf-8"))
    plugins = marketplace.get("plugins", [])
    entry = next(
        (
            item
            for item in plugins
            if isinstance(item, dict) and item.get("name") == "oms-codex"
        ),
        None,
    )

    if entry is None:
        errors.append("marketplace.json oms-codex entry 없음")
    else:
        source = entry.get("source", {})
        if not isinstance(source, dict):
            source = {}
        if source.get("source") != "local":
            errors.append(f"marketplace.json source.source 불일치: {source.get('source')}")
        if source.get("path") != "./":
            errors.append(f"marketplace.json source.path 불일치: {source.get('path')}")
except Exception as exc:
    errors.append(f"marketplace.json 필드 검사 실패: {exc}")

try:
    import tomllib
except Exception as exc:
    errors.append(f"tomllib import 실패: {exc}")
else:
    for path in sorted((root / ".codex/agents").glob("*.toml")):
        try:
            tomllib.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            errors.append(f"{path}: {exc}")

if errors:
    print("\n".join(errors))
    sys.exit(1)
PY
)"
json_field_status=$?
set -e

if [ "$json_field_status" -ne 0 ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && add_error "$line"
  done <<< "$json_field_errors"
fi

if [ -d "$ROOT/.codex/agents" ]; then
  agent_count="$(find "$ROOT/.codex/agents" -maxdepth 1 -type f -name '*.toml' | wc -l | tr -d '[:space:]')"
else
  agent_count="0"
fi

if [ "$agent_count" != "14" ]; then
  add_error ".codex/agents TOML 파일 수 불일치: $agent_count"
fi

shopt -s nullglob
agent_files=("$ROOT"/.codex/agents/*.toml)
shopt -u nullglob

for expected_file in \
  bug-fixer.toml \
  compound-curator.toml \
  compound-learner.toml \
  data-layer.toml \
  design-reviewer.toml \
  evaluator.toml \
  milestone-tracker.toml \
  page-builder.toml \
  plan-auditor.toml \
  qa-guard.toml \
  refactor-specialist.toml \
  security-auditor.toml \
  session-archivist.toml \
  tdd-agent.toml; do
  require_path "$ROOT/.codex/agents/$expected_file"
done

set +e
contract_output="$("$python_cmd" "$ROOT/scripts/verify-agent-contracts.py" "$ROOT" 2>&1)"
contract_status=$?
set -e
if [ "$contract_status" -ne 0 ]; then
  add_error "agent 의미 계약 검증 실패:
$contract_output"
fi

for file in "${agent_files[@]}"; do
  base_name="$(basename "$file")"
  agent_name="${base_name%.toml}"
  require_text "$file" "^name[[:space:]]*=[[:space:]]*\"$agent_name\"" "agent name"
  require_text "$file" '^description[[:space:]]*=' "agent description"
  require_text "$file" '^developer_instructions[[:space:]]*=' "agent developer_instructions"
  if expected_model="$(expected_agent_model "$base_name")"; then
    expected_model_pattern="${expected_model//./\\.}"
    require_text "$file" "^model[[:space:]]*=[[:space:]]*\"$expected_model_pattern\"[[:space:]]*$" "agent model"
  else
    add_error "알 수 없는 custom agent 파일: $base_name"
  fi
  if expected_effort="$(expected_agent_effort "$base_name")"; then
    require_text "$file" "^model_reasoning_effort[[:space:]]*=[[:space:]]*\"$expected_effort\"[[:space:]]*$" "agent model_reasoning_effort"
  else
    add_error "알 수 없는 custom agent 파일: $base_name"
  fi

  for field in name description developer_instructions model model_reasoning_effort; do
    field_count="$(grep -Ec "^$field[[:space:]]*=" "$file")"
    [ "$field_count" = "1" ] || add_error "$base_name 필드 개수 불일치: $field=$field_count"
  done
done

skill_count="$(find "$ROOT/.agents/skills" -name SKILL.md | wc -l | tr -d '[:space:]')"
[ "$skill_count" = "13" ] || add_error "SKILL.md 파일 수 불일치: $skill_count"
while IFS= read -r skill_file; do
  require_text "$skill_file" '^---' "skill frontmatter start"
  require_text "$skill_file" '^name:[[:space:]]*.+' "skill name"
  require_text "$skill_file" '^description:[[:space:]]*.+' "skill description"
done < <(find "$ROOT/.agents/skills" -name SKILL.md)

legacy_pattern='Agent\(|Skill\(|TaskCreate|TaskList|TaskUpdate|run_in_background|CLAUDE\.md|~/.claude|\.claude/settings\.json|\.claude-plugin|gpt-5\.4|gpt-5\.4-mini|model:\s*opus|opus'

set +e
if command -v rg >/dev/null 2>&1; then
  legacy_output="$(rg --hidden "$legacy_pattern" "$ROOT" --glob '!scripts/verify.*' --glob '!docs/superpowers/specs/**' 2>&1)"
else
  grep_legacy_pattern='Agent\(|Skill\(|TaskCreate|TaskList|TaskUpdate|run_in_background|CLAUDE\.md|~/.claude|\.claude/settings\.json|\.claude-plugin|gpt-5\.4|gpt-5\.4-mini|model:[[:space:]]*opus|opus'
  legacy_output="$(grep -RInE --exclude='verify.ps1' --exclude='verify.sh' --exclude-dir='.git' --exclude-dir='docs/superpowers/specs' "$grep_legacy_pattern" "$ROOT" 2>&1)"
fi
legacy_status=$?
set -e

if [ "$legacy_status" -eq 0 ]; then
  add_error "legacy 토큰 잔존:
$legacy_output"
elif [ "$legacy_status" -gt 1 ]; then
  add_error "legacy scan 실패: $legacy_output"
fi

set +e
if command -v rg >/dev/null 2>&1; then
  forbidden_output="$(rg '~[/\\]\.agents[/\\]skills|\$HOME[/\\]\.agents[/\\]skills|\$env:USERPROFILE.*\.agents\\skills|\.codex[/\\]config\.toml' "$ROOT/install.ps1" "$ROOT/install.sh" 2>&1)"
else
  forbidden_output="$(grep -nE '~[/\\]\.agents[/\\]skills|\$HOME[/\\]\.agents[/\\]skills|\$env:USERPROFILE.*\.agents\\skills|\.codex[/\\]config\.toml' "$ROOT/install.ps1" "$ROOT/install.sh" 2>&1)"
fi
forbidden_status=$?
set -e

if [ "$forbidden_status" -eq 0 ]; then
  add_error "installer 금지 대상 참조 잔존:
$forbidden_output"
elif [ "$forbidden_status" -gt 1 ]; then
  add_error "installer 금지 대상 검사 실패: $forbidden_output"
fi

require_text "$ROOT/README.md" 'install\.ps1 -Symlink' "README install.ps1 -Symlink"
require_text "$ROOT/README.md" 'install\.sh --symlink' "README install.sh --symlink"
require_text "$ROOT/install.ps1" 'codex plugin marketplace add' "install.ps1 marketplace"
require_text "$ROOT/install.sh" 'codex plugin marketplace add' "install.sh marketplace"

if [ "${#errors[@]}" -gt 0 ]; then
  printf '%s\n' "${errors[@]}" >&2
  exit 1
fi

echo "검증 통과: $ROOT"
exit 0

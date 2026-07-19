#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
WORKSPACE="$ROOT/_workspace"
mkdir -p "$WORKSPACE"
test_root="$(mktemp -d "$WORKSPACE/installer-safety.XXXXXX")"
target="$test_root/target"
external="$test_root/external"
junction="$target/.codex"

cleanup() {
  if [[ -L "$junction" ]]; then
    rm -f "$junction"
  fi
  if [[ "$test_root" == "$WORKSPACE/installer-safety."* && -d "$test_root" ]]; then
    rm -rf "$test_root"
  fi
}
trap cleanup EXIT

mkdir -p "$target" "$external"
ln -s "$external" "$junction"
if bash "$ROOT/install.sh" --target "$target" >/dev/null 2>&1; then
  echo "대상 하위 symlink 설치가 거부되지 않았습니다." >&2
  exit 1
fi
if find "$external" -mindepth 1 -print -quit | grep -q .; then
  echo "거부된 symlink 대상에 파일이 생성되었습니다." >&2
  exit 1
fi
rm -f "$junction"

if bash "$ROOT/install.sh" --target "$ROOT" --symlink >/dev/null 2>&1; then
  echo "원본-대상 중첩 symlink 설치가 거부되지 않았습니다." >&2
  exit 1
fi

echo "Bash 설치기 경로 안전성 검증 통과"

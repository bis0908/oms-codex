#!/usr/bin/env python3
"""프로젝트 로컬 custom agent TOML에 승인된 실행 프로필을 안전하게 적용한다."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import tempfile
import tomllib


SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
PROFILE_PATH = SCRIPT_DIR / "agent-profiles.json"
MODEL_FIELDS = ("model", "model_reasoning_effort")
ALLOWED_MODELS = {"gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"}
ALLOWED_EFFORTS = {"low", "medium", "high", "xhigh", "max"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-agents", required=True, type=pathlib.Path)
    parser.add_argument("--target-agents", required=True, type=pathlib.Path)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--check", action="store_true", help="쓰기 없이 선택 프로필 일치 여부만 확인")
    return parser.parse_args()


def load_profiles() -> dict[str, dict[str, dict[str, str]]]:
    try:
        data = json.loads(PROFILE_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"프로필 설정을 읽을 수 없습니다: {exc}") from exc

    profiles = data.get("profiles")
    if not isinstance(profiles, dict) or not profiles:
        raise ValueError("프로필 설정에 profiles가 없습니다")

    result: dict[str, dict[str, dict[str, str]]] = {}
    expected_names: set[str] | None = None
    for profile_name, profile_data in profiles.items():
        if not isinstance(profile_data, dict) or not isinstance(profile_data.get("agents"), dict):
            raise ValueError(f"프로필 형식이 올바르지 않습니다: {profile_name}")
        agents = profile_data["agents"]
        names = set(agents)
        if expected_names is None:
            expected_names = names
        elif names != expected_names:
            raise ValueError(f"프로필 agent 목록이 일치하지 않습니다: {profile_name}")
        for agent_name, values in agents.items():
            if not isinstance(values, dict) or any(not isinstance(values.get(field), str) for field in MODEL_FIELDS):
                raise ValueError(f"프로필 agent 값이 올바르지 않습니다: {profile_name}/{agent_name}")
            if values["model"] not in ALLOWED_MODELS:
                raise ValueError(f"프로필 model 값이 허용되지 않습니다: {profile_name}/{agent_name}")
            if values["model_reasoning_effort"] not in ALLOWED_EFFORTS:
                raise ValueError(f"프로필 effort 값이 허용되지 않습니다: {profile_name}/{agent_name}")
        result[profile_name] = agents
    return result


def normalize_without_model_fields(text: str) -> str:
    normalized = text.replace("\r\n", "\n")
    for field in MODEL_FIELDS:
        normalized, count = re.subn(rf"(?m)^{field}\s*=.*(?:\n|$)", "", normalized)
        if count != 1:
            raise ValueError(f"{field} 필드가 정확히 하나여야 합니다: {count}")
    return normalized


def replace_model_fields(text: str, values: dict[str, str]) -> str:
    updated = text
    for field in MODEL_FIELDS:
        updated, count = re.subn(
            rf'(?m)^{field}\s*=\s*"[^"]*"\s*$',
            f'{field} = "{values[field]}"',
            updated,
        )
        if count != 1:
            raise ValueError(f"{field} 필드를 안전하게 교체할 수 없습니다: {count}")
    return updated


def load_toml(path: pathlib.Path, expected_name: str) -> str:
    try:
        text = path.read_text(encoding="utf-8")
        data = tomllib.loads(text)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise ValueError(f"TOML을 읽을 수 없습니다: {path}: {exc}") from exc
    if data.get("name") != expected_name:
        raise ValueError(f"agent name이 파일명과 다릅니다: {path}")
    if any(field not in data for field in MODEL_FIELDS):
        raise ValueError(f"필수 모델 필드가 없습니다: {path}")
    return text


def atomic_write(path: pathlib.Path, text: str) -> None:
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        os.replace(temp_name, path)
    except Exception:
        pathlib.Path(temp_name).unlink(missing_ok=True)
        raise


def main() -> int:
    args = parse_args()
    profiles = load_profiles()
    if args.profile not in profiles:
        raise ValueError(f"알 수 없는 프로필: {args.profile}. 선택값: {', '.join(sorted(profiles))}")
    if not args.source_agents.is_dir() or not args.target_agents.is_dir():
        raise ValueError("source-agents와 target-agents는 모두 존재하는 디렉터리여야 합니다")

    selected = profiles[args.profile]
    expected_names = set(selected)
    source_names = {path.stem for path in args.source_agents.glob("*.toml")}
    target_names = {path.stem for path in args.target_agents.glob("*.toml")}
    if source_names != expected_names or not target_names or not target_names <= expected_names:
        raise ValueError(
            "agent 목록이 프로필과 일치하지 않습니다: "
            f"source missing={sorted(expected_names - source_names)}, source extra={sorted(source_names - expected_names)}, "
            f"target unsupported={sorted(target_names - expected_names)}"
        )

    updates: list[tuple[pathlib.Path, str]] = []
    mismatches: list[str] = []
    for agent_name in sorted(target_names):
        source_path = args.source_agents / f"{agent_name}.toml"
        target_path = args.target_agents / f"{agent_name}.toml"
        source_text = load_toml(source_path, agent_name)
        target_text = load_toml(target_path, agent_name)
        if normalize_without_model_fields(source_text) != normalize_without_model_fields(target_text):
            mismatches.append(agent_name)
            continue
        updated_text = replace_model_fields(target_text, selected[agent_name])
        if args.check:
            target_values = tomllib.loads(target_text)
            if any(target_values[field] != selected[agent_name][field] for field in MODEL_FIELDS):
                mismatches.append(agent_name)
        elif updated_text != target_text:
            updates.append((target_path, updated_text))

    if mismatches:
        raise ValueError(
            "사용자 변경 또는 선택 프로필 불일치로 처리할 수 없는 agent: "
            f"{', '.join(sorted(set(mismatches)))}"
        )
    if args.check:
        print(f"프로필 일치 확인: {args.profile} ({len(target_names)} agents)")
        return 0

    for path, text in updates:
        atomic_write(path, text)
    print(f"프로필 적용 완료: {args.profile} (변경 {len(updates)} / {len(target_names)} agents)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as exc:
        raise SystemExit(f"프로필 적용 실패: {exc}")

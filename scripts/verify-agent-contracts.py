from __future__ import annotations

import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib


ROOT = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[1]

AGENT_SKILLS = {
    "bug-fixer": "bugfix",
    "compound-curator": "compound",
    "compound-learner": "compound",
    "data-layer": None,
    "design-reviewer": "design-review",
    "evaluator": "evaluate",
    "milestone-tracker": "milestone-track",
    "page-builder": None,
    "plan-auditor": "plan-audit",
    "qa-guard": "qa",
    "refactor-specialist": "refactor",
    "security-auditor": "security-audit",
    "session-archivist": "session-archive",
    "tdd-agent": "tdd",
}

PROFILE_PATH = pathlib.Path(".agents/skills/init-project/references/agent-profiles.json")
PROFILE_HELPER_PATH = pathlib.Path(".agents/skills/init-project/references/apply-agent-profile.py")
PROFILE_NAMES = {"performance", "economy", "low-cost"}
ALLOWED_MODELS = {"gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"}
ALLOWED_EFFORTS = {"medium", "high", "xhigh"}

COMMON_RETURN_KEYS = (
    "결과:",
    "완료 항목:",
    "완료 task_id:",
    "미완료 항목:",
    "검증:",
    "미검증 항목:",
    "확인 필요:",
    "다음 단계:",
    "마일스톤:",
    "단계:",
    "에이전트:",
    "request_id:",
)

ROLE_EXTENSIONS = {
    "bug-fixer": ("재현 확인:", "재발 조건:", "evaluator 필요 여부:"),
    "compound-curator": ("무손실 검증:", "acknowledgement:", "acknowledged ID:"),
    "compound-learner": ("학습 트리거:", "acknowledgement:", "acknowledged ID:"),
    "data-layer": ("위험 클래스:", "migration 롤백·백업 근거:"),
    "design-reviewer": ("디자인 검수 결과:", "보고서:", "호출 ID:"),
    "evaluator": ("검증 결과:", "보고서:", "호출 ID:", "blocking 항목:"),
    "milestone-tracker": ("상태 전이:", "작업 유형:", "사용자 검증:"),
    "page-builder": ("연결 지점:", "UI 상태:"),
    "plan-auditor": ("정합성 결과:", "분자/분모:", "보고서:"),
    "qa-guard": ("QA 검증 결과:", "보고서:", "호출 ID:", "검증 부채:"),
    "refactor-specialist": ("기준선:", "보존 확인:", "공개 계약 diff:"),
    "security-auditor": ("보안 감사 결과:", "보고서:", "잔여 위험:", "학습 신호:"),
    "session-archivist": ("민감정보 점검:", "redaction:", "파일명 충돌 처리:"),
    "tdd-agent": ("Red 상태:", "격리 방식:", "cleanup 검증:"),
}

SKILL_EXTENSIONS = {
    "bugfix": ("재현 확인:", "재발 조건:", "evaluator 필요 여부:"),
    "compound": ("학습 트리거:", "무손실 검증:", "acknowledgement:", "acknowledged ID:"),
    "design-review": ("디자인 검수 결과:", "보고서:", "호출 ID:"),
    "evaluate": ("검증 결과:", "보고서:", "호출 ID:", "blocking 항목:"),
    "milestone-track": ("상태 전이:", "작업 유형:", "사용자 검증:"),
    "plan-audit": ("정합성 결과:", "분자/분모:", "보고서:"),
    "qa": ("QA 검증 결과:", "보고서:", "호출 ID:", "검증 부채:"),
    "refactor": ("기준선:", "보존 확인:", "공개 계약 diff:"),
    "security-audit": ("보안 감사 결과:", "보고서:", "잔여 위험:", "학습 신호:"),
    "session-archive": ("민감정보 점검:", "redaction:", "파일명 충돌 처리:"),
    "tdd": ("Red 상태:", "격리 방식:", "cleanup 검증:"),
}

REQUIRED_TEXT = {
    ".agents/skills/orchestrate/SKILL.md": (
        "필수 design, QA, security, evaluator가 1회 재시도 후에도 실행 실패하면 fail-closed",
        "compound-curator",
        "red-confirmed",
        "red-blocked",
        "사용자 검증: 통과",
        "commit-local",
    ),
    ".agents/skills/orchestrate/references/durable-work.md": (
        "acknowledgement: done",
        "acknowledged ID",
        "pending -> inflight -> done",
        "writer는 오케스트레이터 하나",
        "queue 갱신을 직렬화",
        "compare-and-swap",
        "stale snapshot",
    ),
    ".agents/skills/orchestrate/references/pipeline-gates.md": (
        "plan-remediation",
        "auth/session: QA -> security(필수) -> evaluator",
    ),
    ".agents/skills/compound/SKILL.md": ("security-repeat", "compound-curator"),
    ".agents/skills/tdd/SKILL.md": ("red-confirmed", "red-blocked"),
    ".agents/skills/milestone-track/SKILL.md": ("사용자 검증", "phase-5-complete", "plan-remediation"),
    "AGENTS.md": ("커밋 정책은 `ask`", "시각 전용 경로가 없다"),
}

FORBIDDEN_ACTIVE_TEXT = (
    "재실패 시 해당 결과 없이 진행",
    "실 dev DB 사용, mock 금지",
    "실 dev DB 사용, Mock 금지",
    "dev DB 기존 데이터 사용",
    "compound-learner` 에이전트를 직접 호출한다(인자: 트랙 `compound-curate`",
    "단계: <progress-update>",
)

SCENARIO_TOKENS = {
    "NEG-01": ("blocked", "evaluator", "커밋"),
    "NEG-02": ("security-auditor", "쿠키"),
    "NEG-03": ("사용자 검증: 통과", "needs-input"),
    "NEG-04": ("red-blocked", "Green"),
    "NEG-05": ("security-repeat", "docs/compound/security/"),
    "NEG-06": ("pending", "timeout"),
    "NEG-07": ("request_id", "재전송"),
    "NEG-08": ("phase", "발신자"),
    "NEG-09": ("commit-local", "커밋"),
    "NEG-10": ("request_id", "정확한"),
    "NEG-11": ("evaluator", "클릭"),
    "NEG-12": ("data-layer", "임의 배정"),
    "NEG-13": ("대상 ID", "pending"),
    "NEG-14": ("inconclusive", "blocking"),
}


def fail(message: str) -> None:
    print(message, file=sys.stderr)


def load_profile_policy(errors: list[str]) -> dict[str, tuple[str, str, str | None]]:
    profile_path = ROOT / PROFILE_PATH
    try:
        data = json.loads(profile_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"agent profile JSON 파싱 실패: {PROFILE_PATH}: {exc}")
        return {}

    if data.get("schema_version") != 1:
        errors.append("agent profile schema_version 불일치")
    if data.get("default_profile") != "performance":
        errors.append("agent profile 기본값은 performance여야 합니다")

    profiles = data.get("profiles")
    if not isinstance(profiles, dict) or set(profiles) != PROFILE_NAMES:
        errors.append(
            "agent profile 목록 불일치: "
            f"expected={sorted(PROFILE_NAMES)}, actual={sorted(profiles) if isinstance(profiles, dict) else profiles!r}"
        )
        return {}

    expected_agents = set(AGENT_SKILLS)
    parsed: dict[str, dict[str, dict[str, str]]] = {}
    for profile_name, profile_data in profiles.items():
        if not isinstance(profile_data, dict):
            errors.append(f"agent profile 형식 불일치: {profile_name}")
            continue
        agents = profile_data.get("agents")
        if not isinstance(agents, dict) or set(agents) != expected_agents:
            errors.append(
                f"agent profile agent 목록 불일치: {profile_name}: "
                f"missing={sorted(expected_agents - set(agents) if isinstance(agents, dict) else expected_agents)}, "
                f"extra={sorted(set(agents) - expected_agents) if isinstance(agents, dict) else []}"
            )
            continue
        parsed[profile_name] = agents
        for agent_name, values in agents.items():
            if not isinstance(values, dict):
                errors.append(f"agent profile 값 형식 불일치: {profile_name}/{agent_name}")
                continue
            model = values.get("model")
            effort = values.get("model_reasoning_effort")
            if model not in ALLOWED_MODELS:
                errors.append(f"agent profile model 불일치: {profile_name}/{agent_name}: {model!r}")
            if effort not in ALLOWED_EFFORTS:
                errors.append(f"agent profile effort 불일치: {profile_name}/{agent_name}: {effort!r}")

    performance = parsed.get("performance")
    if performance is None:
        return {}
    return {
        agent_name: (
            performance[agent_name]["model"],
            performance[agent_name]["model_reasoning_effort"],
            AGENT_SKILLS[agent_name],
        )
        for agent_name in sorted(expected_agents)
    }


def verify_profile_application(errors: list[str]) -> None:
    helper_path = ROOT / PROFILE_HELPER_PATH
    profile_path = ROOT / PROFILE_PATH
    source_agents = ROOT / ".codex" / "agents"
    if not helper_path.is_file() or not profile_path.is_file() or not source_agents.is_dir():
        errors.append("agent profile 적용 fixture를 준비할 수 없습니다")
        return

    try:
        profiles = json.loads(profile_path.read_text(encoding="utf-8"))["profiles"]
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
        errors.append(f"agent profile fixture 설정 읽기 실패: {exc}")
        return

    with tempfile.TemporaryDirectory(prefix="oms-codex-profile-") as temp_dir:
        target_agents = pathlib.Path(temp_dir) / "agents"
        shutil.copytree(source_agents, target_agents)
        for profile_name in ("performance", "economy", "low-cost"):
            command = [
                sys.executable,
                str(helper_path),
                "--source-agents",
                str(source_agents),
                "--target-agents",
                str(target_agents),
                "--profile",
                profile_name,
            ]
            result = subprocess.run(command, capture_output=True, text=True, check=False)
            if result.returncode != 0:
                errors.append(f"agent profile 적용 실패: {profile_name}: {result.stderr.strip()}")
                continue

            check_result = subprocess.run(command + ["--check"], capture_output=True, text=True, check=False)
            if check_result.returncode != 0:
                errors.append(f"agent profile 확인 실패: {profile_name}: {check_result.stderr.strip()}")
                continue

            for agent_name, values in profiles[profile_name]["agents"].items():
                data = tomllib.loads((target_agents / f"{agent_name}.toml").read_text(encoding="utf-8"))
                if data.get("model") != values["model"] or data.get("model_reasoning_effort") != values["model_reasoning_effort"]:
                    errors.append(f"agent profile 적용값 불일치: {profile_name}/{agent_name}")

        changed_path = target_agents / "page-builder.toml"
        changed_text = changed_path.read_text(encoding="utf-8") + "\n# 사용자 변경\n"
        changed_path.write_text(changed_text, encoding="utf-8")
        conflict_result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
        )
        if conflict_result.returncode == 0 or changed_path.read_text(encoding="utf-8") != changed_text:
            errors.append("agent profile 사용자 변경 충돌 보류 검증 실패")


def main() -> int:
    errors: list[str] = []
    policy = load_profile_policy(errors)
    agents_dir = ROOT / ".codex" / "agents"
    paths = sorted(agents_dir.glob("*.toml"))
    names = {path.stem for path in paths}

    if names != set(policy):
        errors.append(
            "agent 목록 불일치: "
            f"missing={sorted(set(policy) - names)}, extra={sorted(names - set(policy))}"
        )

    for path in paths:
        try:
            data = tomllib.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            errors.append(f"TOML 파싱 실패: {path.relative_to(ROOT)}: {exc}")
            continue

        name = data.get("name")
        if name != path.stem:
            errors.append(f"agent name 불일치: {path.name}: {name!r}")
            continue
        if name not in policy:
            continue

        expected_model, expected_effort, skill = policy[name]
        if data.get("model") != expected_model:
            errors.append(f"{path.name} model 불일치: {data.get('model')!r}")
        if data.get("model_reasoning_effort") != expected_effort:
            errors.append(f"{path.name} effort 불일치: {data.get('model_reasoning_effort')!r}")

        instructions = data.get("developer_instructions", "")
        for key in COMMON_RETURN_KEYS:
            if not re.search(rf"(?m)^{re.escape(key)}", instructions):
                errors.append(f"{path.name} 공통 반환 키 누락: {key}")
        for key in ROLE_EXTENSIONS[name]:
            if not re.search(rf"(?m)^{re.escape(key)}", instructions):
                errors.append(f"{path.name} 역할별 반환 키 누락: {key}")

        if skill:
            skill_path = ROOT / ".agents" / "skills" / skill / "SKILL.md"
            if not skill_path.is_file():
                errors.append(f"{path.name} 참조 skill 없음: {skill}")
            if skill not in instructions:
                errors.append(f"{path.name} developer_instructions에 기준 skill 누락: {skill}")

    for relative, needles in REQUIRED_TEXT.items():
        path = ROOT / relative
        if not path.is_file():
            errors.append(f"필수 계약 파일 없음: {relative}")
            continue
        text = path.read_text(encoding="utf-8")
        for needle in needles:
            if needle not in text:
                errors.append(f"필수 계약 텍스트 없음: {relative}: {needle}")

    agent_skill_names = sorted({skill for _, _, skill in policy.values() if skill})
    for skill in agent_skill_names:
        path = ROOT / ".agents" / "skills" / skill / "SKILL.md"
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for key in COMMON_RETURN_KEYS:
            if key not in text:
                errors.append(f"{skill} skill 공통 반환 키 누락: {key}")
        for key in SKILL_EXTENSIONS[skill]:
            if key not in text:
                errors.append(f"{skill} skill 역할별 반환 키 누락: {key}")

    active_paths = list((ROOT / ".codex" / "agents").glob("*.toml"))
    active_paths += list((ROOT / ".agents" / "skills").glob("**/SKILL.md"))
    active_paths += list((ROOT / ".agents" / "skills" / "orchestrate" / "references").glob("*.md"))
    for path in active_paths:
        text = path.read_text(encoding="utf-8")
        for forbidden in FORBIDDEN_ACTIVE_TEXT:
            if forbidden in text:
                errors.append(f"stale 계약 잔존: {path.relative_to(ROOT)}: {forbidden}")

    orchestrate_lines = len(
        (ROOT / ".agents" / "skills" / "orchestrate" / "SKILL.md")
        .read_text(encoding="utf-8")
        .splitlines()
    )
    if orchestrate_lines >= 500:
        errors.append(f"orchestrate SKILL.md 500줄 미만 규칙 위반: {orchestrate_lines}")

    tracker = tomllib.loads(
        (agents_dir / "milestone-tracker.toml").read_text(encoding="utf-8")
    )["developer_instructions"]
    tracker_skill = (
        ROOT / ".agents" / "skills" / "milestone-track" / "SKILL.md"
    ).read_text(encoding="utf-8")
    transition_pairs = {
        "phase-3-impl": ("page-builder", "data-layer", "orchestrator"),
        "phase-4-eval": ("evaluator",),
        "phase-5-complete": ("orchestrator",),
        "plan-remediation": ("orchestrator",),
    }
    for phase, senders in transition_pairs.items():
        for source_name, source_text in (("agent", tracker), ("skill", tracker_skill)):
            matching_lines = [line for line in source_text.splitlines() if phase in line]
            if not matching_lines:
                errors.append(f"milestone-tracker {source_name} 전이 누락: {phase}")
                continue
            joined = "\n".join(matching_lines)
            for sender in senders:
                if sender not in joined:
                    errors.append(
                        f"milestone-tracker {source_name} phase/발신자 조합 누락: {phase} <- {sender}"
                    )

    scenarios = (ROOT / ".agents" / "skills" / "orchestrate" / "references" / "test-scenarios.md")
    if scenarios.is_file():
        scenario_text = scenarios.read_text(encoding="utf-8")
        if "| ID | Given | When | Then |" not in scenario_text:
            errors.append("시나리오 Given/When/Then 표 헤더 누락")
        rows: dict[str, list[str]] = {}
        for line in scenario_text.splitlines():
            match = re.match(r"^\| ((?:POS|NEG)-\d{2}) \|", line)
            if match:
                rows.setdefault(match.group(1), []).append(line)
                if line.count("|") != 5:
                    errors.append(f"시나리오 표 열 수 불일치: {match.group(1)}")
        expected_ids = {f"POS-{number:02d}" for number in range(1, 9)} | {
            f"NEG-{number:02d}" for number in range(1, 15)
        }
        if set(rows) != expected_ids:
            errors.append(
                f"시나리오 ID 집합 불일치: missing={sorted(expected_ids - set(rows))}, "
                f"extra={sorted(set(rows) - expected_ids)}"
            )
        for scenario_id, lines in rows.items():
            if len(lines) != 1:
                errors.append(f"시나리오 ID 중복: {scenario_id}={len(lines)}")
        for scenario_id, needles in SCENARIO_TOKENS.items():
            if scenario_id not in rows:
                continue
            row = rows[scenario_id][0]
            for needle in needles:
                if needle not in row:
                    errors.append(f"시나리오 핵심 결과 누락: {scenario_id}: {needle}")

    verify_profile_application(errors)

    if errors:
        for error in errors:
            fail(error)
        return 1
    print(f"agent 계약 검증 통과: {len(paths)} agents")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

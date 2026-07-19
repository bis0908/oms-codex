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
    "compound-curator": "compound",
    "compound-learner": "compound",
    "data-layer": "tdd",
    "design-reviewer": "design-review",
    "evaluator": "evaluate",
    "page-builder": None,
    "plan-auditor": "plan-audit",
    "qa-guard": "qa",
    "security-auditor": "security-audit",
}

PROFILE_PATH = pathlib.Path(".agents/skills/init-project/references/agent-profiles.json")
PROFILE_HELPER_PATH = pathlib.Path(".agents/skills/init-project/references/apply-agent-profile.py")
TOPOLOGY_PATH = pathlib.Path(".agents/skills/init-project/references/topology-profiles.json")
PROFILE_NAMES = {"balanced", "performance", "economy", "low-cost"}
ALLOWED_MODELS = {"gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"}
ALLOWED_EFFORTS = {"low", "medium", "high", "xhigh", "max"}

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
    "compound-curator": ("무손실 검증", "acknowledgement", "acknowledged ID"),
    "compound-learner": ("학습 트리거", "acknowledgement", "acknowledged ID"),
    "data-layer": ("Red 상태", "격리 방식", "위험 클래스", "migration 롤백·백업 근거"),
    "design-reviewer": ("디자인 검수 결과", "보고서", "호출 ID"),
    "evaluator": ("검증 결과", "보고서", "호출 ID", "blocking 항목"),
    "page-builder": ("연결 지점", "UI 상태"),
    "plan-auditor": ("정합성 결과", "분자/분모", "보고서"),
    "qa-guard": ("QA 검증 결과", "보고서", "호출 ID", "검증 부채"),
    "security-auditor": ("보안 감사 결과", "보고서", "잔여 위험", "학습 신호"),
}

REQUIRED_TEXT = {
    ".agents/skills/orchestrate/SKILL.md": (
        "호출한 필수 design, QA, security, evaluator가 1회 재시도 후에도 실행 실패하면 fail-closed",
        "compound-curator",
        "red-confirmed",
        "red-blocked",
        "사용자 검증: 통과",
        "commit-local",
        "ui-verification-fallback.md",
        "UI 검증 모드",
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
        "`auth | payment | migration | destructive` 위험 클래스는 항상 `full`",
        "감사 모드 진단 연속성",
        "구현 완료로",
        "전이하지 않는다",
    ),
    ".agents/skills/orchestrate/references/agent-contract.md": (
        "UI 검증 모드",
        "선호 UI 검증 수단",
        "대체 검증 허용",
        "completion 모드의 필수 미검증",
    ),
    ".agents/skills/orchestrate/references/ui-verification-fallback.md": (
        "`completion`",
        "`audit`",
        "증거 등가표",
        "완료 전이와 커밋을 금지",
    ),
    ".agents/skills/design-review/SKILL.md": (
        "검증 수단 독립",
        "UI 검증 모드",
        "completed + 수정필요",
        "구현 완료 승인이 아니다",
    ),
    ".agents/skills/evaluate/SKILL.md": (
        "UI 런타임·폴백 스모크 체크",
        "등가 런타임 증거",
        "completed + 수정필요",
        "blocking 항목을 approved로 바꾸지 않는다",
    ),
    ".codex/agents/design-reviewer.toml": (
        "UI 작업이거나 디자인 레퍼런스가 있을 때만 호출",
        "변경 의미, diff 범위, 재검증 가능성",
        "completion 모드",
        "audit 모드",
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
    "POS-01": ("폴백", "등가 증거", "사용자 검증", "커밋"),
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
    "NEG-14": ("inconclusive", "blocking", "감사 모드", "커밋"),
}


def fail(message: str) -> None:
    print(message, file=sys.stderr)


def verify_common_contract(errors: list[str]) -> None:
    contract_path = ROOT / ".agents" / "skills" / "orchestrate" / "references" / "agent-contract.md"
    try:
        contract = contract_path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"공통 반환 계약 읽기 실패: {exc}")
        return
    for key in COMMON_RETURN_KEYS:
        if key not in contract:
            errors.append(f"공통 반환 계약 키 누락: {key}")


def load_profile_policy(errors: list[str]) -> dict[str, tuple[str, str, str | None]]:
    profile_path = ROOT / PROFILE_PATH
    try:
        data = json.loads(profile_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"agent profile JSON 파싱 실패: {PROFILE_PATH}: {exc}")
        return {}

    if data.get("schema_version") != 2:
        errors.append("agent profile schema_version 불일치")
    if data.get("default_profile") != "balanced":
        errors.append("agent profile 기본값은 balanced여야 합니다")

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

    default_profile = parsed.get("balanced")
    if default_profile is None:
        return {}
    return {
        agent_name: (
            default_profile[agent_name]["model"],
            default_profile[agent_name]["model_reasoning_effort"],
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
        for profile_name in ("balanced", "performance", "economy", "low-cost"):
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


def verify_topologies(errors: list[str], expected_agents: set[str]) -> None:
    try:
        data = json.loads((ROOT / TOPOLOGY_PATH).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"topology profile JSON 파싱 실패: {TOPOLOGY_PATH}: {exc}")
        return
    if data.get("schema_version") != 1 or data.get("default_topology") != "lean":
        errors.append("topology profile 기본 설정 불일치")
        return
    topologies = data.get("topologies")
    if not isinstance(topologies, dict) or set(topologies) != {"lean", "full"}:
        errors.append("topology profile 목록 불일치")
        return
    lean = topologies["lean"]
    full = topologies["full"]
    name_pattern = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")

    def validate_agent_list(topology_name: str, key: str) -> list[str]:
        value = topologies[topology_name].get(key)
        if (
            not isinstance(value, list)
            or any(not isinstance(name, str) or not name_pattern.fullmatch(name) for name in value)
            or len(value) != len(set(value))
        ):
            errors.append(f"topology agent 목록 형식 불일치: {topology_name}/{key}")
            return []
        return value

    lean_default_list = validate_agent_list("lean", "default_agents")
    lean_optional_list = validate_agent_list("lean", "optional_agents")
    full_default_list = validate_agent_list("full", "default_agents")
    full_optional_list = validate_agent_list("full", "optional_agents")
    lean_default = set(lean_default_list)
    lean_optional = set(lean_optional_list)
    full_default = set(full_default_list)
    if lean_default & lean_optional or lean_default | lean_optional != expected_agents:
        errors.append("lean topology agent 분류 불일치")
    if full_default != expected_agents or full_optional_list != []:
        errors.append("full topology agent 분류 불일치")
    required_modes = {"bugfix", "milestone-track", "refactor", "session-archive", "tdd"}
    for name, topology in topologies.items():
        if set(topology.get("direct_skill_modes", [])) != required_modes:
            errors.append(f"topology direct skill mode 불일치: {name}")


def verify_transition_validator(errors: list[str]) -> None:
    validator = ROOT / "scripts" / "validate-milestone-transition.py"
    if not validator.is_file():
        errors.append("마일스톤 전이 검증기 누락")
        return
    valid_payload = {
        "request_id": "verify-transition",
        "milestone": "M1",
        "phase": "phase-5-complete",
        "sender": "orchestrator",
        "work_type": "UI",
        "risk_class": "ui",
        "task_ids": ["T1"],
        "checklist_ids": ["C1"],
        "evaluation_result": "approved",
        "evaluation_report": "_workspace/eval_m1.md",
        "gate_profile": "full",
        "required_gates": ["design", "qa", "evaluator"],
        "gate_results": {"design": "approved", "qa": "approved", "evaluator": "approved"},
        "user_verification": "통과",
    }
    invalid_payload = dict(valid_payload, user_verification="누락")
    empty_gates_payload = dict(valid_payload, required_gates=[], gate_results={})
    missing_gate_payload = dict(valid_payload, gate_results={"design": "approved", "qa": "approved"})
    security_omission_payload = dict(
        valid_payload,
        work_type="non-UI",
        risk_class="auth",
        required_gates=["qa", "evaluator"],
        gate_results={"qa": "approved", "evaluator": "approved"},
    )
    ui_lean_payload = dict(
        valid_payload,
        gate_profile="lean",
        required_gates=["qa"],
        gate_results={"qa": "approved"},
    )
    with tempfile.TemporaryDirectory(prefix="oms-codex-transition-") as temp_dir:
        temp_path = pathlib.Path(temp_dir)
        valid_path = temp_path / "valid.json"
        invalid_path = temp_path / "invalid.json"
        empty_gates_path = temp_path / "empty-gates.json"
        missing_gate_path = temp_path / "missing-gate.json"
        security_omission_path = temp_path / "security-omission.json"
        ui_lean_path = temp_path / "ui-lean.json"
        valid_path.write_text(json.dumps(valid_payload), encoding="utf-8")
        invalid_path.write_text(json.dumps(invalid_payload), encoding="utf-8")
        empty_gates_path.write_text(json.dumps(empty_gates_payload), encoding="utf-8")
        missing_gate_path.write_text(json.dumps(missing_gate_payload), encoding="utf-8")
        security_omission_path.write_text(json.dumps(security_omission_payload), encoding="utf-8")
        ui_lean_path.write_text(json.dumps(ui_lean_payload), encoding="utf-8")
        valid_result = subprocess.run([sys.executable, str(validator), str(valid_path)], capture_output=True, text=True)
        invalid_result = subprocess.run([sys.executable, str(validator), str(invalid_path)], capture_output=True, text=True)
        empty_gates_result = subprocess.run(
            [sys.executable, str(validator), str(empty_gates_path)], capture_output=True, text=True
        )
        missing_gate_result = subprocess.run(
            [sys.executable, str(validator), str(missing_gate_path)], capture_output=True, text=True
        )
        security_omission_result = subprocess.run(
            [sys.executable, str(validator), str(security_omission_path)], capture_output=True, text=True
        )
        ui_lean_result = subprocess.run(
            [sys.executable, str(validator), str(ui_lean_path)], capture_output=True, text=True
        )
        if valid_result.returncode != 0:
            errors.append(f"유효 마일스톤 전이 검증 실패: {valid_result.stdout} {valid_result.stderr}")
        if invalid_result.returncode == 0 or "사용자 검증" not in invalid_result.stdout:
            errors.append("무효 마일스톤 전이 거부 실패")
        if empty_gates_result.returncode == 0 or "required_gates" not in empty_gates_result.stdout:
            errors.append("빈 필수 gate 전이 거부 실패")
        if missing_gate_result.returncode == 0 or "정확히 일치" not in missing_gate_result.stdout:
            errors.append("필수 gate 일부 누락 전이 거부 실패")
        if security_omission_result.returncode == 0 or "security gate" not in security_omission_result.stdout:
            errors.append("보안 고위험 security gate 누락 전이 거부 실패")
        if ui_lean_result.returncode == 0 or "UI 완료에는 full" not in ui_lean_result.stdout:
            errors.append("UI lean 완료 전이 거부 실패")


def main() -> int:
    errors: list[str] = []
    verify_common_contract(errors)
    policy = load_profile_policy(errors)
    verify_topologies(errors, set(policy))
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

        if name == "design-reviewer":
            features = data.get("features")
            preferred_ui_features = ("computer_use", "browser_use", "in_app_browser")
            if not isinstance(features, dict):
                errors.append("design-reviewer.toml 선호 UI features 누락")
            else:
                for feature in preferred_ui_features:
                    if features.get(feature) is not True:
                        errors.append(f"design-reviewer.toml 선호 UI feature 비활성: {feature}")

        expected_model, expected_effort, skill = policy[name]
        if data.get("model") != expected_model:
            errors.append(f"{path.name} model 불일치: {data.get('model')!r}")
        if data.get("model_reasoning_effort") != expected_effort:
            errors.append(f"{path.name} effort 불일치: {data.get('model_reasoning_effort')!r}")

        instructions = data.get("developer_instructions", "")
        if "agent-contract.md" not in instructions:
            errors.append(f"{path.name} 공통 계약 참조 누락")
        if "## 공통 반환 형식" in instructions or "## 표준 반환" in instructions:
            errors.append(f"{path.name} 공통 반환 계약 중복")
        for key in ROLE_EXTENSIONS[name]:
            if key not in instructions:
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
        for source_name, source_text in (("skill", tracker_skill),):
            matching_lines = [line for line in source_text.splitlines() if phase in line]
            if not matching_lines:
                errors.append(f"milestone-track {source_name} 전이 누락: {phase}")
                continue
            joined = "\n".join(matching_lines)
            for sender in senders:
                if sender not in joined:
                    errors.append(
                        f"milestone-track {source_name} phase/발신자 조합 누락: {phase} <- {sender}"
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
    verify_transition_validator(errors)

    if errors:
        for error in errors:
            fail(error)
        return 1
    print(f"agent 계약 검증 통과: {len(paths)} agents")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

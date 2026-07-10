from __future__ import annotations

import pathlib
import re
import sys
import tomllib


ROOT = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[1]

POLICY = {
    "bug-fixer": ("gpt-5.6-sol", "high", "bugfix"),
    "compound-curator": ("gpt-5.6-sol", "high", "compound"),
    "compound-learner": ("gpt-5.6-terra", "medium", "compound"),
    "data-layer": ("gpt-5.6-sol", "high", None),
    "design-reviewer": ("gpt-5.6-sol", "high", "design-review"),
    "evaluator": ("gpt-5.6-sol", "xhigh", "evaluate"),
    "milestone-tracker": ("gpt-5.6-luna", "medium", "milestone-track"),
    "page-builder": ("gpt-5.6-sol", "high", None),
    "plan-auditor": ("gpt-5.6-sol", "high", "plan-audit"),
    "qa-guard": ("gpt-5.6-terra", "high", "qa"),
    "refactor-specialist": ("gpt-5.6-sol", "high", "refactor"),
    "security-auditor": ("gpt-5.6-sol", "xhigh", "security-audit"),
    "session-archivist": ("gpt-5.6-luna", "medium", "session-archive"),
    "tdd-agent": ("gpt-5.6-sol", "high", "tdd"),
}

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


def main() -> int:
    errors: list[str] = []
    agents_dir = ROOT / ".codex" / "agents"
    paths = sorted(agents_dir.glob("*.toml"))
    names = {path.stem for path in paths}

    if names != set(POLICY):
        errors.append(
            "agent 목록 불일치: "
            f"missing={sorted(set(POLICY) - names)}, extra={sorted(names - set(POLICY))}"
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
        if name not in POLICY:
            continue

        expected_model, expected_effort, skill = POLICY[name]
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

    agent_skill_names = sorted({skill for _, _, skill in POLICY.values() if skill})
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

    if errors:
        for error in errors:
            fail(error)
        return 1
    print(f"agent 계약 검증 통과: {len(paths)} agents")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

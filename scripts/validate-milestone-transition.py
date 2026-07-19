#!/usr/bin/env python3
"""마일스톤 상태 전이 신호를 결정적으로 검증하고 정규화한다."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys


ALLOWED_SENDERS = {
    "phase-3-impl": {"page-builder", "data-layer", "orchestrator"},
    "phase-4-eval": {"evaluator"},
    "phase-5-complete": {"orchestrator"},
    "plan-remediation": {"orchestrator"},
}

ALLOWED_GATE_PROFILES = {"direct", "lean", "full"}
ALLOWED_GATES = {"deterministic", "design", "qa", "security", "evaluator"}
ALLOWED_RISK_CLASSES = {"none", "ui", "data", "auth", "payment", "migration", "destructive"}
SECURITY_REQUIRED_RISKS = {"auth", "payment", "migration", "destructive"}
GATE_PROFILE_MINIMUMS = {
    "direct": {"deterministic"},
    "lean": {"qa"},
    "full": {"qa", "evaluator"},
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("request", type=pathlib.Path, help="전이 요청 JSON 경로")
    return parser.parse_args()


def require_nonempty_string(payload: dict[str, object], key: str, errors: list[str]) -> None:
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        errors.append(f"필수 문자열 누락: {key}")


def require_id_list(payload: dict[str, object], key: str, errors: list[str]) -> None:
    value = payload.get(key)
    if not isinstance(value, list) or not value or any(not isinstance(item, str) or not item.strip() for item in value):
        errors.append(f"비어 있지 않은 문자열 목록 필요: {key}")
        return
    if len(value) != len(set(value)):
        errors.append(f"중복 ID 금지: {key}")


def validate(payload: dict[str, object]) -> list[str]:
    errors: list[str] = []
    for key in ("request_id", "milestone", "phase", "sender", "work_type", "risk_class"):
        require_nonempty_string(payload, key, errors)
    require_id_list(payload, "task_ids", errors)
    require_id_list(payload, "checklist_ids", errors)

    phase = payload.get("phase")
    sender = payload.get("sender")
    if phase not in ALLOWED_SENDERS:
        errors.append(f"허용되지 않은 phase: {phase!r}")
    elif sender not in ALLOWED_SENDERS[phase]:
        errors.append(f"허용되지 않은 phase/sender 조합: {phase} <- {sender}")

    work_type = payload.get("work_type")
    if work_type not in {"UI", "non-UI"}:
        errors.append(f"허용되지 않은 work_type: {work_type!r}")
    risk_class = payload.get("risk_class")
    if risk_class not in ALLOWED_RISK_CLASSES:
        errors.append(f"허용되지 않은 risk_class: {risk_class!r}")
    if risk_class == "ui" and work_type != "UI":
        errors.append("ui 위험 클래스에는 UI work_type이 필요합니다")

    if phase == "phase-4-eval":
        if payload.get("evaluation_result") not in {"approved", "수정필요"}:
            errors.append("evaluation_result는 approved 또는 수정필요여야 합니다")
        require_nonempty_string(payload, "evaluation_report", errors)

    if phase == "phase-5-complete":
        gate_profile = payload.get("gate_profile")
        if gate_profile not in ALLOWED_GATE_PROFILES:
            errors.append(f"허용되지 않은 gate_profile: {gate_profile!r}")
        required_gates = payload.get("required_gates")
        if (
            not isinstance(required_gates, list)
            or not required_gates
            or any(not isinstance(gate, str) or gate not in ALLOWED_GATES for gate in required_gates)
            or len(required_gates) != len(set(required_gates))
        ):
            errors.append("required_gates는 중복 없는 비어 있지 않은 허용 gate 목록이어야 합니다")
            required_gate_set: set[str] = set()
        else:
            required_gate_set = set(required_gates)
        if gate_profile in GATE_PROFILE_MINIMUMS:
            missing_minimums = GATE_PROFILE_MINIMUMS[gate_profile] - required_gate_set
            if missing_minimums:
                errors.append(f"gate_profile 필수 gate 누락: {sorted(missing_minimums)}")
        if work_type == "UI":
            if gate_profile != "full":
                errors.append("UI 완료에는 full gate_profile이 필요합니다")
            if "design" not in required_gate_set:
                errors.append("UI 완료에는 design gate가 필요합니다")
        if risk_class in SECURITY_REQUIRED_RISKS:
            if gate_profile != "full":
                errors.append(f"{risk_class} 위험 클래스에는 full gate_profile이 필요합니다")
            if "security" not in required_gate_set:
                errors.append(f"{risk_class} 위험 클래스에는 security gate가 필요합니다")
        if "evaluator" in required_gate_set:
            if payload.get("evaluation_result") != "approved":
                errors.append("evaluator gate 완료에는 approved가 필요합니다")
            require_nonempty_string(payload, "evaluation_report", errors)
        gate_results = payload.get("gate_results")
        if not isinstance(gate_results, dict):
            errors.append("gate_results는 object여야 합니다")
        else:
            result_gate_set = set(gate_results)
            if result_gate_set != required_gate_set:
                errors.append(
                    "gate_results 키는 required_gates와 정확히 일치해야 합니다: "
                    f"missing={sorted(required_gate_set - result_gate_set)}, "
                    f"extra={sorted(result_gate_set - required_gate_set)}"
                )
            if any(value != "approved" for value in gate_results.values()):
                errors.append("최종 완료에는 모든 필수 gate의 approved가 필요합니다")
        if work_type == "UI" and payload.get("user_verification") != "통과":
            errors.append("UI 최종 완료에는 사용자 검증 통과가 필요합니다")

    if phase == "plan-remediation":
        if payload.get("user_approval") != "통과":
            errors.append("계획 보완에는 사용자 승인 통과가 필요합니다")
        require_nonempty_string(payload, "approval_evidence", errors)
        require_nonempty_string(payload, "plan_audit_report", errors)

    return errors


def main() -> int:
    args = parse_args()
    try:
        payload = json.loads(args.request.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"요청 JSON을 읽을 수 없습니다: {exc}") from exc
    if not isinstance(payload, dict):
        raise ValueError("요청 JSON 최상위 값은 object여야 합니다")

    errors = validate(payload)
    result = {
        "valid": not errors,
        "request_id": payload.get("request_id"),
        "phase": payload.get("phase"),
        "sender": payload.get("sender"),
        "errors": errors,
    }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if not errors else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as exc:
        print(f"전이 검증 실패: {exc}", file=sys.stderr)
        raise SystemExit(2)

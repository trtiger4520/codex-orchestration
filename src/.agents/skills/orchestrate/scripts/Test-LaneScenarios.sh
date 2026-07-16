#!/usr/bin/env bash

set -euo pipefail
script_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
scenario_file=${1:-"$script_root/../references/lane-scenarios.v1.json"}
schema_file=${2:-"$script_root/../references/lane-evaluation-result.schema.json"}
command -v python3 >/dev/null 2>&1 || { printf '%s\n' 'python3 is required' >&2; exit 1; }

python3 - "$scenario_file" "$schema_file" <<'PYTHON'
import json
import sys
from pathlib import Path

matrix = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
lanes = {"single-agent", "plan-light", "orchestrate-heavy"}
roles = {"orchestration_planner", "orchestration_explorer", "orchestration_implementer", "orchestration_verifier"}
required_ids = {"known-dto-field", "unfamiliar-login-trace", "known-crud-edits", "large-ci-log", "independent-verification-only", "ef-core-migration", "authentication-policy", "ten-doc-wording", "cohesive-feature-unit", "security-read-only-analysis", "architecture-read-only-analysis", "explicit-two-writer-workflow"}
assert matrix.get("version") == "1.1" and len(matrix.get("scenarios", [])) >= 12
ids = set()
for scenario in matrix["scenarios"]:
    assert scenario["id"] not in ids and scenario["prompt"] and scenario["allowed_lanes"]
    ids.add(scenario["id"])
    assert set(scenario["allowed_lanes"]) <= lanes
    required = set(scenario["required_roles"])
    allowed = set(scenario["allowed_roles"])
    forbidden = set(scenario["forbidden_roles"])
    assert required | allowed | forbidden <= roles
    assert required <= allowed and not allowed & forbidden
    limits = scenario["max_role_counts"]
    assert isinstance(limits, dict)
    assert set(limits) == allowed
    assert all(isinstance(count, int) and not isinstance(count, bool) and count >= 1 for count in limits.values())
    assert limits.get("orchestration_implementer", 1) <= 2
    assert all(role == "orchestration_implementer" or count == 1 for role, count in limits.items())
    assert scenario["max_subagents"] >= len(required)
    if "plan-light" in scenario["allowed_lanes"]:
        assert scenario["max_subagents"] <= 1
assert required_ids <= ids

scenarios_by_id = {scenario["id"]: scenario for scenario in matrix["scenarios"]}


def evaluation_errors(scenario, result):
    errors = []
    counts = {}
    agents = result.get("delegated_agents")
    if not isinstance(agents, list):
        return ["schema"]
    for agent in agents:
        if not isinstance(agent, dict) or set(agent) != {"role", "count"}:
            return ["schema"]
        role, count = agent["role"], agent["count"]
        if role not in roles or not isinstance(count, int) or isinstance(count, bool) or count < 1:
            return ["schema"]
        if (role == "orchestration_implementer" and count > 2) or (role != "orchestration_implementer" and count != 1):
            return ["schema"]
        if role in counts:
            errors.append("duplicate-role")
            continue
        counts[role] = count
    total = sum(counts.values())
    if result["lane"] not in scenario["allowed_lanes"]:
        errors.append("lane")
    if result["approval_required"] != scenario["approval_required"]:
        errors.append("approval")
    if result["lane"] == "single-agent" and total != 0:
        errors.append("single-agent-count")
    if result["lane"] == "plan-light" and total > 1:
        errors.append("plan-light-count")
    if total > scenario["max_subagents"]:
        errors.append("max-subagents")
    if not set(scenario["required_roles"]) <= set(counts):
        errors.append("required-role")
    for role, count in counts.items():
        if role not in scenario["allowed_roles"] or role in scenario["forbidden_roles"]:
            errors.append("disallowed-role")
        elif count > scenario["max_role_counts"][role]:
            errors.append("role-limit")
    return errors


def assert_case(name, scenario, result, expected=None):
    errors = evaluation_errors(scenario, result)
    if expected is None and errors:
        raise AssertionError(f"{name} unexpectedly failed: {errors}")
    if expected is not None and expected not in errors:
        raise AssertionError(f"{name} did not report {expected}: {errors}")


assert_case("two implementers count as two", scenarios_by_id["explicit-two-writer-workflow"], {
    "lane": "orchestrate-heavy", "delegated_agents": [
        {"role": "orchestration_planner", "count": 1},
        {"role": "orchestration_implementer", "count": 2},
        {"role": "orchestration_verifier", "count": 1},
    ], "approval_required": True,
})
assert_case("more than two implementers", scenarios_by_id["explicit-two-writer-workflow"], {
    "lane": "orchestrate-heavy", "delegated_agents": [
        {"role": "orchestration_planner", "count": 1},
        {"role": "orchestration_implementer", "count": 3},
        {"role": "orchestration_verifier", "count": 1},
    ], "approval_required": True,
}, "schema")
assert_case("high-risk writer limit", scenarios_by_id["ef-core-migration"], {
    "lane": "orchestrate-heavy", "delegated_agents": [
        {"role": "orchestration_planner", "count": 1},
        {"role": "orchestration_implementer", "count": 2},
        {"role": "orchestration_verifier", "count": 1},
    ], "approval_required": True,
}, "role-limit")
assert_case("duplicate role", scenarios_by_id["explicit-two-writer-workflow"], {
    "lane": "orchestrate-heavy", "delegated_agents": [
        {"role": "orchestration_planner", "count": 1},
        {"role": "orchestration_implementer", "count": 1},
        {"role": "orchestration_implementer", "count": 2},
        {"role": "orchestration_verifier", "count": 1},
    ], "approval_required": True,
}, "duplicate-role")
assert_case("plan-light count limit", {
    "allowed_lanes": ["plan-light"], "required_roles": [],
    "allowed_roles": ["orchestration_explorer", "orchestration_implementer"], "forbidden_roles": [],
    "max_role_counts": {"orchestration_explorer": 1, "orchestration_implementer": 1},
    "max_subagents": 2, "approval_required": False,
}, {
    "lane": "plan-light", "delegated_agents": [
        {"role": "orchestration_explorer", "count": 1},
        {"role": "orchestration_implementer", "count": 1},
    ], "approval_required": False,
}, "plan-light-count")
print(f"PASS: {len(matrix['scenarios'])} lane scenarios")
PYTHON

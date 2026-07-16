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
required_ids = {"known-dto-field", "unfamiliar-login-trace", "known-crud-edits", "large-ci-log", "independent-verification-only", "ef-core-migration", "authentication-policy", "ten-doc-wording", "cohesive-feature-unit"}
assert matrix.get("version") == "1.0" and len(matrix.get("scenarios", [])) >= 9
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
    assert scenario["max_subagents"] >= len(required)
    if "plan-light" in scenario["allowed_lanes"]:
        assert scenario["max_subagents"] <= 1
assert required_ids <= ids
print(f"PASS: {len(matrix['scenarios'])} lane scenarios")
PYTHON

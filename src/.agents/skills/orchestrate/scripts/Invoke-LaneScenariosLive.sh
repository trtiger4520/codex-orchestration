#!/usr/bin/env bash

set -euo pipefail
script_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
scenario_file="$script_root/../references/lane-scenarios.v1.json"
result_schema="$script_root/../references/lane-evaluation-result.schema.json"
agents_file="$script_root/../../../../AGENTS.md"
model=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --scenario-file) scenario_file=$2; shift 2 ;;
        --result-schema) result_schema=$2; shift 2 ;;
        --agents-file) agents_file=$2; shift 2 ;;
        --model) model=$2; shift 2 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; exit 1 ;;
    esac
done

command -v codex >/dev/null 2>&1 || { printf '%s\n' 'Codex CLI is required for live lane evaluation' >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf '%s\n' 'python3 is required for live lane evaluation' >&2; exit 1; }
temp_root=$(mktemp -d "${TMPDIR:-/tmp}/codex-lane-eval.XXXXXX")
trap 'rm -rf "$temp_root"' EXIT

python3 - "$scenario_file" <<'PYTHON' > "$temp_root/scenarios.tsv"
import base64
import json
import sys
from pathlib import Path
for item in json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["scenarios"]:
    print(item["id"] + "\t" + base64.b64encode(json.dumps(item).encode()).decode())
PYTHON

passed=0
while IFS=$'\t' read -r scenario_id encoded; do
    case_root="$temp_root/$scenario_id"
    mkdir -p "$case_root"
    cp "$agents_file" "$case_root/AGENTS.md"
    git -C "$case_root" init --quiet
    result_file="$case_root/result.json"
    prompt=$(python3 - "$encoded" <<'PYTHON'
import base64, json, sys
scenario = json.loads(base64.b64decode(sys.argv[1]))
print("Classify this hypothetical task using AGENTS.md, but do not execute it or modify files\nReturn only the JSON object required by the output schema\n\nTask: " + scenario["prompt"])
PYTHON
)
    arguments=(exec -C "$case_root" --sandbox read-only --output-schema "$result_schema" --output-last-message "$result_file")
    [ -z "$model" ] || arguments+=(--model "$model")
    codex "${arguments[@]}" "$prompt"
    python3 - "$encoded" "$result_file" <<'PYTHON'
import base64, json, sys
from pathlib import Path
scenario = json.loads(base64.b64decode(sys.argv[1]))
result = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
roles = {"orchestration_planner", "orchestration_explorer", "orchestration_implementer", "orchestration_verifier"}
assert set(result) == {"lane", "delegated_agents", "approval_required", "rationale"}
assert result["lane"] in {"single-agent", "plan-light", "orchestrate-heavy"}
assert isinstance(result["approval_required"], bool)
assert isinstance(result["rationale"], str) and 1 <= len(result["rationale"]) <= 300
agents = result["delegated_agents"]
assert isinstance(agents, list)
counts = {}
for agent in agents:
    assert isinstance(agent, dict) and set(agent) == {"role", "count"}
    assert agent["role"] in roles
    assert isinstance(agent["count"], int) and not isinstance(agent["count"], bool) and agent["count"] >= 1
    assert agent["count"] <= 2 if agent["role"] == "orchestration_implementer" else agent["count"] == 1
    assert agent["role"] not in counts
    counts[agent["role"]] = agent["count"]
subagent_count = sum(counts.values())
assert result["lane"] in scenario["allowed_lanes"]
assert result["approval_required"] == scenario["approval_required"]
assert result["lane"] != "single-agent" or subagent_count == 0
assert result["lane"] != "plan-light" or subagent_count <= 1
assert subagent_count <= scenario["max_subagents"]
assert set(scenario["required_roles"]) <= set(counts)
assert set(counts) <= set(scenario["allowed_roles"])
assert not set(counts) & set(scenario["forbidden_roles"])
assert all(count <= scenario["max_role_counts"][role] for role, count in counts.items())
PYTHON
    printf 'PASS: %s\n' "$scenario_id"
    passed=$((passed + 1))
done < "$temp_root/scenarios.tsv"

printf 'Live lane scenarios passed: %s\n' "$passed"

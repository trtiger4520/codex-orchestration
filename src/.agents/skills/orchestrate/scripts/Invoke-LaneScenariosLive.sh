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
assert result["lane"] in scenario["allowed_lanes"]
assert result["approval_required"] == scenario["approval_required"]
assert len(result["delegated_roles"]) <= scenario["max_subagents"]
assert set(scenario["required_roles"]) <= set(result["delegated_roles"])
assert set(result["delegated_roles"]) <= set(scenario["allowed_roles"])
assert not set(result["delegated_roles"]) & set(scenario["forbidden_roles"])
PYTHON
    printf 'PASS: %s\n' "$scenario_id"
    passed=$((passed + 1))
done < "$temp_root/scenarios.tsv"

printf 'Live lane scenarios passed: %s\n' "$passed"

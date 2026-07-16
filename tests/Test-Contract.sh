#!/usr/bin/env bash

set -euo pipefail

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
source_root="$repository_root/src"
validator="$source_root/.agents/skills/orchestrate/scripts/Test-OrchestrationPlan.sh"
schema="$source_root/.agents/skills/orchestrate/references/orchestration-plan.schema.json"
temp_root=$(mktemp -d "${TMPDIR:-/tmp}/codex-orchestration-contract.XXXXXX")

cleanup() {
    rm -rf "$temp_root"
}
trap cleanup EXIT

run_case() {
    name=$1
    expected=$2
    plan=$3
    plan_file="$temp_root/$name.json"
    printf '%s\n' "$plan" > "$plan_file"

    if bash "$validator" --plan-file "$plan_file" --schema-file "$schema" >"$temp_root/$name.out" 2>&1; then
        actual=pass
    else
        actual=fail
    fi

    [ "$actual" = "$expected" ] || {
        cat "$temp_root/$name.out" >&2
        printf 'Case %s expected %s but got %s\n' "$name" "$expected" "$actual" >&2
        exit 1
    }
    printf 'PASS: %s\n' "$name"
}

run_case 'valid-single-agent' pass '{
  "version": "1.0",
  "lane": "single-agent",
  "summary": "Validate single-agent planning",
  "tasks": [{
    "id": "inspect",
    "mode": "read",
    "goal": "Complete inspect",
    "files": [],
    "depends_on": [],
    "risk": "low",
    "acceptance_criteria": ["inspect is complete"],
    "verify_cmds": []
  }]
}'

run_case 'valid-plan-light' pass '{
  "version": "1.0",
  "lane": "plan-light",
  "summary": "Validate plan-light planning",
  "tasks": [{
    "id": "inspect",
    "mode": "read",
    "goal": "Complete inspect",
    "files": [],
    "depends_on": [],
    "risk": "low",
    "acceptance_criteria": ["inspect is complete"],
    "verify_cmds": []
  }, {
    "id": "change",
    "mode": "write",
    "goal": "Complete change",
    "files": ["README.md"],
    "depends_on": ["inspect"],
    "risk": "low",
    "acceptance_criteria": ["change is complete"],
    "verify_cmds": ["git diff --check"]
  }]
}'

run_case 'valid-v1.1-structured-command' pass '{
  "version": "1.1",
  "lane": "plan-light",
  "summary": "Validate structured verification",
  "tasks": [{
    "id": "change",
    "mode": "write",
    "goal": "Complete change",
    "files": ["README.md"],
    "depends_on": [],
    "risk": "low",
    "acceptance_criteria": ["change is complete"],
    "verify_cmds": [{
      "command": "git diff --check",
      "cwd": ".",
      "purpose": "diff-validation",
      "timeout_seconds": 60,
      "expected_writes": []
    }]
  }]
}'

run_case 'invalid-v1.1-string-command' fail '{
  "version": "1.1",
  "lane": "plan-light",
  "summary": "Reject legacy command shape",
  "tasks": [{
    "id": "change", "mode": "write", "goal": "Complete change", "files": ["README.md"], "depends_on": [], "risk": "low", "acceptance_criteria": ["change is complete"], "verify_cmds": ["git diff --check"]
  }]
}'

run_case 'invalid-v1.1-parent-write' fail '{
  "version": "1.1",
  "lane": "plan-light",
  "summary": "Reject parent traversal",
  "tasks": [{
    "id": "change", "mode": "write", "goal": "Complete change", "files": ["README.md"], "depends_on": [], "risk": "low", "acceptance_criteria": ["change is complete"], "verify_cmds": [{
      "command": "git diff --check", "cwd": ".", "purpose": "diff-validation", "timeout_seconds": 60, "expected_writes": ["../outside/**"]
    }]
  }]
}'

run_case 'invalid-v1.1-duplicate-expected-write' fail '{
  "version": "1.1",
  "lane": "plan-light",
  "summary": "Reject duplicate artifact globs",
  "tasks": [{
    "id": "change", "mode": "write", "goal": "Complete change", "files": ["README.md"], "depends_on": [], "risk": "low", "acceptance_criteria": ["change is complete"], "verify_cmds": [{
      "command": "dotnet test", "cwd": ".", "purpose": "test", "timeout_seconds": 60, "expected_writes": ["**/bin/**", "**/bin/**"]
    }]
  }]
}'

run_case 'valid-orchestrate-heavy' pass '{
  "version": "1.0",
  "lane": "orchestrate-heavy",
  "summary": "Validate orchestrate-heavy planning",
  "tasks": [{
    "id": "inspect", "mode": "read", "goal": "Complete inspect", "files": [], "depends_on": [], "risk": "low", "acceptance_criteria": ["inspect is complete"], "verify_cmds": []
  }, {
    "id": "change", "mode": "write", "goal": "Complete change", "files": ["src/**"], "depends_on": ["inspect"], "risk": "low", "acceptance_criteria": ["change is complete"], "verify_cmds": ["dotnet test"]
  }, {
    "id": "review", "mode": "review", "goal": "Complete review", "files": [], "depends_on": ["change"], "risk": "low", "acceptance_criteria": ["review is complete"], "verify_cmds": ["dotnet test"]
  }]
}'

run_case 'invalid-missing-field' fail '{
  "version": "1.0",
  "lane": "single-agent",
  "tasks": []
}'

run_case 'invalid-duplicate-id' fail '{
  "version": "1.0",
  "lane": "plan-light",
  "summary": "Duplicate task ids",
  "tasks": [{
    "id": "same", "mode": "read", "goal": "Complete same", "files": [], "depends_on": [], "risk": "low", "acceptance_criteria": ["same is complete"], "verify_cmds": []
  }, {
    "id": "same", "mode": "read", "goal": "Complete same", "files": [], "depends_on": [], "risk": "low", "acceptance_criteria": ["same is complete"], "verify_cmds": []
  }]
}'

run_case 'invalid-unknown-dependency' fail '{
  "version": "1.0",
  "lane": "plan-light",
  "summary": "Unknown dependency",
  "tasks": [{
    "id": "change", "mode": "write", "goal": "Complete change", "files": ["README.md"], "depends_on": ["missing"], "risk": "low", "acceptance_criteria": ["change is complete"], "verify_cmds": ["git diff --check"]
  }]
}'

run_case 'invalid-write-without-files' fail '{
  "version": "1.0",
  "lane": "plan-light",
  "summary": "Missing files",
  "tasks": [{
    "id": "change", "mode": "write", "goal": "Complete change", "files": [], "depends_on": [], "risk": "low", "acceptance_criteria": ["change is complete"], "verify_cmds": ["git diff --check"]
  }]
}'

run_case 'invalid-write-without-verification' fail '{
  "version": "1.0",
  "lane": "plan-light",
  "summary": "Missing verification",
  "tasks": [{
    "id": "change", "mode": "write", "goal": "Complete change", "files": ["README.md"], "depends_on": [], "risk": "low", "acceptance_criteria": ["change is complete"], "verify_cmds": []
  }]
}'

run_case 'invalid-self-dependency' fail '{
  "version": "1.0",
  "lane": "plan-light",
  "summary": "Self dependency",
  "tasks": [{
    "id": "inspect", "mode": "read", "goal": "Complete inspect", "files": [], "depends_on": ["inspect"], "risk": "low", "acceptance_criteria": ["inspect is complete"], "verify_cmds": []
  }]
}'

run_case 'invalid-cycle' fail '{
  "version": "1.0",
  "lane": "orchestrate-heavy",
  "summary": "Dependency cycle",
  "tasks": [{
    "id": "first", "mode": "read", "goal": "Complete first", "files": [], "depends_on": ["second"], "risk": "low", "acceptance_criteria": ["first is complete"], "verify_cmds": []
  }, {
    "id": "second", "mode": "read", "goal": "Complete second", "files": [], "depends_on": ["first"], "risk": "low", "acceptance_criteria": ["second is complete"], "verify_cmds": []
  }]
}'

printf '%s\n' 'All Bash orchestration contract tests passed'

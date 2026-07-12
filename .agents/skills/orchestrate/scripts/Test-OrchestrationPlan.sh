#!/usr/bin/env bash

set -euo pipefail

script_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
schema_file="$script_root/../references/orchestration-plan.schema.json"

usage() {
    printf '%s\n' 'Usage: Test-OrchestrationPlan.sh --plan-file <path> [--schema-file <path>]'
}

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

plan_file=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --plan-file)
            [ "$#" -ge 2 ] || fail 'Missing value for --plan-file'
            plan_file=$2
            shift 2
            ;;
        --schema-file)
            [ "$#" -ge 2 ] || fail 'Missing value for --schema-file'
            schema_file=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            fail "Unknown argument: $1"
            ;;
    esac
done

[ -n "$plan_file" ] || { usage >&2; fail 'Missing required --plan-file argument'; }
[ -f "$plan_file" ] || fail "Plan file not found: $plan_file"
[ -f "$schema_file" ] || fail "Schema file not found: $schema_file"
command -v python3 >/dev/null 2>&1 || fail 'python3 is required to validate orchestration plans'

python3 - "$plan_file" "$schema_file" <<'PYTHON'
import json
import re
import sys
from pathlib import Path


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def load_json(path, label):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"{label} is not valid JSON: {error}")


def require_object(value, context, errors):
    if not isinstance(value, dict):
        errors.append(f"{context} must be an object")
        return False
    return True


def require_string(value, context, errors, minimum=1, maximum=None, pattern=None):
    if not isinstance(value, str):
        errors.append(f"{context} must be a string")
        return
    if len(value) < minimum:
        errors.append(f"{context} must not be empty")
    if maximum is not None and len(value) > maximum:
        errors.append(f"{context} must not exceed {maximum} characters")
    if pattern is not None and re.fullmatch(pattern, value) is None:
        errors.append(f"{context} has an invalid format")


def require_string_list(value, context, errors, minimum=0):
    if not isinstance(value, list):
        errors.append(f"{context} must be an array")
        return
    if len(value) < minimum:
        errors.append(f"{context} must contain at least {minimum} item(s)")
    for index, item in enumerate(value):
        require_string(item, f"{context}[{index}]", errors)


def require_enum(value, context, allowed, errors):
    require_string(value, context, errors)
    if isinstance(value, str) and value not in allowed:
        errors.append(f"{context} must be one of: {', '.join(allowed)}")


def validate_properties(value, context, required, allowed, errors):
    if not require_object(value, context, errors):
        return False
    for name in required:
        if name not in value:
            errors.append(f"{context} is missing required property: {name}")
    for name in value:
        if name not in allowed:
            errors.append(f"{context} has unknown property: {name}")
    return True


plan_file, schema_file = sys.argv[1:]
schema = load_json(schema_file, "Schema")
plan = load_json(plan_file, "Plan")

try:
    root_required = schema["required"]
    root_properties = schema["properties"]
    task_schema = schema["definitions"]["task"]
    task_required = task_schema["required"]
    task_properties = task_schema["properties"]
except (KeyError, TypeError) as error:
    fail(f"Schema has an unsupported structure: {error}")

errors = []
if validate_properties(plan, "Plan", root_required, root_properties, errors):
    require_enum(plan.get("version"), "Plan.version", root_properties["version"]["enum"], errors)
    require_enum(plan.get("lane"), "Plan.lane", root_properties["lane"]["enum"], errors)
    require_string(
        plan.get("summary"),
        "Plan.summary",
        errors,
        minimum=root_properties["summary"]["minLength"],
        maximum=root_properties["summary"]["maxLength"],
    )

    tasks = plan.get("tasks")
    if not isinstance(tasks, list):
        errors.append("Plan.tasks must be an array")
        tasks = []
    elif len(tasks) < root_properties["tasks"]["minItems"]:
        errors.append("Plan.tasks must contain at least one item")

    tasks_by_id = {}
    for index, task in enumerate(tasks):
        context = f"Plan.tasks[{index}]"
        if not validate_properties(task, context, task_required, task_properties, errors):
            continue

        require_string(task.get("id"), f"{context}.id", errors, pattern=task_properties["id"]["pattern"])
        require_enum(task.get("mode"), f"{context}.mode", task_properties["mode"]["enum"], errors)
        require_string(task.get("goal"), f"{context}.goal", errors)
        require_string_list(task.get("files"), f"{context}.files", errors)
        require_string_list(task.get("depends_on"), f"{context}.depends_on", errors)
        require_enum(task.get("risk"), f"{context}.risk", task_properties["risk"]["enum"], errors)
        require_string_list(task.get("acceptance_criteria"), f"{context}.acceptance_criteria", errors, minimum=1)
        require_string_list(task.get("verify_cmds"), f"{context}.verify_cmds", errors)

        task_id = task.get("id")
        if isinstance(task_id, str) and task_id:
            if task_id in tasks_by_id:
                errors.append(f"Duplicate task id: {task_id}")
            else:
                tasks_by_id[task_id] = task

        if task.get("mode") == "write":
            files = task.get("files")
            commands = task.get("verify_cmds")
            if not isinstance(files, list) or not files:
                errors.append(f"Write task '{task_id}' must declare at least one file")
            if not isinstance(commands, list) or not commands:
                errors.append(f"Write task '{task_id}' must declare at least one verification command")

    for task_id, task in tasks_by_id.items():
        dependencies = task.get("depends_on")
        if not isinstance(dependencies, list):
            continue
        for dependency in dependencies:
            if not isinstance(dependency, str):
                continue
            if dependency == task_id:
                errors.append(f"Task '{task_id}' cannot depend on itself")
            elif dependency not in tasks_by_id:
                errors.append(f"Task '{task_id}' has unknown dependency '{dependency}'")

    visit_state = {}

    def visit_task(task_id):
        state = visit_state.get(task_id)
        if state == "visiting":
            errors.append(f"Dependency cycle detected at task '{task_id}'")
            return
        if state == "visited":
            return
        visit_state[task_id] = "visiting"
        for dependency in tasks_by_id[task_id].get("depends_on", []):
            if dependency in tasks_by_id and dependency != task_id:
                visit_task(dependency)
        visit_state[task_id] = "visited"

    for task_id in tasks_by_id:
        visit_task(task_id)

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)

print(f"PASS: {plan_file}")
PYTHON

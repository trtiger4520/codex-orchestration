#!/usr/bin/env bash

set -e

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
installer="$repository_root/install.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/codex-orchestration-installer.XXXXXX")
passed=0
python3_available=0
if command -v python3 >/dev/null 2>&1; then
    python3_available=1
    printf 'python3 dependency: available\n'
else
    printf 'python3 dependency: unavailable, model and sidecar tests will be skipped\n'
fi

cleanup() {
    rm -rf "$test_root"
}
trap cleanup EXIT

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

assert_true() {
    "$@" || fail "Assertion failed: $*"
}

snapshot() {
    directory=$1
    if [ -d "$directory" ]; then
        find "$directory" -type f -print | LC_ALL=C sort | while IFS= read -r file; do
            relative=${file#"$directory"/}
            if command -v shasum >/dev/null 2>&1; then
                digest=$(shasum -a 256 "$file" | awk '{ print $1 }')
            else
                digest=$(sha256sum "$file" | awk '{ print $1 }')
            fi
            printf '%s %s\n' "$relative" "$digest"
        done
    fi
}

run_test() {
    name=$1
    shift
    "$@"
    passed=$((passed + 1))
    printf 'PASS  %s\n' "$name"
}

run_python_test() {
    name=$1
    shift
    if [ "$python3_available" -eq 0 ]; then
        printf 'SKIP  %s (requires python3)\n' "$name"
        return
    fi
    run_test "$name" "$@"
}

run_installer_defaults() {
    printf '\n\n\n\n' | bash "$installer" "$@"
}

fresh_project_install() {
    platform=$1
    project="$test_root/project-$platform"
    mkdir -p "$project"
    run_installer_defaults --scope project --platform "$platform" --project-path "$project"
    before=$(snapshot "$project")
    bash "$installer" --scope project --platform "$platform" --project-path "$project" --check
    after=$(snapshot "$project")
    [ "$before" = "$after" ]
}

run_python_test "fresh Project install and read-only check for Codex" fresh_project_install Codex
run_python_test "fresh Project install and read-only check for Copilot" fresh_project_install Copilot
run_python_test "fresh Project install and read-only check for All" fresh_project_install All

check_model_defaults() {
    project="$test_root/model-defaults"
    mkdir -p "$project"
    printf '%s\n' inherit '' '' inherit | bash "$installer" --scope project --platform all --project-path "$project"
    sidecar="$project/.codex-orchestration-models.json"
    [ "$(cat "$sidecar")" = '{"explorer":"gpt-5.6-luna","implementer":"gpt-5.6-luna"}' ]

    for role in planner verifier; do
        ! grep -Eq '^[[:space:]]*model[[:space:]]*=' "$project/.codex/agents/orchestration_$role.toml"
        ! grep -Eq '^model[[:space:]]*:' "$project/.github/agents/orchestration_$role.agent.md"
    done
    for role in explorer implementer; do
        grep -F 'model = "gpt-5.6-luna"' "$project/.codex/agents/orchestration_$role.toml" >/dev/null
        grep -F 'model: "gpt-5.6-luna"' "$project/.github/agents/orchestration_$role.agent.md" >/dev/null
    done

    grep -F 'model_reasoning_effort = "medium"' "$project/.codex/agents/orchestration_planner.toml" >/dev/null
    grep -F 'model_reasoning_effort = "low"' "$project/.codex/agents/orchestration_explorer.toml" >/dev/null
    grep -F 'model_reasoning_effort = "high"' "$project/.codex/agents/orchestration_implementer.toml" >/dev/null
    grep -F 'model_reasoning_effort = "high"' "$project/.codex/agents/orchestration_verifier.toml" >/dev/null
    ! grep -R -F 'model_reasoning_effort' "$project/.github/agents" >/dev/null
}
run_python_test "model defaults and inherited agent settings" check_model_defaults

check_rendered_agent_content() {
    project="$test_root/rendered-agent-content"
    mkdir -p "$project"
    printf '%s\n' custom-planner inherit custom-implementer inherit | bash "$installer" --scope project --platform all --project-path "$project"

    for role in planner implementer; do
        grep -F "model = \"custom-$role\"" "$project/.codex/agents/orchestration_$role.toml" >/dev/null
        grep -F "model: \"custom-$role\"" "$project/.github/agents/orchestration_$role.agent.md" >/dev/null
    done
    for role in explorer verifier; do
        ! grep -Eq '^[[:space:]]*model[[:space:]]*=' "$project/.codex/agents/orchestration_$role.toml"
        ! grep -Eq '^model[[:space:]]*:' "$project/.github/agents/orchestration_$role.agent.md"
    done
}
run_python_test "rendered agent content includes custom models and omits inherited model fields" check_rendered_agent_content

check_custom_models_and_read_only_check() {
    project="$test_root/model-custom"
    mkdir -p "$project"
    printf '%s\n' custom-planner custom-explorer custom-implementer custom-verifier | bash "$installer" --scope project --platform all --project-path "$project"
    for role in planner explorer implementer verifier; do
        grep -F "\"$role\":\"custom-$role\"" "$project/.codex-orchestration-models.json" >/dev/null
        grep -F "model = \"custom-$role\"" "$project/.codex/agents/orchestration_$role.toml" >/dev/null
        grep -F "model: \"custom-$role\"" "$project/.github/agents/orchestration_$role.agent.md" >/dev/null
        grep -E '^model_reasoning_effort = "(low|medium|high)"$' "$project/.codex/agents/orchestration_$role.toml" >/dev/null
    done

    before=$(snapshot "$project")
    check_output="$test_root/model-custom-check-output"
    bash "$installer" --scope project --platform all --project-path "$project" --check < /dev/null > "$check_output" 2>&1
    after=$(snapshot "$project")
    [ "$before" = "$after" ]
    ! grep -F 'Model for ' "$check_output" >/dev/null
}
run_python_test "custom models are saved and Check is non-interactive and read-only" check_custom_models_and_read_only_check

check_legacy_luna_sidecar() {
    project="$test_root/model-legacy-luna"
    mkdir -p "$project"
    printf '%s\n' inherit 5.6-luna 5.6-luna inherit | bash "$installer" --scope project --platform all --project-path "$project"
    before=$(snapshot "$project")
    bash "$installer" --scope project --platform all --project-path "$project" --check < /dev/null
    after=$(snapshot "$project")
    [ "$before" = "$after" ]
    grep -F '"explorer":"5.6-luna"' "$project/.codex-orchestration-models.json" >/dev/null
    grep -F '"implementer":"5.6-luna"' "$project/.codex-orchestration-models.json" >/dev/null
}
run_python_test "legacy luna sidecar remains explicit and Check does not migrate it" check_legacy_luna_sidecar

check_duplicate_scope_warning() {
    project="$test_root/duplicate-scope"
    home="$test_root/duplicate-home"
    codex_home="$home/.codex"
    mkdir -p "$project" "$codex_home"
    global_agents="$codex_home/AGENTS.md"
    printf '%s\n' 'before' '<!-- codex-multi-agent-orchestration:start -->' 'rules' '<!-- codex-multi-agent-orchestration:end -->' 'after' > "$global_agents"
    before=$(snapshot "$codex_home")

    HOME="$home" CODEX_HOME="$codex_home" run_installer_defaults --scope project --platform codex --project-path "$project" > "$test_root/duplicate-install-output" 2>&1
    grep -F 'WARN  Duplicate managed orchestration instructions' "$test_root/duplicate-install-output" >/dev/null
    [ "$before" = "$(snapshot "$codex_home")" ]

    HOME="$home" CODEX_HOME="$codex_home" bash "$installer" --scope project --platform codex --project-path "$project" --check > "$test_root/duplicate-check-output" 2>&1
    grep -F 'WARN  Duplicate managed orchestration instructions' "$test_root/duplicate-check-output" >/dev/null
    [ "$before" = "$(snapshot "$codex_home")" ]

    rm "$global_agents"
    HOME="$home" CODEX_HOME="$codex_home" bash "$installer" --scope project --platform codex --project-path "$project" --check > "$test_root/no-duplicate-output" 2>&1
    ! grep -F 'WARN  Duplicate managed orchestration instructions' "$test_root/no-duplicate-output" >/dev/null

    printf '%s\n' '<!-- codex-multi-agent-orchestration:start -->' '<!-- codex-multi-agent-orchestration:end -->' > "$global_agents"
    copilot_project="$test_root/duplicate-copilot-only"
    mkdir -p "$copilot_project"
    HOME="$home" CODEX_HOME="$codex_home" run_installer_defaults --scope project --platform copilot --project-path "$copilot_project" > "$test_root/copilot-only-output" 2>&1
    ! grep -F 'WARN  Duplicate managed orchestration instructions' "$test_root/copilot-only-output" >/dev/null
}
run_python_test "Project duplicate scope warning is non-blocking and read-only" check_duplicate_scope_warning

check_sidecar_errors() {
    for case_name in malformed invalid unknown-role; do
        project="$test_root/sidecar-$case_name"
        mkdir -p "$project"
        printf '%s\n' '' '' '' '' | bash "$installer" --scope project --platform all --project-path "$project"
        case "$case_name" in
            malformed) printf '%s' '{"explorer":' > "$project/.codex-orchestration-models.json"; expected='Malformed model settings JSON' ;;
            invalid) printf '%s' '{"explorer":42}' > "$project/.codex-orchestration-models.json"; expected="invalid model for 'explorer'" ;;
            unknown-role) printf '%s' '{"unknown":"model"}' > "$project/.codex-orchestration-models.json"; expected='unknown model role' ;;
        esac
        output="$test_root/sidecar-$case_name-output"
        if bash "$installer" --scope project --platform all --project-path "$project" --check < /dev/null > "$output" 2>&1; then
            return 1
        fi
        grep -F "$expected" "$output" >/dev/null
    done
}
run_python_test "malformed and invalid model sidecars are rejected" check_sidecar_errors

check_aggregates_drift() {
    project="$test_root/drift"
    mkdir -p "$project"
    run_installer_defaults --scope project --platform all --project-path "$project"
    agent=$(find "$project/.codex/agents" -type f | head -n 1)
    printf 'drift\n' >> "$agent"
    if bash "$installer" --scope project --platform all --project-path "$project" --check > "$test_root/drift-output" 2>&1; then
        return 1
    fi
    grep -F 'DRIFT [Different]' "$test_root/drift-output" >/dev/null
}
run_python_test "check reports changed managed files" check_aggregates_drift

user_scope_honors_homes() {
    user_home="$test_root/user-home"
    codex_home="$test_root/codex-home"
    copilot_home="$test_root/copilot-home"
    mkdir -p "$user_home"
    HOME="$user_home" CODEX_HOME="$codex_home" COPILOT_HOME="$copilot_home" run_installer_defaults --scope user --platform all
    [ -d "$codex_home/agents" ] && [ -d "$copilot_home/agents" ] && [ -d "$user_home/.agents/skills" ]
    grep -F '# Multi-agent orchestration rules' "$copilot_home/copilot-instructions.md" >/dev/null
}
run_python_test "User scope honors configured homes" user_scope_honors_homes

check_rejects_force() {
    project="$test_root/check-force"
    mkdir -p "$project"
    if bash "$installer" --scope project --platform all --project-path "$project" --check --force > /dev/null 2>&1; then
        return 1
    fi
}
run_test "check rejects force" check_rejects_force

printf 'Installer tests passed: %s\n' "$passed"

#!/usr/bin/env bash

set -e

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
installer="$repository_root/install.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/codex-orchestration-installer.XXXXXX")
passed=0

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

fresh_project_install() {
    platform=$1
    project="$test_root/project-$platform"
    mkdir -p "$project"
    bash "$installer" --scope project --platform "$platform" --project-path "$project"
    before=$(snapshot "$project")
    bash "$installer" --scope project --platform "$platform" --project-path "$project" --check
    after=$(snapshot "$project")
    [ "$before" = "$after" ]
}

run_test "fresh Project install and read-only check for Codex" fresh_project_install Codex
run_test "fresh Project install and read-only check for Copilot" fresh_project_install Copilot
run_test "fresh Project install and read-only check for All" fresh_project_install All

check_aggregates_drift() {
    project="$test_root/drift"
    mkdir -p "$project"
    bash "$installer" --scope project --platform all --project-path "$project"
    agent=$(find "$project/.codex/agents" -type f | head -n 1)
    printf 'drift\n' >> "$agent"
    if bash "$installer" --scope project --platform all --project-path "$project" --check > "$test_root/drift-output" 2>&1; then
        return 1
    fi
    grep -F 'DRIFT [Different]' "$test_root/drift-output" >/dev/null
}
run_test "check reports changed managed files" check_aggregates_drift

user_scope_honors_homes() {
    user_home="$test_root/user-home"
    codex_home="$test_root/codex-home"
    copilot_home="$test_root/copilot-home"
    mkdir -p "$user_home"
    HOME="$user_home" CODEX_HOME="$codex_home" COPILOT_HOME="$copilot_home" bash "$installer" --scope user --platform all
    [ -d "$codex_home/agents" ] && [ -d "$copilot_home/agents" ] && [ -d "$user_home/.agents/skills" ]
    grep -F '# Multi-agent orchestration rules' "$copilot_home/copilot-instructions.md" >/dev/null
}
run_test "User scope honors configured homes" user_scope_honors_homes

check_rejects_force() {
    project="$test_root/check-force"
    mkdir -p "$project"
    if bash "$installer" --scope project --platform all --project-path "$project" --check --force > /dev/null 2>&1; then
        return 1
    fi
}
run_test "check rejects force" check_rejects_force

printf 'Installer tests passed: %s\n' "$passed"

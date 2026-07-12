#!/usr/bin/env bash

set -e

scope="user"
platform="all"
project_path=""
force=0
check=0

package_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
start_marker="<!-- codex-multi-agent-orchestration:start -->"
end_marker="<!-- codex-multi-agent-orchestration:end -->"
drift_count=0

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

normalize() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

hash_file() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{ print $1 }'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{ print $1 }'
    else
        fail "Neither shasum nor sha256sum is available"
    fi
}

same_path() {
    left_dir=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd -P) || return 1
    right_dir=$(CDPATH= cd -- "$(dirname -- "$2")" && pwd -P) || return 1
    [ "$left_dir/$(basename -- "$1")" = "$right_dir/$(basename -- "$2")" ]
}

add_drift() {
    drift_count=$((drift_count + 1))
    printf 'DRIFT [%s] %s\n' "$1" "$2"
}

copy_managed_file() {
    source_file=$1
    destination_file=$2

    [ -f "$source_file" ] || fail "Source file not found: $source_file"

    if [ -e "$destination_file" ] && same_path "$source_file" "$destination_file"; then
        printf 'SKIP  %s\n' "$destination_file"
        return
    fi

    if [ -f "$destination_file" ]; then
        if [ "$(hash_file "$source_file")" = "$(hash_file "$destination_file")" ]; then
            printf 'SKIP  %s\n' "$destination_file"
            return
        fi

        [ "$force" -eq 1 ] || fail "Managed file conflict: $destination_file
Re-run with --force to overwrite this managed file"
    fi

    mkdir -p "$(dirname -- "$destination_file")"
    cp "$source_file" "$destination_file"
    printf 'COPY  %s\n' "$destination_file"
}

copy_managed_tree() {
    source_root=$1
    destination_root=$2

    [ -d "$source_root" ] || fail "Source directory not found: $source_root"

    while IFS= read -r source_file; do
        relative_path=${source_file#"$source_root"/}
        copy_managed_file "$source_file" "$destination_root/$relative_path"
    done < <(find "$source_root" -type f -print)
}

test_managed_file() {
    source_file=$1
    destination_file=$2

    [ -f "$source_file" ] || fail "Source file not found: $source_file"

    if [ -e "$destination_file" ] && same_path "$source_file" "$destination_file"; then
        return
    fi

    if [ ! -f "$destination_file" ]; then
        add_drift "Missing" "$destination_file"
    elif [ "$(hash_file "$source_file")" != "$(hash_file "$destination_file")" ]; then
        add_drift "Different" "$destination_file"
    fi
}

test_managed_tree() {
    source_root=$1
    destination_root=$2

    [ -d "$source_root" ] || fail "Source directory not found: $source_root"

    while IFS= read -r source_file; do
        relative_path=${source_file#"$source_root"/}
        test_managed_file "$source_file" "$destination_root/$relative_path"
    done < <(find "$source_root" -type f -print)
}

marker_state() {
    awk -v start="$start_marker" -v end="$end_marker" '
        $0 == start { starts++; if (first_start == 0) first_start = NR }
        $0 == end { ends++; if (first_end == 0) first_end = NR }
        END {
            if (starts == 0 && ends == 0) print "Absent"
            else if (starts != 1 || ends != 1 || first_start > first_end) print "Malformed"
            else print "Valid"
        }
    ' "$1"
}

make_managed_block() {
    source_file=$1
    block_file=$2
    [ -f "$source_file" ] || fail "Source file not found: $source_file"

    printf '%s\n' "$start_marker" > "$block_file"
    cat "$source_file" >> "$block_file"
    if [ -s "$source_file" ] && [ "$(tail -c 1 "$source_file" 2>/dev/null || true)" != "" ]; then
        printf '\n' >> "$block_file"
    fi
    printf '%s\n' "$end_marker" >> "$block_file"
}

managed_block_matches() {
    source_file=$1
    destination_file=$2
    expected_file=$(mktemp "${TMPDIR:-/tmp}/codex-managed-block.XXXXXX")
    actual_file=$(mktemp "${TMPDIR:-/tmp}/codex-managed-block.XXXXXX")
    make_managed_block "$source_file" "$expected_file"
    awk -v start="$start_marker" -v end="$end_marker" '
        $0 == start { printing = 1 }
        printing { print }
        $0 == end && printing { exit }
    ' "$destination_file" > "$actual_file"
    if cmp -s "$expected_file" "$actual_file"; then
        result=0
    else
        result=1
    fi
    rm -f "$expected_file" "$actual_file"
    return "$result"
}

test_managed_instructions() {
    source_file=$1
    destination_file=$2

    if [ -e "$destination_file" ] && same_path "$source_file" "$destination_file"; then
        return
    fi

    if [ ! -f "$destination_file" ]; then
        add_drift "Missing" "$destination_file"
        return
    fi

    case "$(marker_state "$destination_file")" in
        Absent) add_drift "Missing" "$destination_file" ;;
        Malformed) add_drift "MalformedMarker" "$destination_file" ;;
        Valid) managed_block_matches "$source_file" "$destination_file" || add_drift "Different" "$destination_file" ;;
    esac
}

merge_managed_instructions() {
    source_file=$1
    destination_file=$2

    if [ -e "$destination_file" ] && same_path "$source_file" "$destination_file"; then
        printf 'SKIP  %s\n' "$destination_file"
        return
    fi

    mkdir -p "$(dirname -- "$destination_file")"
    block_file=$(mktemp "${TMPDIR:-/tmp}/codex-managed-block.XXXXXX")
    make_managed_block "$source_file" "$block_file"

    if [ ! -f "$destination_file" ]; then
        cp "$block_file" "$destination_file"
        rm -f "$block_file"
        printf 'MERGE %s\n' "$destination_file"
        return
    fi

    state=$(marker_state "$destination_file")
    [ "$state" != "Malformed" ] || { rm -f "$block_file"; fail "Malformed managed instruction markers: $destination_file"; }

    if [ "$state" = "Valid" ]; then
        if managed_block_matches "$source_file" "$destination_file"; then
            rm -f "$block_file"
            printf 'SKIP  %s\n' "$destination_file"
            return
        fi

        [ "$force" -eq 1 ] || { rm -f "$block_file"; fail "Managed instruction block conflict: $destination_file
Re-run with --force to update only the marked block"; }

        output_file=$(mktemp "${TMPDIR:-/tmp}/codex-managed-merge.XXXXXX")
        awk -v start="$start_marker" -v end="$end_marker" -v block="$block_file" '
            $0 == start {
                while ((getline line < block) > 0) print line
                close(block)
                replacing = 1
                next
            }
            replacing && $0 == end { replacing = 0; next }
            !replacing { print }
        ' "$destination_file" > "$output_file"
        mv "$output_file" "$destination_file"
    else
        { cat "$destination_file"; printf '\n\n'; cat "$block_file"; } > "$destination_file.tmp"
        mv "$destination_file.tmp" "$destination_file"
    fi

    rm -f "$block_file"
    printf 'MERGE %s\n' "$destination_file"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -Scope|--scope)
            [ "$#" -ge 2 ] || fail "Missing value for $1"
            scope=$(normalize "$2")
            shift 2
            ;;
        -Platform|--platform)
            [ "$#" -ge 2 ] || fail "Missing value for $1"
            platform=$(normalize "$2")
            shift 2
            ;;
        -ProjectPath|--project-path)
            [ "$#" -ge 2 ] || fail "Missing value for $1"
            project_path=$2
            shift 2
            ;;
        -Force|--force)
            force=1
            shift
            ;;
        -Check|--check)
            check=1
            shift
            ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

case "$scope" in user|project) ;; *) fail "Scope must be User or Project" ;; esac
case "$platform" in codex|copilot|all) ;; *) fail "Platform must be Codex, Copilot, or All" ;; esac
[ "$check" -eq 0 ] || [ "$force" -eq 0 ] || fail "--check and --force cannot be used together"

install_codex=0
install_copilot=0
[ "$platform" = "codex" ] || [ "$platform" = "all" ] && install_codex=1
[ "$platform" = "copilot" ] || [ "$platform" = "all" ] && install_copilot=1

install_targets() {
    codex_instructions_destination=$1
    codex_root=$2
    copilot_instructions_destination=$3
    copilot_root=$4
    skills_root=$5

    if [ "$install_codex" -eq 1 ]; then
        if [ "$check" -eq 1 ]; then
            test_managed_tree "$package_root/.codex/agents" "$codex_root"
            test_managed_instructions "$package_root/AGENTS.md" "$codex_instructions_destination"
        else
            copy_managed_tree "$package_root/.codex/agents" "$codex_root"
            merge_managed_instructions "$package_root/AGENTS.md" "$codex_instructions_destination"
        fi
    fi

    if [ "$install_copilot" -eq 1 ]; then
        if [ "$scope" = "project" ]; then
            copilot_instructions_source="$package_root/.github/copilot-instructions.md"
        else
            copilot_instructions_source="$package_root/.github/copilot-user-instructions.md"
        fi

        if [ "$check" -eq 1 ]; then
            test_managed_tree "$package_root/.github/agents" "$copilot_root"
            test_managed_instructions "$copilot_instructions_source" "$copilot_instructions_destination"
        else
            copy_managed_tree "$package_root/.github/agents" "$copilot_root"
            merge_managed_instructions "$copilot_instructions_source" "$copilot_instructions_destination"
        fi
    fi

    if [ "$check" -eq 1 ]; then
        test_managed_tree "$package_root/.agents/skills" "$skills_root"
    else
        copy_managed_tree "$package_root/.agents/skills" "$skills_root"
    fi
}

if [ "$scope" = "project" ]; then
    [ -n "$project_path" ] || fail "--project-path is required when --scope project is selected"
    [ -d "$project_path" ] || fail "Project path not found: $project_path"
    target_root=$(CDPATH= cd -- "$project_path" && pwd -P)
    install_targets "$target_root/AGENTS.md" "$target_root/.codex/agents" "$target_root/.github/copilot-instructions.md" "$target_root/.github/agents" "$target_root/.agents/skills"
else
    user_home=${HOME:-}
    [ -n "$user_home" ] || fail "HOME is not available in this Bash session"
    codex_home=${CODEX_HOME:-"$user_home/.codex"}
    copilot_home=${COPILOT_HOME:-"$user_home/.copilot"}
    install_targets "$codex_home/AGENTS.md" "$codex_home/agents" "$copilot_home/copilot-instructions.md" "$copilot_home/agents" "$user_home/.agents/skills"
fi

if [ "$check" -eq 1 ]; then
    if [ "$drift_count" -gt 0 ]; then
        printf 'Check completed with %s drift item(s) for scope %s and platform %s\n' "$drift_count" "$scope" "$platform"
        exit 1
    fi
    printf 'Check completed with no drift for scope %s and platform %s\n' "$scope" "$platform"
else
    printf 'Installation completed for scope %s and platform %s\n' "$scope" "$platform"
fi

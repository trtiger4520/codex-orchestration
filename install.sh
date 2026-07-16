#!/usr/bin/env bash

set -e

scope="user"
platform="all"
project_path=""
force=0
check=0

package_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
source_root="$package_root/src"
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

hash_stdin() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{ print $1 }'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{ print $1 }'
    else
        fail "Neither shasum nor sha256sum is available"
    fi
}

agent_role() {
    source_file=$1
    file_name=$(basename -- "$source_file")
    case "$file_name" in
        orchestration_*.toml) role=${file_name#orchestration_}; role=${role%.toml} ;;
        orchestration_*.agent.md) role=${file_name#orchestration_}; role=${role%.agent.md} ;;
        *) return 0 ;;
    esac

    case "$role" in
        planner|explorer|implementer|verifier) printf '%s' "$role" ;;
    esac
}

model_for_role() {
    case "$1" in
        planner) printf '%s' "$model_planner" ;;
        explorer) printf '%s' "$model_explorer" ;;
        implementer) printf '%s' "$model_implementer" ;;
        verifier) printf '%s' "$model_verifier" ;;
        *) fail "Unknown model role: $1" ;;
    esac
}

transform_agent() {
    source_file=$1
    role=$2
    model=$3
    python3 - "$source_file" "$role" "$model" <<'PY'
import json
import re
import sys

source_file, role, model = sys.argv[1:]
with open(source_file, "r", encoding="utf-8", newline="") as source:
    text = source.read()
newline = "\r\n" if "\r\n" in text else "\n"
lines = text.splitlines()
trailing_newline = text.endswith(("\r\n", "\n", "\r"))
quoted_model = json.dumps(model, ensure_ascii=False)

if source_file.lower().endswith(".toml"):
    lines = [line for line in lines if not re.match(r"^\s*model\s*=", line)]
    if model:
        for index, line in enumerate(lines):
            if re.match(r"^\s*name\s*=", line):
                lines.insert(index + 1, f"model = {quoted_model}")
                break
        else:
            lines.insert(0, f"model = {quoted_model}")
else:
    if not lines or lines[0].strip() != "---":
        raise ValueError(f"Malformed Copilot agent front matter: {source_file}")
    try:
        front_matter_end = next(index for index in range(1, len(lines)) if lines[index].strip() == "---")
    except StopIteration as error:
        raise ValueError(f"Malformed Copilot agent front matter: {source_file}") from error

    front_matter = [line for line in lines[1:front_matter_end] if not re.match(r"^\s*model\s*:", line)]
    if model:
        front_matter.insert(0, f"model: {quoted_model}")
    lines = [lines[0], *front_matter, *lines[front_matter_end:]]

result = newline.join(lines)
if trailing_newline:
    result += newline
sys.stdout.buffer.write(result.encode("utf-8"))
PY
}

configured_hash() {
    source_file=$1
    role=$2
    model=$3
    transform_agent "$source_file" "$role" "$model" | hash_stdin
}

prompt_model() {
    role=$1
    default_value=$2
    if [ -n "$default_value" ]; then
        default_label=$default_value
    else
        default_label=inherit
    fi

    while true; do
        printf 'Model for %s [%s] (Enter=default, inherit=inherit): ' "$role" "$default_label" >&2
        IFS= read -r value || fail "Unable to read model for $role"
        if [ -z "$value" ]; then
            REPLY=$default_value
            return
        fi
        if [ "$value" = "inherit" ]; then
            REPLY=""
            return
        fi
        case "$value" in
            *$'\r'*|*$'\n'*) printf '%s\n' "Model must not contain a newline" >&2 ;;
            *)
                case "$value" in
                    *[![:space:]]*) REPLY=$value; return ;;
                    *) printf '%s\n' "Model must be non-empty" >&2 ;;
                esac
                ;;
        esac
    done
}

load_model_settings() {
    sidecar_path=$1
    if [ ! -f "$sidecar_path" ]; then
        model_planner=""
        model_explorer="gpt-5.6-luna"
        model_implementer="gpt-5.6-luna"
        model_verifier=""
        return
    fi
    command -v python3 >/dev/null 2>&1 || fail "python3 is required to read model settings JSON"

    output=$(python3 - "$sidecar_path" <<'PY'
import json
import sys

path = sys.argv[1]
roles = ("planner", "explorer", "implementer", "verifier")
defaults = {"planner": None, "explorer": "gpt-5.6-luna", "implementer": "gpt-5.6-luna", "verifier": None}
try:
    with open(path, "r", encoding="utf-8") as sidecar:
        parsed = json.load(sidecar)
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"Malformed model settings JSON: {path}") from error

if not isinstance(parsed, dict):
    raise SystemExit(f"Malformed model settings JSON: {path}")
unknown = set(parsed) - set(roles)
if unknown:
    raise SystemExit(f"Malformed model settings JSON: unknown model role(s) in {path}")

for role in roles:
    value = parsed.get(role, defaults[role])
    if value is None:
        print()
    elif isinstance(value, str) and value and not any(character in value for character in "\r\n"):
        print(value)
    else:
        raise SystemExit(f"Malformed model settings JSON: invalid model for '{role}' in {path}")
print("__CODEX_MODEL_SETTINGS_END__")
PY
) || fail "$output"

    settings=()
    while IFS= read -r line; do
        line=${line%$'\r'}
        settings+=("$line")
    done <<< "$output"
    [ "${settings[4]:-}" = "__CODEX_MODEL_SETTINGS_END__" ] || fail "Malformed model settings JSON: $sidecar_path"
    model_planner=${settings[0]}
    model_explorer=${settings[1]}
    model_implementer=${settings[2]}
    model_verifier=${settings[3]}
}

save_model_settings() {
    sidecar_path=$1
    python3 - "$sidecar_path" "$model_planner" "$model_explorer" "$model_implementer" "$model_verifier" <<'PY'
import json
import os
import sys

path, planner, explorer, implementer, verifier = sys.argv[1:]
settings = {}
for role, value in (("planner", planner), ("explorer", explorer), ("implementer", implementer), ("verifier", verifier)):
    if value:
        settings[role] = value
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8", newline="\n") as sidecar:
    json.dump(settings, sidecar, ensure_ascii=False, separators=(",", ":"))
    sidecar.write("\n")
PY
}

configure_models() {
    sidecar_path=$1
    if [ "$check" -eq 1 ]; then
        load_model_settings "$sidecar_path"
        return
    fi

    prompt_model planner ""
    model_planner=$REPLY
    prompt_model explorer "gpt-5.6-luna"
    model_explorer=$REPLY
    prompt_model implementer "gpt-5.6-luna"
    model_implementer=$REPLY
    prompt_model verifier ""
    model_verifier=$REPLY
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
    local source_root=$1
    local destination_root=$2
    local source_file relative_path destination_file role temporary_file

    [ -d "$source_root" ] || fail "Source directory not found: $source_root"

    while IFS= read -r source_file; do
        relative_path=${source_file#"$source_root"/}
        destination_file="$destination_root/$relative_path"
        role=$(agent_role "$source_file")
        if [ -z "$role" ] || { [ -e "$destination_file" ] && same_path "$source_file" "$destination_file"; }; then
            copy_managed_file "$source_file" "$destination_file"
        else
            temporary_file=$(mktemp "${TMPDIR:-/tmp}/codex-agent.XXXXXX")
            transform_agent "$source_file" "$role" "$(model_for_role "$role")" > "$temporary_file"
            copy_managed_file "$temporary_file" "$destination_file"
            rm -f "$temporary_file"
        fi
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
    local source_root=$1
    local destination_root=$2
    local source_file relative_path destination_file role

    [ -d "$source_root" ] || fail "Source directory not found: $source_root"

    while IFS= read -r source_file; do
        relative_path=${source_file#"$source_root"/}
        destination_file="$destination_root/$relative_path"
        role=$(agent_role "$source_file")
        if [ -z "$role" ]; then
            test_managed_file "$source_file" "$destination_file"
        else
            if [ -e "$destination_file" ] && same_path "$source_file" "$destination_file"; then
                continue
            fi
            if [ ! -f "$destination_file" ]; then
                add_drift "Missing" "$destination_file"
            elif [ "$(configured_hash "$source_file" "$role" "$(model_for_role "$role")")" != "$(hash_file "$destination_file")" ]; then
                add_drift "Different" "$destination_file"
            fi
        fi
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
            test_managed_tree "$source_root/.codex/agents" "$codex_root"
            test_managed_instructions "$source_root/AGENTS.md" "$codex_instructions_destination"
        else
            copy_managed_tree "$source_root/.codex/agents" "$codex_root"
            merge_managed_instructions "$source_root/AGENTS.md" "$codex_instructions_destination"
        fi
    fi

    if [ "$install_copilot" -eq 1 ]; then
        if [ "$scope" = "project" ]; then
            copilot_instructions_source="$source_root/.github/copilot-instructions.md"
        else
            copilot_instructions_source="$source_root/.github/copilot-user-instructions.md"
        fi

        if [ "$check" -eq 1 ]; then
            test_managed_tree "$source_root/.github/agents" "$copilot_root"
            test_managed_instructions "$copilot_instructions_source" "$copilot_instructions_destination"
        else
            copy_managed_tree "$source_root/.github/agents" "$copilot_root"
            merge_managed_instructions "$copilot_instructions_source" "$copilot_instructions_destination"
        fi
    fi

    if [ "$check" -eq 1 ]; then
        test_managed_tree "$source_root/.agents/skills" "$skills_root"
    else
        copy_managed_tree "$source_root/.agents/skills" "$skills_root"
    fi
}

warn_duplicate_scope() {
    [ "$scope" = "project" ] || return 0
    [ "$install_codex" -eq 1 ] || return 0

    user_home=${HOME:-}
    if [ -n "${CODEX_HOME:-}" ]; then
        global_agents_path="$CODEX_HOME/AGENTS.md"
    elif [ -n "$user_home" ]; then
        global_agents_path="$user_home/.codex/AGENTS.md"
    else
        return 0
    fi

    [ -f "$global_agents_path" ] || return 0
    if grep -F "$start_marker" "$global_agents_path" >/dev/null 2>&1 || grep -F "$end_marker" "$global_agents_path" >/dev/null 2>&1; then
        printf 'WARN  Duplicate managed orchestration instructions found in %s; keep the complete rules in either User or Project scope\n' "$global_agents_path"
    fi
}

if [ "$scope" = "project" ]; then
    [ -n "$project_path" ] || fail "--project-path is required when --scope project is selected"
    [ -d "$project_path" ] || fail "Project path not found: $project_path"
    target_root=$(CDPATH= cd -- "$project_path" && pwd -P)
    warn_duplicate_scope
    model_sidecar="$target_root/.codex-orchestration-models.json"
    configure_models "$model_sidecar"
    install_targets "$target_root/AGENTS.md" "$target_root/.codex/agents" "$target_root/.github/copilot-instructions.md" "$target_root/.github/agents" "$target_root/.agents/skills"
    [ "$check" -eq 1 ] || save_model_settings "$model_sidecar"
else
    user_home=${HOME:-}
    [ -n "$user_home" ] || fail "HOME is not available in this Bash session"
    codex_home=${CODEX_HOME:-"$user_home/.codex"}
    copilot_home=${COPILOT_HOME:-"$user_home/.copilot"}
    model_sidecar="$user_home/.codex-orchestration-models.json"
    configure_models "$model_sidecar"
    install_targets "$codex_home/AGENTS.md" "$codex_home/agents" "$copilot_home/copilot-instructions.md" "$copilot_home/agents" "$user_home/.agents/skills"
    [ "$check" -eq 1 ] || save_model_settings "$model_sidecar"
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

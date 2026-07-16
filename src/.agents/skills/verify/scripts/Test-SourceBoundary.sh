#!/usr/bin/env bash

set -euo pipefail

mode=""
snapshot_file=""
repository="."
allowed_writes=()

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --capture|--verify) mode=${1#--}; shift ;;
        --snapshot-file) [ "$#" -ge 2 ] || fail "Missing value for $1"; snapshot_file=$2; shift 2 ;;
        --repository) [ "$#" -ge 2 ] || fail "Missing value for $1"; repository=$2; shift 2 ;;
        --allow-write) [ "$#" -ge 2 ] || fail "Missing value for $1"; allowed_writes+=("$2"); shift 2 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

[ -n "$mode" ] || fail 'Specify --capture or --verify'
[ -n "$snapshot_file" ] || fail 'Missing --snapshot-file'
command -v python3 >/dev/null 2>&1 || fail 'python3 is required for source-boundary verification'

python3 - "$mode" "$snapshot_file" "$repository" "${allowed_writes[@]}" <<'PYTHON'
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

mode, snapshot_file, repository, *patterns = sys.argv[1:]


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def repository_snapshot(root):
    try:
        resolved = Path(subprocess.check_output(
            ["git", "-C", root, "rev-parse", "--show-toplevel"], text=True
        ).strip())
        output = subprocess.check_output(
            ["git", "-C", str(resolved), "-c", "core.quotepath=false", "ls-files", "--cached", "--others", "--exclude-standard"],
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        fail(f"Unable to inspect Git repository: {error}")
    files = {}
    for relative in sorted(set(filter(None, output.splitlines()))):
        path = resolved / relative
        if path.is_file():
            files[relative.replace("\\", "/")] = hashlib.sha256(path.read_bytes()).hexdigest()
    return {"version": "1.0", "repository_root": str(resolved), "files": files}


def allowed(path):
    for pattern in patterns:
        normalized = pattern.replace("\\", "/")
        if Path(normalized).is_absolute() or ".." in Path(normalized).parts or re.match(r"^[A-Za-z]:", normalized):
            fail(f"Allowed write pattern must be repository-relative: {pattern}")
        expression = re.escape(normalized).replace(r"\*\*/", "(?:.*/)?").replace(r"\*\*", ".*").replace(r"\*", "[^/]*").replace(r"\?", "[^/]")
        if re.fullmatch(expression, path):
            return True
    return False


snapshot_path = Path(snapshot_file)
if mode == "capture":
    snapshot_path.parent.mkdir(parents=True, exist_ok=True)
    snapshot_path.write_text(json.dumps(repository_snapshot(repository), indent=2) + "\n", encoding="utf-8")
    print(f"CAPTURED: {snapshot_path}")
    raise SystemExit(0)

try:
    before = json.loads(snapshot_path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as error:
    fail(f"Unable to read snapshot: {error}")
after = repository_snapshot(repository)
violations = [
    path for path in sorted(set(before["files"]) | set(after["files"]))
    if before["files"].get(path) != after["files"].get(path) and not allowed(path)
]
if violations:
    for path in violations:
        print(f"Source boundary violation: {path}", file=sys.stderr)
    raise SystemExit(1)
print("PASS: source boundary preserved")
PYTHON

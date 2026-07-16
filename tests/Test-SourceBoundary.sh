#!/usr/bin/env bash

set -euo pipefail
repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
guard="$repository_root/src/.agents/skills/verify/scripts/Test-SourceBoundary.sh"
temp_root=$(mktemp -d "${TMPDIR:-/tmp}/codex-boundary.XXXXXX")
trap 'rm -rf "$temp_root"' EXIT

git -C "$temp_root" init --quiet
printf 'baseline' > "$temp_root/source.txt"
printf 'ignored/\n' > "$temp_root/.gitignore"
git -C "$temp_root" add source.txt .gitignore
snapshot="$temp_root/.git/boundary.json"

bash "$guard" --capture --repository "$temp_root" --snapshot-file "$snapshot"
mkdir -p "$temp_root/bin"
printf 'artifact' > "$temp_root/bin/artifact.dll"
bash "$guard" --verify --repository "$temp_root" --snapshot-file "$snapshot" --allow-write '**/bin/**'

printf 'changed' > "$temp_root/source.txt"
if bash "$guard" --verify --repository "$temp_root" --snapshot-file "$snapshot" --allow-write '**/bin/**' >/dev/null 2>&1; then
    printf '%s\n' 'Tracked source change was not rejected' >&2
    exit 1
fi

printf 'baseline' > "$temp_root/source.txt"
printf 'new' > "$temp_root/new-source.txt"
if bash "$guard" --verify --repository "$temp_root" --snapshot-file "$snapshot" --allow-write '**/bin/**' >/dev/null 2>&1; then
    printf '%s\n' 'Non-ignored untracked source was not rejected' >&2
    exit 1
fi

rm "$temp_root/new-source.txt"
mkdir -p "$temp_root/ignored"
printf 'cache' > "$temp_root/ignored/cache.txt"
bash "$guard" --verify --repository "$temp_root" --snapshot-file "$snapshot" --allow-write '**/bin/**'
printf '%s\n' 'All Bash source boundary tests passed'

#!/usr/bin/env bash

set -euo pipefail
repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
bash "$repository_root/src/.agents/skills/orchestrate/scripts/Test-LaneScenarios.sh"
printf '%s\n' 'All Bash lane scenario tests passed'

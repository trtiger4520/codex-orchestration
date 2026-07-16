---
name: verify
description: Independently inspect and validate current code changes against a supplied plan, scope, or acceptance criteria, run the real project checks, and report PASS or actionable FAIL without applying fixes. Use only when the user invokes $verify or explicitly requests independent acceptance verification.
---

# Verify

Perform acceptance verification in a context that did not implement the change

## Workflow

1. Determine the requested scope from the text following `$verify`
2. When no scope is supplied, inspect all current uncommitted changes or all files identified by the parent task
3. Review allowed build and test artifact globs, then capture tracked and non-ignored untracked hashes with `scripts/Test-SourceBoundary.ps1 -Mode Capture` or `scripts/Test-SourceBoundary.sh --capture`
4. Send the scope, acceptance criteria, claimed changes, reviewed commands, and allowed artifact globs to `orchestration_verifier`
5. Require the verifier to inspect the actual change and run the real project commands
6. Verify the snapshot with the matching script and invalidate the verdict if any source changed outside allowed artifact globs
7. Return the verdict and evidence without modifying files

## Verdict requirements

- Return PASS only when every acceptance criterion is met and the reported commands were observed succeeding
- Return FAIL with blocking file and line references, impact, evidence, and the smallest required fix
- Do not apply fixes after FAIL until the user explicitly requests implementation
- If `orchestration_verifier` is unavailable, use a separate read-focused agent context with no source-editing task

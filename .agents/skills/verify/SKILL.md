---
name: verify
description: Independently inspect and validate current code changes against a supplied plan, scope, or acceptance criteria, run the real project checks, and report PASS or actionable FAIL without applying fixes. Use only when the user invokes $verify or explicitly requests independent acceptance verification.
---

# Verify

Perform acceptance verification in a context that did not implement the change

## Workflow

1. Determine the requested scope from the text following `$verify`
2. When no scope is supplied, inspect all current uncommitted changes or all files identified by the parent task
3. Send the scope, acceptance criteria, and claimed changes to `orchestration_verifier`
4. Require the verifier to inspect the actual change and run the real project commands
5. Return the verdict and evidence without modifying files

## Verdict requirements

- Return PASS only when every acceptance criterion is met and the reported commands were observed succeeding
- Return FAIL with blocking file and line references, impact, evidence, and the smallest required fix
- Do not apply fixes after FAIL until the user explicitly requests implementation
- If `orchestration_verifier` is unavailable, use a separate read-focused agent context with no source-editing task

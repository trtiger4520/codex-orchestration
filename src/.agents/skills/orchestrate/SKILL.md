---
name: orchestrate
description: Coordinate an explicitly requested complete orchestration workflow or a high-risk change that modifies security-sensitive behavior or controls, migrates or transforms persisted data or schema, changes production state, changes core architecture, or breaks a public contract.
---

# Orchestrate

Coordinate an `orchestrate-heavy` task while keeping planning, implementation, and verification in separate agent contexts

## Workflow

1. Confirm the operating system and required PowerShell, Bash, Python, or bundled runtime tools, then send the complete request to `orchestration_planner`
2. Require the planner response to contain exactly one fenced JSON task contract, extract it, and write it to an operating-system temporary directory outside the repository
3. Validate the temporary contract before command review, user approval, or dispatch
   - Read `references/orchestration-plan.schema.json` when inspecting or producing the contract
   - On PowerShell, run `scripts/Test-OrchestrationPlan.ps1 -PlanFile <temporary-path>`
   - On Bash, run `scripts/Test-OrchestrationPlan.sh --plan-file <temporary-path>`
   - Require newly produced contracts to use version `1.1` and structured `verify_cmds` entries containing `command`, `cwd`, `purpose`, `timeout_seconds`, and `expected_writes`
4. If extraction or validation fails, report the validator errors and stop without command review, user approval, or dispatch
5. Review the validated contract for verified paths, dependencies, observable acceptance criteria, and safe verification commands
6. Present the validated plan to the user and stop until the user explicitly approves it
7. Require cohesive delivery units rather than separate contract tasks solely for product code, tests, or documentation; after approval, send only unanswered codebase questions to `orchestration_explorer`
8. Before dispatching, check active subagents, available slots, task mode, risk, dependencies, and file-conflict clusters
9. Assign each cohesive approved delivery unit to an `orchestration_implementer`
10. Use available slots for independent read-only work; use the minimum number of writers, run at most two writers, use one writer for high-risk work, and serialize writers that share a file-conflict cluster
11. Integrate the completed subtasks without expanding the approved scope
12. Capture a source-boundary snapshot with the verify skill scripts
13. Send the approved plan and complete change set to `orchestration_verifier`
14. Verify the source boundary afterward using only reviewed `expected_writes`; any other tracked or non-ignored untracked change invalidates the verifier result
15. If verification returns FAIL, send only the blocking items to the original implementer context and verify again in the same verifier context
16. Stop after two failed repair cycles and report the remaining blockers
17. Remove the temporary contract when the workflow ends, whether it succeeds or fails

## Coordination rules

- Keep user communication and approval decisions in the parent task
- Only the parent task may dispatch; every spawned agent must never spawn, delegate to, or invoke another agent
- Prefer native subagent tools and event-driven waiting; never wrap subagent waiting in general `exec`
- If event-driven waiting is unavailable, poll every 30 to 60 seconds and report only state changes
- Pass only task-relevant findings between agents
- Treat the task contract as declarative input for parent-agent dispatch, not as an executable DAG
- Treat verification commands as declarative input; the parent must inspect their working directory, purpose, timeout, and write boundary before execution
- Do not treat an implementer's self-check as independent verification
- Do not declare completion without verifier PASS and observed command evidence
- After a repair, run only failed checks; run the complete relevant suite once after all blockers clear
- Treat test naming, formatting preferences, and traceability concerns with equivalent existing coverage as non-blocking notes
- If an exact custom agent is unavailable, use an equivalent agent only when it preserves the same write boundary and independent context
- Do not assume a service-side model-capacity precheck or a model fallback is available
- Do not change the approved scope, select a named model, or adjust thread limits to increase concurrency
- If dispatch receives `Selected model is at capacity` or an equivalent temporary subagent-availability error, re-dispatch the original role and unchanged subtask after 30 seconds, then 90 seconds
- If both re-dispatch attempts fail, report the original error and the unfinished subtask without expanding or changing the approved scope

## Final report

Report changed files, verification commands and outcomes, acceptance criteria status, and remaining follow-ups

Emit exactly one compact JSON completion record with `delegated_agents` role/count entries and the fields required by the installed orchestration policy; use `null` for unavailable metrics and do not save the record automatically

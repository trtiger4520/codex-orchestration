---
name: orchestrate
description: Coordinate an explicitly requested high-risk or complete orchestration workflow through planning, approval, cohesive implementation, independent verification, and up to two repair cycles. Use only when the user invokes $orchestrate, directly requests the complete workflow, or the work involves security, data migration, production deployment, core architecture, or a breaking public contract.
---

# Orchestrate

Coordinate an `orchestrate-heavy` task while keeping planning, implementation, and verification in separate agent contexts

## Workflow

1. Confirm the operating system and required PowerShell, Bash, Python, or bundled runtime tools, then send the complete request to `orchestration_planner`
2. Review the returned Markdown summary and JSON task contract for verified paths, dependencies, and observable acceptance criteria
   - Read `references/orchestration-plan.schema.json` when inspecting or producing the contract
   - On PowerShell, run `scripts/Test-OrchestrationPlan.ps1 -PlanFile <path>` when a contract is materialized as JSON
   - On Bash, run `scripts/Test-OrchestrationPlan.sh --plan-file <path>` when a contract is materialized as JSON
   - Require newly produced contracts to use version `1.1` and structured `verify_cmds` entries containing `command`, `cwd`, `purpose`, `timeout_seconds`, and `expected_writes`
3. Present the plan to the user and stop until the user explicitly approves it
4. Require cohesive delivery units rather than separate contract tasks solely for product code, tests, or documentation; after approval, send only unanswered codebase questions to `orchestration_explorer`
5. Before dispatching, check active subagents, available slots, task mode, risk, dependencies, and file-conflict clusters
6. Assign each cohesive approved delivery unit to an `orchestration_implementer`
7. Use available slots for independent read-only work; use the minimum number of writers, run at most two writers, use one writer for high-risk work, and serialize writers that share a file-conflict cluster
8. Integrate the completed subtasks without expanding the approved scope
9. Review every verification command, reject unapproved chaining, redirection, package installation, network access, and destructive operations, then capture a source-boundary snapshot with the verify skill scripts
10. Send the approved plan and complete change set to `orchestration_verifier`
11. Verify the source boundary afterward using only reviewed `expected_writes`; any other tracked or non-ignored untracked change invalidates the verifier result
12. If verification returns FAIL, send only the blocking items to the original implementer context and verify again in the same verifier context
13. Stop after two failed repair cycles and report the remaining blockers

## Coordination rules

- Keep user communication and approval decisions in the parent task
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

Emit exactly one compact JSON completion record with the fields required by the installed orchestration policy; use `null` for unavailable metrics and do not save the record automatically

---
name: orchestrate
description: Coordinate an explicitly requested multi-file or multi-step engineering task through planning, user approval, targeted exploration, bounded implementation, independent verification, and up to two repair cycles. Use only when the user invokes $orchestrate or directly requests this complete orchestration workflow.
---

# Orchestrate

Coordinate the parent task while keeping planning, implementation, and verification in separate agent contexts

## Workflow

1. Send the complete request to `orchestration_planner`
2. Review the returned Markdown summary and JSON task contract for verified paths, dependencies, and observable acceptance criteria
   - Read `references/orchestration-plan.schema.json` when inspecting or producing the contract
   - Run `scripts/Test-OrchestrationPlan.ps1 -PlanFile <path>` when a contract is materialized as JSON
3. Present the plan to the user and stop until the user explicitly approves it
4. After approval, send unanswered codebase questions to `orchestration_explorer`
5. Before dispatching, check active subagents, available slots, task mode, risk, dependencies, and file-conflict clusters
6. Assign each approved subtask to a separate `orchestration_implementer`
7. Use available slots for independent read-only work; run at most two writers, use one writer for high-risk work, and serialize writers that share a file-conflict cluster
8. Integrate the completed subtasks without expanding the approved scope
9. Send the approved plan and complete change set to `orchestration_verifier`
10. If verification returns FAIL, send only the blocking items to an implementer and verify again
11. Stop after two failed repair cycles and report the remaining blockers

## Coordination rules

- Keep user communication and approval decisions in the parent task
- Pass only task-relevant findings between agents
- Treat the task contract as declarative input for parent-agent dispatch, not as an executable DAG
- Do not treat an implementer's self-check as independent verification
- Do not declare completion without verifier PASS and observed command evidence
- If an exact custom agent is unavailable, use an equivalent agent only when it preserves the same write boundary and independent context
- Do not assume a service-side model-capacity precheck or a model fallback is available
- Do not change the approved scope, select a named model, or adjust thread limits to increase concurrency
- If dispatch receives `Selected model is at capacity` or an equivalent temporary subagent-availability error, re-dispatch the original role and unchanged subtask after 30 seconds, then 90 seconds
- If both re-dispatch attempts fail, report the original error and the unfinished subtask without expanding or changing the approved scope

## Final report

Report changed files, verification commands and outcomes, acceptance criteria status, and remaining follow-ups

---
name: orchestrate
description: Coordinate an explicitly requested multi-file or multi-step engineering task through planning, user approval, targeted exploration, bounded implementation, independent verification, and up to two repair cycles. Use only when the user invokes $orchestrate or directly requests this complete orchestration workflow.
---

# Orchestrate

Coordinate the parent task while keeping planning, implementation, and verification in separate agent contexts

## Workflow

1. Send the complete request to `orchestration_planner`
2. Review the returned plan for verified paths, dependencies, and observable acceptance criteria
3. Present the plan to the user and stop until the user explicitly approves it
4. After approval, send unanswered codebase questions to `orchestration_explorer`
5. Assign each approved subtask to a separate `orchestration_implementer`
6. Run implementers in parallel only when they share no files and have no dependency
7. Integrate the completed subtasks without expanding the approved scope
8. Send the approved plan and complete change set to `orchestration_verifier`
9. If verification returns FAIL, send only the blocking items to an implementer and verify again
10. Stop after two failed repair cycles and report the remaining blockers

## Coordination rules

- Keep user communication and approval decisions in the parent task
- Pass only task-relevant findings between agents
- Do not treat an implementer's self-check as independent verification
- Do not declare completion without verifier PASS and observed command evidence
- If an exact custom agent is unavailable, use an equivalent agent only when it preserves the same write boundary and independent context

## Final report

Report changed files, verification commands and outcomes, acceptance criteria status, and remaining follow-ups

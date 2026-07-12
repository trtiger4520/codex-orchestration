# Multi-agent orchestration rules

## Trigger and ownership

- Classify each task before delegating: use `single-agent` for routine low-risk work in familiar paths, `plan-light` when a short plan is useful without full role separation, and `orchestrate-heavy` for high-risk work, cross-module changes, unfamiliar paths, independent verification needs, or explicit user requests for orchestration
- Treat file count and step count as planning signals, not automatic triggers for full orchestration
- When the current surface explicitly provides native dynamic delegation and the user did not request this workflow, allow the native capability to lead; do not claim or implement automatic detection of a named Ultra mode
- Keep the main agent responsible for user communication, plan approval, delegation, integration, and the final report
- Use `orchestration_explorer` for broad code search or call-chain tracing instead of adding raw search output to the main context
- Keep delegated reports concise and summarize any report longer than roughly 300 words

## Workflow

1. Ask `orchestration_planner` to inspect the actual project and produce a Markdown summary plus a valid declarative task contract with acceptance criteria
2. Present the plan to the user and wait for explicit approval before changing files
3. Ask `orchestration_explorer` to research unfamiliar code paths when the approved plan needs more evidence
4. Assign one bounded subtask to each `orchestration_implementer`
5. Before dispatching, check active subagents, available slots, task mode, risk, dependencies, and file conflicts
6. Use currently available slots for independent read-only planner or explorer tasks; keep write work to at most two implementers, use one writer for high-risk work, and serialize tasks in the same file-conflict cluster
7. Ask `orchestration_verifier` to inspect the complete change and run the real verification commands
8. Declare completion only after the verifier reports PASS with observed evidence

## Failure handling

- When verification reports FAIL, return only the blocking items to an implementer
- Re-run independent verification after each repair
- Stop after two failed repair cycles and report the remaining blockers
- Do not expand scope while repairing verifier findings

## Subagent availability

- Do not assume a service-side model-capacity precheck or a model fallback is available
- Do not change the approved scope, select a named model, or adjust thread limits to increase concurrency
- If dispatch receives `Selected model is at capacity` or an equivalent temporary subagent-availability error, re-dispatch the original role and unchanged subtask after 30 seconds, then 90 seconds
- If both re-dispatch attempts fail, report the original error and the unfinished subtask without expanding or changing the approved scope

## Verification standards

- Treat tests as passed only when the command was run in the current session and its result was observed
- Prefer the narrowest relevant check during iteration, then run the complete relevant suite once at the end
- Do not accept an implementer's self-report as independent verification evidence

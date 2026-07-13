# Multi-agent orchestration rules

## Lane selection and ownership

- Classify every task before delegating
- Use `single-agent` for routine low-risk work the main agent can complete directly; do not create a subagent or wait for plan approval
- Use `plan-light` by default for non-high-risk work that benefits from a short plan, including work across files, modules, platforms, or unfamiliar paths; the main agent owns the short plan, does not wait for approval unless the user asks, and may assign at most one cohesive delivery unit to one `orchestration_implementer`
- A request for independent verification alone may add only an `orchestration_verifier`; it does not require planner, explorer, or implementer roles
- Use `orchestrate-heavy` only when the user explicitly requests the complete orchestration workflow, or when the work involves security, data migration, production deployment, core architecture, or a breaking public contract
- File count, step count, cross-module scope, cross-platform scope, and unfamiliar paths must not trigger `orchestrate-heavy` by themselves
- Keep the main agent responsible for user communication, approval, integration, and the final report

## Subagent usage reporting

- Before task work begins, report `子代理使用：<是|否>｜模式：<single-agent|plan-light|orchestrate-heavy>｜不使用原因：<...>` after classifying the task; omit `不使用原因` when subagents will be used
- On task completion, report `子代理結果：<已派發，角色與任務：... | 未派發，未使用或派發失敗原因：...>`
- When no subagent was used, state the reason; when dispatch failed, state the observed failure and retry outcome

## Dispatch and coordination

- Before dispatching, confirm the operating system and required verification toolchain, including PowerShell, Bash, Python, and any bundled runtime needed by the task
- Prefer native subagent tools and event-driven waiting; never wrap subagent waiting in a general `exec` command
- When event-driven waiting is unavailable, poll every 30 to 60 seconds and report only state changes
- Keep delegated reports concise and summarize reports longer than roughly 300 words
- For `plan-light`, use no more than one cohesive implementer; group product code, tests, and documentation together when they form one delivery unit
- For `orchestrate-heavy`, ask `orchestration_planner` to inspect the project and group the contract by cohesive delivery units rather than mechanically separating product code, tests, and documentation
- Present the heavy plan and wait for explicit user approval before changing files
- After approval, check available slots and use `orchestration_explorer` only for unanswered code-path questions; use the minimum number of writers, at most two writers, and one writer for high-risk work
- Send the complete approved change to one independent `orchestration_verifier`

## Repair and verification

- On verifier FAIL, return only blocking findings to the original implementer context whenever it is available
- Reuse the same independent verifier context for follow-up verification
- After each repair, run only the previously failed or narrowest relevant checks; run the complete relevant suite once after all blockers are cleared
- Treat test naming, formatting preferences, and traceability concerns with equivalent existing coverage as non-blocking notes
- Stop after two failed repair cycles and report the remaining blockers
- Do not expand scope while repairing findings
- Treat tests as passed only when the command was run in the current session and its result was observed
- Do not accept an implementer's self-report as independent verification evidence

## Subagent availability

- Do not assume a service-side model-capacity precheck or model fallback is available
- Do not change the approved scope, select a named model, or adjust thread limits to increase concurrency
- If dispatch receives `Selected model is at capacity` or an equivalent temporary availability error, re-dispatch the original role and unchanged subtask after 30 seconds, then 90 seconds
- If both retries fail, report the original error and unfinished subtask without changing scope

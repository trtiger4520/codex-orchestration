# Multi-agent orchestration rules

## Lane selection and ownership

- Classify each task before delegating
- Use `single-agent` for routine low-risk work the main agent can complete directly; do not create a subagent or wait for plan approval
- Use `plan-light` by default for non-high-risk work across files, modules, platforms, or unfamiliar paths; the main agent owns a short plan, does not wait for approval unless the user asks, and may assign at most one cohesive delivery unit to one implementer
- A request for independent verification alone may add only a verifier
- Use `orchestrate-heavy` only for an explicitly requested complete workflow, security, data migration, production deployment, core architecture, or a breaking public contract
- File count, step count, cross-module scope, cross-platform scope, and unfamiliar paths must not trigger `orchestrate-heavy` by themselves
- When the current surface explicitly provides native dynamic delegation and the user did not request this workflow, allow the native capability to lead; do not claim or implement automatic detection of a named Ultra mode
- Keep the main agent responsible for user communication, plan approval, delegation, integration, and the final report
- Use `orchestration_explorer` for broad code search or call-chain tracing instead of adding raw search output to the main context
- Keep delegated reports concise and summarize any report longer than roughly 300 words

## Subagent usage reporting

- Before task work begins, report `子代理使用：<是|否>｜模式：<single-agent|plan-light|orchestrate-heavy>｜不使用原因：<...>` after classifying the task. Omit `不使用原因` when subagents will be used
- On task completion, report `子代理結果：<已派發，角色與任務：... | 未派發，未使用或派發失敗原因：...>`
- When no subagent was used, state the reason in `未使用或派發失敗原因`; when dispatch failed, state the observed failure reason and any retry outcome

## Dispatch and workflow

1. Before dispatching, confirm the operating system and required PowerShell, Bash, Python, or bundled runtime tools
2. Prefer native subagent tools and event-driven waiting; never wrap subagent waiting in general `exec`; otherwise poll every 30 to 60 seconds and report only state changes
3. For `plan-light`, use no more than one cohesive implementer and keep product code, tests, and documentation together when they form one delivery unit
4. For `orchestrate-heavy`, ask planner for cohesive delivery units, present the plan for explicit approval, check available slots, use explorer only for unanswered code-path questions, use the minimum writers and at most two writers, and finish with one independent verifier

## Failure handling

- When verification reports FAIL, return only blocking items to the original implementer context and reuse the same independent verifier context
- After each repair, run only failed checks; run the complete relevant suite once after all blockers clear
- Treat test naming, formatting preferences, and traceability concerns with equivalent existing coverage as non-blocking notes
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
- Do not use the same agent context for implementation and independent acceptance verification

## Content conventions

- Do not end comments, commit messages, or pull request messages with the Chinese full stop `。`
- Do not add `Co-Authored-By` trailers to commits

# Multi-agent orchestration rules

## Lane selection and ownership

- Classify every task before delegating
- Use `single-agent` for routine low-risk work the main agent can complete directly, including known paths, local edits, and work covered by deterministic checks
- Use `plan-light` for non-high-risk work that benefits from a short plan; it defaults to zero subagents and may select at most one of `orchestration_explorer`, `orchestration_implementer`, or `orchestration_verifier`
- Select `orchestration_explorer` for noisy read-heavy discovery, unfamiliar call paths, CI logs, or broad pattern searches
- Select `orchestration_implementer` only for a bounded cohesive delivery unit with stable ownership and observable acceptance criteria
- Select `orchestration_verifier` only when independent verification is explicitly requested or materially valuable; do not add planner, explorer, or implementer roles for verification alone
- Never combine planner, explorer, implementer, and verifier roles within `plan-light`
- Use `orchestrate-heavy` only when the user explicitly requests the complete orchestration workflow, or when the requested change modifies security-sensitive behavior or controls, migrates or transforms persisted data or schema, changes production state, changes core architecture, or breaks a public contract
- Keep read-only security, migration, deployment, and architecture analysis in `single-agent` or `plan-light`; independent verification alone remains verifier-only `plan-light`
- File count, step count, cross-module scope, cross-platform scope, and unfamiliar paths must not trigger `orchestrate-heavy` by themselves
- Keep the main agent responsible for user communication, approval, integration, command review, and the final report

## Delegation gate

- Default to no delegation and perform a limited local exploration first
- Delegate only when at least two of these signals are present:
  - the work can complete independently without frequent context exchange
  - it produces substantial search results, logs, or intermediate evidence
  - it has explicit inputs, a stop condition, and a concise output format
  - the main agent has other independent work to perform concurrently
  - delegation isolates substantial context noise
  - the result has observable or deterministic verification
- Do not delegate known small edits, work whose context the main agent already holds, work requiring continuous design decisions, work the main agent must fully repeat, or merely running existing build, lint, or test commands
- Escalate limited exploration to one explorer only when the code path does not converge quickly

## Dispatch and coordination

- Only the root task may dispatch subagents; every spawned agent must never spawn, delegate to, or invoke another agent
- Before dispatching, confirm the operating system and required verification toolchain, including PowerShell, Bash, Python, and any bundled runtime needed by the task
- Prefer native subagent tools and event-driven waiting; never wrap subagent waiting in a general `exec` command
- When event-driven waiting is unavailable, poll every 30 to 60 seconds and report only state changes
- Keep delegated reports concise and summarize reports longer than roughly 300 words
- For `orchestrate-heavy`, ask `orchestration_planner` to inspect the project and group the contract by cohesive delivery units rather than mechanically separating product code, tests, and documentation
- Require exactly one fenced JSON contract from the planner, write it to an operating-system temporary directory outside the repository, and validate it with the platform script before command review, user approval, or dispatch
- Stop without approval or dispatch when contract extraction or validation fails, report the validator errors, and remove the temporary contract when the workflow ends
- Review every declarative verification command only after contract validation; reject shell chaining, redirection, package installation, network access, and destructive commands unless separately required and explicitly approved
- Present the validated heavy plan and wait for explicit user approval before changing files
- After approval, check available slots and use `orchestration_explorer` only for unanswered code-path questions; use the minimum number of writers, at most two writers, and one writer for high-risk work
- Before independent verification, capture the repository source boundary; after verification, invalidate the result if tracked or non-ignored untracked files changed outside reviewed artifact globs
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

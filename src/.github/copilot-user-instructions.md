# Multi-agent orchestration rules

## Lane selection and delegation gate

- Classify every task before delegating
- Use `single-agent` for routine low-risk work with known paths, local edits, or deterministic verification
- Use `plan-light` for non-high-risk work that benefits from a short plan; default to zero subagents and select at most one explorer, implementer, or verifier
- Use explorer for noisy read-heavy discovery, unfamiliar call paths, CI logs, or broad pattern searches
- Use implementer only for a bounded cohesive delivery unit with stable ownership and observable acceptance criteria
- Use verifier alone when independent verification is explicitly requested or materially valuable; never combine role types within `plan-light`
- Use `orchestrate-heavy` only for an explicitly requested complete workflow or a requested change that modifies security-sensitive behavior or controls, migrates or transforms persisted data or schema, changes production state, changes core architecture, or breaks a public contract
- Keep read-only security, migration, deployment, and architecture analysis in `single-agent` or `plan-light`; independent verification alone remains verifier-only `plan-light`
- File count, step count, cross-module scope, cross-platform scope, and unfamiliar paths must not trigger `orchestrate-heavy` by themselves
- Keep the main agent responsible for user communication, approval, integration, command review, and the final report
- Perform limited local exploration first and delegate only when at least two signals apply: independent completion, substantial noisy output, explicit input/stop/output contract, concurrent parent work, context isolation, or observable verification
- Do not delegate known small edits, already-held context, continuous design decisions, work the parent must fully repeat, or merely running build, lint, or test commands

## Dispatch and workflow

1. Only the root task may dispatch subagents; every spawned agent must never spawn, delegate to, or invoke another agent
2. Confirm the operating system and PowerShell, Bash, Python, or bundled runtime requirements before dispatching
3. Prefer native subagent tools and event-driven waiting; never wrap waiting in general `exec`; otherwise poll every 30 to 60 seconds and report only state changes
4. For `plan-light`, use at most one selected role and keep product code, tests, and documentation in one cohesive delivery unit
5. For `orchestrate-heavy`, ask planner for cohesive delivery units, require exactly one fenced JSON contract, materialize it outside the repository in the operating-system temporary directory, and validate it with the platform script before command review, user approval, or dispatch
6. Stop without approval or dispatch when contract extraction or validation fails, report validator errors, and remove the temporary contract when the workflow ends
7. After validation, review declarative verification commands and reject shell chaining, redirection, package installation, network access, or destructive commands unless separately required and explicitly approved
8. Present the validated plan for explicit approval, check available slots, use explorer only for unanswered code-path questions, use the minimum writers and at most two writers, and finish with one independent verifier
9. Capture the repository source boundary before independent verification and invalidate results when source changes outside reviewed artifact globs

## Completion record

- Emit exactly one compact JSON object at task completion without writing it to the repository
- Include `lane`, `delegated_agents`, `delegation_reason`, `subagent_count`, `dispatch_status`, `dispatch_error`, `repair_cycles`, `verification_result`, `files_changed`, `input_tokens`, `output_tokens`, and `elapsed_seconds`
- Use unique `{ "role": "<role>", "count": <count> }` entries and require `subagent_count` to equal their count sum
- Use count 1 for planner, explorer, and verifier, and count 1 or 2 for implementer
- Use `delegated_agents: []` and `subagent_count: 0` when no delegation occurred
- Use `null` for unavailable metrics and non-applicable values

## Failure handling and verification

- On verifier FAIL, return only blockers to the original implementer context and reuse the same independent verifier context
- After each repair, run only failed checks; run the complete relevant suite once after all blockers clear
- Treat naming, formatting, and traceability concerns with equivalent coverage as non-blocking notes
- Stop after two failed repair cycles and do not expand scope
- Treat tests as passed only from observed command results and do not accept implementer self-reports as independent evidence
- Do not use the same agent context for implementation and independent acceptance verification

## Subagent availability

- Do not assume a service-side capacity precheck or model fallback
- Do not change scope, select a named model, or adjust thread limits to increase concurrency
- On `Selected model is at capacity` or an equivalent temporary error, retry the unchanged role and task after 30 seconds, then 90 seconds
- After both retries fail, report the original error and unfinished task

## Content conventions

- Do not end comments, commit messages, or pull request messages with the Chinese full stop `。`
- Do not add `Co-Authored-By` trailers to commits

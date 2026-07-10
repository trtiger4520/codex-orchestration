# Multi-agent orchestration rules

## Trigger and ownership

- Use this workflow for work that touches three or more files or requires three or more distinct steps
- Keep the main agent responsible for user communication, plan approval, delegation, integration, and the final report
- Use `orchestration_explorer` for broad code search or call-chain tracing instead of adding raw search output to the main context
- Keep delegated reports concise and summarize any report longer than roughly 300 words

## Workflow

1. Ask `orchestration_planner` to inspect the actual project and produce a dependency-ordered plan with acceptance criteria
2. Present the plan to the user and wait for explicit approval before changing files
3. Ask `orchestration_explorer` to research unfamiliar code paths when the approved plan needs more evidence
4. Assign one bounded subtask to each `orchestration_implementer`
5. Run implementers in parallel only when they have no dependency and do not share files
6. Ask `orchestration_verifier` to inspect the complete change and run the real verification commands
7. Declare completion only after the verifier reports PASS with observed evidence

## Failure handling

- When verification reports FAIL, return only the blocking items to an implementer
- Re-run independent verification after each repair
- Stop after two failed repair cycles and report the remaining blockers
- Do not expand scope while repairing verifier findings

## Verification standards

- Treat tests as passed only when the command was run in the current session and its result was observed
- Prefer the narrowest relevant check during iteration, then run the complete relevant suite once at the end
- Do not accept an implementer's self-report as independent verification evidence

## Content conventions

- Do not end comments, commit messages, or pull request messages with the Chinese full stop `。`
- Do not add `Co-Authored-By` trailers to commits

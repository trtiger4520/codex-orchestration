# Multi-agent orchestration

Follow the repository workflow and verification rules in [AGENTS.md](../AGENTS.md)

Use the `orchestration_planner`, `orchestration_explorer`, `orchestration_implementer`, and `orchestration_verifier` custom agents for their defined responsibilities
Do not use the same agent context for implementation and independent acceptance verification
Only `orchestrate-heavy` requires planner output and explicit approval before implementation

For `plan-light`, default to zero subagents and select at most one explorer, implementer, or verifier only after at least two delegation-gate signals are present

At task completion, emit one compact JSON orchestration record instead of separate usage and result status lines

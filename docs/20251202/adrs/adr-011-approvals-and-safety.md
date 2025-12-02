# ADR-011: Expand Approvals and Safety Hooks

Status: Proposed

Context
- Python: MCP approvals via `HostedMCPTool.on_approval_request` with request/response items and streaming events; computer safety checks via `ComputerTool.on_safety_check` acknowledging `PendingSafetyCheck`; guardrail tripwires halt runs; shell executors are user-provided for sandboxing.
- Elixir: central `Codex.Approvals` handles binary-marked approvals; no per-tool approval hooks, no safety acknowledgements for computer actions, MCP approvals not surfaced.

Decision
- Add per-tool approval callbacks (MCP approval requests, computer safety checks) surfaced as events/tool outputs; integrate with runner before continuing tool processing.
- Keep global approvals for binary-provided requirements but merge with tool-level hooks; record telemetry/tracing for approve/deny/timeout.
- Provide shell executor interface with timeout/output caps and optional approval gate.

Consequences
- Benefits: granular control over sensitive operations; matches Python streaming and approval UX.
- Risks: complexity in combining global and tool-specific approvals; potential deadlocks if callbacks block; security-sensitive defaults must be conservative.
- Actions: define approval event structures; integrate into `_run_impl` equivalent; update telemetry; add tests akin to `tests/mcp/test_message_handler.py`, `tests/test_computer_action.py`, `tests/test_shell_tool.py`, and guardrail tripwire suites.

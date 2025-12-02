Python
- `src/agents/tool.py:249-271` `ComputerTool` exposes `on_safety_check` callback to acknowledge `PendingSafetyCheck` before actions proceed, enabling human approval hooks.
- `src/agents/tool.py:274-316` `HostedMCPTool` accepts `on_approval_request`; approvals are surfaced as `McpApprovalRequest` items and routed back via callback.
- `_run_impl.py:348-355` executes pending MCP approvals before other tools, converting approval results into `MCPApprovalResponseItem`s; `_run_impl.py:1295-1325` wraps approval callbacks and builds response items. Streaming emits approval request/response events (`_run_impl.py:1417-1420`).
- Shell tools (`tool.py:347-454`) rely on user-provided executors (`LocalShellExecutor`/`ShellExecutor`), leaving sandboxing/policy enforcement to the host application.
- Handoff/input guardrails can pre-empt execution by raising tripwire exceptions (`run.py:616-645`, `_run_impl.py:473-521`), acting as approval gates for user-defined logic.

Elixir status
- Approval flow is centralized in `lib/codex/approvals.ex`, invoked by auto-run when codex marks actions as requiring consent; supports static policy or custom hook with telemetry but no tool-specific callbacks.
- No explicit safety acknowledgement hook for computer-use equivalents; codex events may carry `requires_approval` flags but SDK tooling does not expose per-tool callbacks.
- MCP approval handling is minimal; no request/response plumbing beyond handshake.
- Shell execution is mediated by codex binary; SDK does not expose sandbox policies per call.

Gaps/deltas
- Missing MCP approval request surfacing and callback handling; approvals are not streamed or converted to tool outputs.
- No safety-check callbacks for computer actions; approvals are global rather than tool-specific.
- Shell policy hooks (timeout/max output/messages) must be implemented in SDK; Python leaves executor-provided enforcement.

Porting steps + test plan
- Add MCP approval request handling that surfaces `McpApprovalRequest` events and routes to a user callback, returning approval/denial items; mirror `tests/mcp/test_server_errors.py` and `tests/mcp/test_tool_filtering.py`.
- Extend tool pipeline to support per-tool approval hooks (computer safety, hosted MCP) and stream approval events; add integration tests analogous to `tests/test_computer_action.py` and `tests/mcp/test_message_handler.py`.
- Provide shell executor interfaces with sandbox controls (timeout/output caps) and approval tie-in; validate with parity tests from `tests/test_shell_tool.py` and `tests/test_local_shell_tool.py`.
- Wire guardrail tripwire errors into approval telemetry to keep parity with `Codex.Approvals` semantics; add coverage for denial/timeouts.***

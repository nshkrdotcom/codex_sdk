# ADR-006: Implement MCP Integration with Tool Filtering, Retries, and Approvals

Status: Proposed

Context
- Python: `src/agents/mcp/server.py` and `src/agents/mcp/util.py` support stdio/SSE/streamable HTTP MCP servers with tool caching, retries, tool filtering (allow/block or dynamic via run_context/agent), structured-content toggle, and per-message handlers. Hosted MCP tool (`tool.py:300-320`) includes approval callbacks; runner executes MCP approvals (`_run_impl.py:348-355`, `1295-1325`) and streams events.
- Elixir: `lib/codex/mcp/client.ex` only handles handshake; no tool discovery, filtering, retries, or approvals; hosted MCP calls not surfaced.

Decision
- Build MCP client layer that lists/calls tools with caching and optional retries/backoff; support stdio/SSE/HTTP transports and dynamic tool filters requiring run_context/agent.
- Add hosted MCP tool config exposing server URL and approval callback; surface approval requests/responses as events and tool outputs.
- Emit tracing/telemetry for MCP list_tools/call_tool with error attachment; provide structured-content toggle.

Consequences
- Benefits: unlocks MCP servers for Elixir agents with parity behaviors; approval flow matches Python.
- Risks: transport complexity and error handling; approval hooks must be safe and time-bounded; tracing volume may increase.
- Actions: design MCP transport abstractions, caching, and retry policy; integrate with runner tool resolution; add tests akin to `tests/mcp/test_runner_calls_mcp.py`, `tests/mcp/test_tool_filtering.py`, `tests/mcp/test_client_session_retries.py`, `tests/mcp/test_mcp_tracing.py`.

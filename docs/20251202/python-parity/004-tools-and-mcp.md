Python
- `src/agents/tool.py:134-189` `FunctionTool` wraps python callables with JSON schema, async invoke hook, strict schema toggle, dynamic `is_enabled`, and optional tool-specific guardrails. Structured tool outputs (`ToolOutputText/Image/FileContent` at `tool.py:53-125`) serialize into Responses input types via `ItemHelpers.tool_call_output_item` (`items.py:429-520`).
- `src/agents/tool.py:194-483` built-in hosted tools: `FileSearchTool` (vector store search), `WebSearchTool`, `ComputerTool` with safety check callback, `HostedMCPTool` with approval hook, `ShellTool`/`LocalShellTool` (next-gen and legacy shells), `ApplyPatchTool` (hosted diff application), `ImageGenerationTool`, `CodeInterpreterTool`.
- `src/agents/tool_guardrails.py:18-199` supplies tool input/output guardrails with behaviors (`allow`, `reject_content` with message back to model, `raise_exception` tripwire) and data objects (`ToolInputGuardrailData`, `ToolOutputGuardrailData`).
- `src/agents/_run_impl.py:189-753` parses model output into tool runs (function, handoff, computer, shell, apply_patch, hosted MCP), enforces tool guardrails, executes calls, and aggregates tool usage per agent. Honors agent `tool_use_behavior` and `reset_tool_choice`.
- `src/agents/mcp/server.py:32-320` defines MCP servers with caching, retries, and tool filtering (allow/block lists or dynamic callbacks requiring run_context/agent). Supports stdio, SSE, and streamable HTTP clients with message handlers and structured-content toggle.
- `src/agents/mcp/util.py:14-210` converts MCP tools to Agents `FunctionTool`, handles retries, error wrapping, and optional schema strictification; emits tracing spans for list_tools/call_tool. `Agent.get_mcp_tools` uses this with `convert_schemas_to_strict` flag (`agent.py:103-108`).

Elixir status
- Tools are simple module registrations via `Codex.Tools.register/2`; no built-in hosted tool catalog or structured output helpers.
- No tool-level guardrails or behaviors (reject/exception messaging) comparable to `tool_guardrails`.
- MCP support limited to handshake in `lib/codex/mcp/client.ex` and metadata structs in `lib/codex/items.ex`; no dynamic tool discovery, filtering, or hosted MCP tool execution.
- Shell/patch/computer/file/web/image/code-interpreter hosted tools are not exposed; codex binary likely implements subset but SDK does not surface configuration.

Gaps/deltas
- Missing function_tool decorator equivalents (schema extraction, docstring parsing, dynamic enablement) and structured tool output conversions to responses-style items.
- No support for hosted tools (file_search/web_search/computer/shell/apply_patch/hosted_mcp/image_generation/code_interpreter) or their safety/approval hooks.
- Tool guardrails absent, meaning no ability to reject or halt tool calls within SDK.
- MCP server integration (cache, retries, tool filtering, structured_content) not present; Elixir only performs handshake.

Porting steps + test plan
- Add a function-tool wrapper that builds JSON schemas (with strict option) and handles dynamic enablement; port tests like `tests/test_function_tool.py`, `tests/test_function_tool_decorator.py`, and `tests/test_streaming_tool_call_arguments.py`.
- Implement structured tool outputs (text/image/file) and conversion utilities; validate with `tests/test_tool_output_conversion.py` and `tests/test_tool_choice_reset.py`.
- Surface hosted tool configs mapped to codex capabilities (file/web search, code interpreter, shell, apply_patch, computer); add approval/safety callbacks; mirror behaviors tested in `tests/test_shell_tool.py`, `tests/test_apply_patch_tool.py`, `tests/test_computer_action.py`, and `tests/test_tool_use_behavior.py`.
- Introduce tool input/output guardrails with behaviors, raising errors consistent with `ToolGuardrailTripwireTriggered`; cover via `tests/test_tool_guardrails.py`.
- Expand MCP client support to list/call tools with filters and retries; add strict-schema conversion flag and tracing events; replicate `tests/mcp/test_runner_calls_mcp.py`, `tests/mcp/test_tool_filtering.py`, and `tests/mcp/test_mcp_tracing.py`.***

Python
- `src/agents/__init__.py:8-170` exports the public surface: `Agent`/`AgentBase`, `Runner.run/run_sync/run_streamed`, `RunConfig`, `RunResult`/`RunResultStreaming`, `function_tool`/`Tool` variants (file_search, web_search, computer_use_preview, hosted_mcp, shell/local_shell, apply_patch, image_generation, code_interpreter), guardrail decorators, handoffs, prompts, sessions (`Session`, `SQLiteSession`, `OpenAIConversationsSession`), model providers, tracing helpers, and config setters.
- `src/agents/agent.py:76-365` defines `Agent` with instructions/prompt, handoffs, model or provider override, model_settings defaults, input/output guardrails, output_type schemas, hooks, `tool_use_behavior` modes, `reset_tool_choice`, validation, and shallow `clone`. `as_tool` wraps an agent as a callable tool with its own max_turns/run_config hooks (`agent.py:381-440`).
- `src/agents/handoffs/__init__.py:41-195` exposes `Handoff` objects, input filters/history mapping, per-handoff enablement, and helpers to generate tool names/descriptions; supports strict schemas and dynamic enablement.
- `src/agents/run.py:179-267` `RunConfig` carries model/provider overrides, handoff history controls, input/output guardrails, tracing flags/metadata, session handling, and `call_model_input_filter`. `Runner` entrypoints (`run`, `run_sync`, `run_streamed` at `run.py:294-510`) enforce max_turns, manage session histories, handle conversation_id/previous_response_id resume, and expose streaming via `RunResultStreaming`.
- `src/agents/result.py:41-199` describes `RunResult`/`RunResultStreaming` shape, `final_output_as`, `last_response_id`, agent reference release, and streaming queue semantics.
- `src/agents/tool.py:134-483` defines `FunctionTool` plus hosted tools (`FileSearchTool`, `WebSearchTool`, `ComputerTool`, `HostedMCPTool`, `ShellTool`/`LocalShellTool`, `ApplyPatchTool`, `ImageGenerationTool`, `CodeInterpreterTool`) and structured tool outputs (`ToolOutputText/Image/FileContent`).
- `src/agents/guardrail.py:71-186` provides `InputGuardrail`/`OutputGuardrail` types and decorators with optional parallel execution.
- `src/agents/memory/session.py:10-99` declares the `Session` protocol/ABC for pluggable history stores; `sqlite_session.py` and `openai_conversations_session.py` provide concrete stores.

Elixir status
- Public entrypoints live in `lib/codex.ex` and `lib/codex/thread.ex` (e.g., `Codex.start_thread/2`, `Codex.Thread.run/3`, `Codex.Thread.run_streamed/3`, `Codex.Thread.run_auto/3`), with configuration via `Codex.Options` and `Codex.Thread.Options`.
- Tool registration is limited to `Codex.Tools.register/invoke` with schema metadata; no built-in hosted tool types comparable to Python’s set.
- No agent structs analogous to Python `Agent` or handoff abstractions; turns are driven by the codex binary interface.
- Sessions are implicit via codex exec continuation tokens; no public session protocol like Python’s `Session`.

Gaps/deltas
- Missing rich agent graph API (handoffs, prompts, hooks, guardrails, tool_use_behavior toggles).
- No exposed per-run config equivalent to `RunConfig` (call_model_input_filter, trace metadata, session callbacks, handoff history mappers).
- Lacks Python’s built-in hosted tools and structured tool output helpers.
- No public streaming result object with event queue semantics akin to `RunResultStreaming`.
- Session interface and pluggable stores absent; resume relies solely on codex continuation tokens.

Porting steps + test plan
- Introduce an `Agent`-like struct with instructions/tools/handoffs/hooks mirrored from `src/agents/agent.py`, plus a `RunConfig` equivalent for per-run overrides; surface through `Codex` module. Add unit coverage mirroring `tests/test_run.py` and `tests/test_run_config.py` for validation and defaults.
- Add handoff abstraction (tool name/description, input filters, history nesting) following `src/agents/handoffs/__init__.py` and cover with parity tests similar to `tests/test_handoff_tool.py`.
- Expand tool surface to include hosted tool types and structured tool outputs, aligning type validations with `tool.py`; port tests such as `tests/test_tool_output_conversion.py` and `tests/test_tool_metadata.py`.
- Implement session protocol with SQLite/OpenAI conversation backends analogous to `memory/session.py` and `memory/sqlite_session.py`; add integration tests for multi-turn memory like `tests/test_session.py` and `tests/test_openai_conversations_session.py`.
- Provide streaming result wrapper with event emission comparable to `RunResultStreaming`; validate via streamed runner tests (`tests/test_agent_runner_streamed.py`, `tests/test_openai_chatcompletions_stream.py`).***

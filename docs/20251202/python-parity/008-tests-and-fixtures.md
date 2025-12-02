Python
- Core runner/loop: `tests/test_run.py`, `tests/test_agent_runner.py`, `tests/test_agent_runner_streamed.py`, `tests/test_max_turns.py`, `tests/test_run_step_execution.py`, `tests/test_run_step_processing.py`, `tests/test_agent_as_tool.py`, `tests/test_agent_clone_shallow_copy.py`.
- Guardrails: `tests/test_guardrails.py`, `tests/test_tool_guardrails.py`, `tests/test_stream_input_guardrail_timing.py`, `tests/test_output_tool.py` (structured outputs), `tests/test_run_hooks.py`.
- Tools: `tests/test_function_tool.py`, `tests/test_function_tool_decorator.py`, `tests/test_tool_output_conversion.py`, `tests/test_tool_metadata.py`, `tests/test_shell_tool.py`, `tests/test_local_shell_tool.py`, `tests/test_apply_patch_tool.py`, `tests/test_computer_action.py`, `tests/test_handoff_tool.py`, `tests/test_tool_use_behavior.py`.
- MCP: `tests/mcp/test_runner_calls_mcp.py`, `tests/mcp/test_tool_filtering.py`, `tests/mcp/test_client_session_retries.py`, `tests/mcp/test_prompt_server.py`, `tests/mcp/test_mcp_tracing.py`, `tests/mcp/test_streamable_http_client_factory.py`.
- Streaming/tracing/errors: `tests/test_tracing_errors.py`, `tests/test_tracing_errors_streamed.py`, `tests/test_cancel_streaming.py`, `tests/test_soft_cancel.py`, `tests/test_responses_tracing.py`, `tests/test_responses.py`.
- Sessions/memory: `tests/test_session.py`, `tests/test_openai_conversations_session.py`; fixtures in `tests/utils/simple_session.py`.
- Realtime/voice: `tests/realtime/*` (runner, session, playback tracker, model events) and `tests/voice/*` (input pipeline, openai stt/tts, workflow) show additional surfaces not present in Elixir.
- Fixtures/helpers: `tests/fake_model.py`, `tests/utils/test_json.py`, `tests/testing_processor.py`, `tests/fastapi/streaming_app.py` (streaming harness), MCP helpers in `tests/mcp/helpers.py`.

Elixir status
- Existing tests focus on codex exec contract and basic attachments/auto-run (`test/integration/attachment_pipeline_test.exs`, `test/codex/thread_auto_run_test.exs`, `test/codex/tools_test.exs`, `test/contract/thread_parity_test.exs`), with limited tool and MCP coverage.

Gaps/deltas
- No parity fixtures for guardrails, hosted tools, MCP filtering/retries, or session behaviors.
- Realtime/voice scenarios entirely absent.
- Streaming and tracing error cases under-tested relative to Python.

Porting steps + test plan
- Mirror Python test categories with Elixir equivalents: runner loop semantics, guardrails, tool behaviors (including shell/apply_patch/computer), MCP retries/filters, session persistence, and streaming error propagation.
- Reuse Python fixtures where possible (e.g., fake models, simple session) by porting to Elixir test helpers; add codex-specific fixtures for approval flows and attachment staging.
- Decide on realtime/voice scope; if deferred, document exclusion and add minimal regression tests to ensure unsupported features fail predictably.***

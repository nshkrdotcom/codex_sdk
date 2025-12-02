Python
- `src/agents/run.py:548-750` drives the core agent loop: resolves enabled tools/handoffs, enforces `max_turns` with `MaxTurnsExceeded`, runs input guardrails (sequential + parallel), executes a single turn, aggregates tool guardrail results, and either returns final output, performs handoff, or reruns based on `NextStep*`.
- `src/agents/run.py:129-171` `_ServerConversationTracker` tracks server-side items for `conversation_id`/`previous_response_id` resume and ensures inputs avoid resending already-seen items.
- `src/agents/run.py:1903-1940` `_prepare_input_with_session` merges session history with new input (requires `session_input_callback` when passing list input) and `_save_result_to_session` persists original input plus new items per turn.
- `src/agents/run.py:765-843` `run_sync` reuses or creates the thread default event loop to keep session locks bound to the same loop and cancels tasks on interruption.
- `src/agents/run.py:1030-1207` `_start_streaming` mirrors the turn loop for streaming: emits `AgentUpdatedStreamEvent`, streams guardrail results, supports soft cancel after turn, and publishes `QueueCompleteSentinel` on completion or max_turns.
- `src/agents/_run_impl.py:189-353` processes model responses into tool/handoff actions, executes tool guardrails, and determines when tool output counts as final output (respecting `tool_use_behavior` and pending approvals). Handoff flow nests history or applies custom filters based on `RunConfig`.
- `src/agents/handoffs/history.py:9-86` manages nesting/flattening conversation history during handoffs, with configurable wrappers via `set_conversation_history_wrappers`.

Elixir status
- `lib/codex/thread.ex:63-183` runs a single turn via the codex binary, emits telemetry, and wraps results; `run_streamed/3` streams codex events; `run_auto/3` retries while continuation tokens remain.
- No notion of guardrails, handoff routing, or tool-use behaviors; turns are single codex invocations.
- Resume relies on codex continuation tokens, not `conversation_id` or `previous_response_id`.
- No session memory abstraction; history persistence is delegated to codex binary sessions.
- Streaming emits codex event stream directly without semantic event queue or soft-cancel hooks.

Gaps/deltas
- Missing multi-turn agent loop semantics (re-entering model after tools, handoff transitions, tool_use_behavior options).
- No guardrail pipeline (input/output/tool-level) or error types for tripwires.
- Lacks session merge logic and callbacks for shaping history; continuation-only resume differs from Python’s conversation/session handling.
- Streaming layer lacks semantic events (`RunItemStreamEvent`, `AgentUpdatedStreamEvent`), soft cancel, or guardrail streaming.
- No `previous_response_id`/`conversation_id` resume handling.

Porting steps + test plan
- Implement an agent turn loop that can rerun after tools/handoffs, honoring `max_turns` and `tool_use_behavior`; validate with parity cases from `tests/test_max_turns.py`, `tests/test_tool_use_behavior.py`, and `tests/test_agent_runner.py`.
- Add guardrail support (input/output/tool) with tripwire errors; mirror coverage from `tests/test_guardrails.py`, `tests/test_tool_guardrails.py`, and `tests/test_stream_input_guardrail_timing.py`.
- Introduce session/history layer compatible with codex (or shims) with merge callbacks and list-input validation; test against scenarios in `tests/test_session.py` and `tests/test_openai_conversations_session.py`.
- Enhance streaming wrapper to emit semantic events and soft-cancel behavior; port tests like `tests/test_agent_runner_streamed.py`, `tests/test_cancel_streaming.py`, and `tests/test_tracing_errors_streamed.py`.
- Add resume support for conversation_id/previous_response_id equivalents if codex exposes them; otherwise document limitations and add regression tests for continuation tokens (`test/integration/turn_resumption_test.exs`).***

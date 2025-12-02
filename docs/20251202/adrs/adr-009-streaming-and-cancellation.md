# ADR-009: Align Streaming Semantics and Soft Cancellation

Status: Proposed

Context
- Python: `RunResultStreaming` exposes semantic events (`RunItemStreamEvent`, `AgentUpdatedStreamEvent`, `RawResponsesStreamEvent`) and queues; `_start_streaming` supports soft cancel (`after_turn`), streams guardrail results, and maintains usage/agent state mid-run (`run.py:1030-1207`).
- Elixir: `Thread.run_streamed/3` wraps codex event stream without semantic event objects or soft-cancel support; no guardrail streaming.

Decision
- Add streaming result struct with event queue API and semantic event types mirroring Python; keep compatibility with existing raw event stream when desired.
- Implement soft-cancel states (immediate vs after_turn) and ensure runner stops gracefully, persisting session history before exit.
- Stream guardrail/tool approval events and agent updates to consumers.

Consequences
- Benefits: richer streaming UX, parity with Python tests, safer cancellation semantics.
- Risks: requires buffering/translation of codex events; potential latency overhead; soft-cancel may be limited by codex binary capabilities.
- Actions: design streaming structs/events; map codex stream to semantic events; add cancel handling; test against `tests/test_agent_runner_streamed.py`, `tests/test_cancel_streaming.py`, `tests/test_soft_cancel.py`, `tests/test_tracing_errors_streamed.py`.

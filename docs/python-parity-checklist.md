# Python Parity Checklist

This checklist tracks coverage of Python Codex SDK features in the Elixir port. Each entry notes the canonical fixture, associated Elixir tests, and current status.

| Feature | Fixture | Elixir Tests | Status | Notes |
|---------|---------|--------------|--------|-------|
| Thread lifecycle (start/resume, single turn) | `python/thread_basic.jsonl` | `Codex.Contract.ThreadParityTest`, `Codex.ThreadTest` | Captured | Fixture scaffolded locally; replace with harvested data once available. |
| Tool auto-run with retry | `python/thread_with_tool_retry.jsonl` | _TBD_ | Planned | Capture fixture during Milestone 0. |
| Structured output success case | `python/structured_output_success.jsonl` | _TBD_ | Planned | Requires schema snapshot. |
| Sandbox approval denial | `python/sandbox_approval_denied.jsonl` | _TBD_ | Planned | Needs approval policy harness. |
| Error taxonomy coverage | `python/errors_transport.jsonl` | _TBD_ | Planned | Verify message parity. |

Update this table as fixtures land and Elixir parity tests are implemented.

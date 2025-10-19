# Python Parity Checklist

This checklist tracks coverage of Python Codex SDK features in the Elixir port. Each entry notes the canonical fixture, associated Elixir tests, and current status.

| Feature | Fixture | Elixir Tests | Status | Notes |
|---------|---------|--------------|--------|-------|
| Thread lifecycle (start/resume, single turn) | `python/thread_basic.jsonl` | `Codex.Contract.ThreadParityTest`, `Codex.ThreadTest`, `Codex.ThreadAutoRunTest`, `Codex.Integration.TurnResumptionTest`, `Codex.EventsTest` | ✅ Implemented | Typed event structs, auto-run retries, and continuation-aware resumption validated against fixtures. |
| Tool auto-run with retry | `python/thread_tool_auto_step1.jsonl` + `thread_tool_auto_step2.jsonl` | `Codex.ThreadAutoRunTest` | ✅ Implemented | Tool registry + auto-run loop exercising continuation tokens and tool callbacks. |
| Structured output success case | `python/structured_output_success.jsonl` | _TBD_ | Planned | Requires schema snapshot. |
| Attachment staging & reuse | `python/thread_basic.jsonl` | `Codex.FilesTest`, `Codex.Integration.AttachmentPipelineTest` | ✅ Implemented | Staging deduplication and CLI propagation validated via captured fixtures. |
| Sandbox approval denial | `python/thread_tool_auto_pending.jsonl` | `Codex.ThreadAutoRunTest` | ✅ Implemented | Static approval policy denies tool invocation and halts auto-run. |
| Error taxonomy coverage | `python/errors_transport.jsonl` | `Codex.ErrorTest` | ✅ Implemented | Typed transport errors mirror Python exit diagnostics. |
| Telemetry lifecycle events | _N/A_ | `Codex.TelemetryTest` | ✅ Implemented | Thread start/stop/exception events and default logger attached via telemetry. |

Update this table as fixtures land and Elixir parity tests are implemented.

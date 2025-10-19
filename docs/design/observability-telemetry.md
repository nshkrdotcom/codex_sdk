# Observability & Telemetry Design

## Feature Summary
- Emit telemetry events and structured logs that match Python client's observability hooks.
- Provide opt-in logging adapters, metrics integration, and correlation IDs for multi-thread sessions.
- Expose tracing hooks compatible with OpenTelemetry.

## Subagent Perspectives
### Subagent Astra (API Strategist)
- Document telemetry namespaces (`[:codex, :thread, :start]`, `[:codex, :turn, :completed]`, etc.) and payload fields.
- Offer `Codex.Telemetry.attach_default_logger/0` helper for quick adoption.
- Align log messages and log levels with Python's default logger output.

### Subagent Borealis (Concurrency Specialist)
- Ensure telemetry emission occurs on calling process to maintain ordering.
- Propagate correlation IDs across processes via `Logger.metadata/1` and explicit fields in events.
- Add safeguards to throttle high-volume event streams (e.g., streaming runs) to prevent overload.

### Subagent Cypher (Test Architect)
- Create ExUnit helpers capturing telemetry events; assert payload shape and sequence.
- Add integration tests comparing Python and Elixir telemetry logs using golden transcripts.
- Property tests verifying correlation IDs persist across nested calls.

## Implementation Tasks
- Implement `Codex.Telemetry` module encapsulating event emission and logger helpers.
- Integrate telemetry calls into thread lifecycle, turn execution, tool invocation, and approvals.
- Provide configuration for structured logging (JSON vs plain text).

### Current Status
- Thread lifecycle emits start/stop/exception telemetry with duration measurements.
- Default logger handler attaches via `Codex.Telemetry.attach_default_logger/1` and mirrors Python output.

## TDD Entry Points
1. Red test capturing telemetry for `start_thread` and asserting metadata fields.
2. Add streaming run test verifying event count and ordering.
3. Implement logging test ensuring default logger produces expected format.

## Risks & Mitigations
- **Performance overhead**: allow telemetry to be disabled or sampled; benchmark before release.
- **Metadata leaks**: scrub sensitive data (API keys) before emission; add tests.
- **Mismatch with Python**: maintain parity matrix and run nightly diff.

## Open Questions
- Should we surface OpenTelemetry spans by default or behind configuration?
- Determine metrics exporter requirements (Prometheus? StatsD?) from stakeholders.

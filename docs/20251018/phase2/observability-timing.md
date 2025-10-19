# Observability Enhancements – Design (2025-10-17)

## Overview
Augment the telemetry stack with execution timing, error classification, and optional OTLP exporter integration so downstream monitoring can track latency and failure modes without manual instrumentation.

## Goals
- Emit duration metadata for turn execution, tool invocations, and attachment cleanup.
- Tag telemetry events with `originator` (CLI vs SDK) for correlation.
- Provide optional OTLP exporter settings via application config.
- Document runbook for capturing logs and metrics in production.

## Non-Goals
- Ship a bundled OTLP collector.
- Provide dashboards (Grafana, etc.).
- Persist metrics locally.

## Architecture
1. `Codex.Telemetry.emit/3` wraps duration conversions — it accepts `System.monotonic_time/1` input and normalises payloads with `:duration_ms`.
2. Thread, tool, and approval emitters surface `originator: :sdk`, span tokens, and stop timestamps to support OpenTelemetry spans.
3. `Codex.Telemetry.configure/1` restarts the OTEL apps with a simple processor when OTLP is enabled (via `CODEX_OTLP_ENABLE=1`), reading `CODEX_OTLP_ENDPOINT` and optional `CODEX_OTLP_HEADERS`, defaulting to `otel_exporter_pid` during tests.
4. Provide runbook with commands for enabling exporters, tailing telemetry, and cleaning erlexec state.

## Implementation Steps
1. Add `:duration_ms` (and stop-system timestamps) across thread, tool, and approval events.
2. Introduce `Codex.Telemetry.configure/1` that restarts OTEL with a configured exporter and attaches span handlers.
3. Attach OpenTelemetry spans to thread lifecycle events via telemetry handlers and `otel_exporter_pid` for tests.
4. Document how to enable the exporter and verify spans in the runbook/ops docs.

## Risks
- Optional OTLP dependency should be runtime-only; guard runtime starts and tolerate `:tls_certificate_check` being absent.
- Ensure exporter init errors fail gracefully (log warning, continue).

## Verification
- Tests capturing telemetry ensure duration present and within expected range.
- Integration test enabling exporter with mock OTLP collector (use `opentelemetry_exporter` test handler).
- Runbook instructions validated manually.

## Open Questions
- Should exporter configuration live in `config/*.exs`? Default to environment-driven to avoid compile-time dependency.
- Do we need sampling controls? Possibly later; start with full stream.

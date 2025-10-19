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
1. `Codex.Telemetry.emit/3` wraps duration conversions—accept `System.monotonic_time/1` input.
2. `Codex.Exec` already tracks start time; extend to include `originator` metadata and error classification (`transport`, `approval_denied`, etc.).
3. Add `Codex.Telemetry.exporter/0` that reads env (`CODEX_OTLP_ENDPOINT`, `CODEX_OTLP_HEADERS`) and configures `opentelemetry_exporter` if present.
4. Provide runbook with commands for tailing telemetry and cleaning erlexec state.

## Implementation Steps
1. Update telemetry events to include `:duration_ms` keys (convert from native).
2. Introduce `Codex.Telemetry.configure/1` called during application start to optionally set exporter.
3. Add new event types for attachment cleanup and tool metrics (ties into other feature docs).
4. Document how to enable exporter in README/ops doc.

## Risks
- Optional OTLP dependency should be runtime-only; guard with `Code.ensure_loaded?`.
- Ensure exporter init errors fail gracefully (log warning, continue).

## Verification
- Tests capturing telemetry ensure duration present and within expected range.
- Integration test enabling exporter with mock OTLP collector (use `opentelemetry_exporter` test handler).
- Runbook instructions validated manually.

## Open Questions
- Should exporter configuration live in `config/*.exs`? Default to environment-driven to avoid compile-time dependency.
- Do we need sampling controls? Possibly later; start with full stream.

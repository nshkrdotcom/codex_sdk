# Tool Execution Metrics – Design (2025-10-17)

## Overview
Track invocation statistics for registered tools (success/failure counts, latency, retry metadata) and expose them via telemetry and optional in-memory counters. Aimed at surfacing operational insights without external instrumentation.

## Goals
- Capture per-tool metrics for both synchronous and async tool runs.
- Provide `Codex.Tools.metrics/0` returning snapshot map.
- Emit telemetry for `tool.started`, `tool.succeeded`, `tool.failed`.
- Integrate with auto-run loop to tag retries.

## Non-Goals
- Persist metrics to disk.
- Provide dashboards/exporters (beyond telemetry).
- Handle structured custom metrics (only core counters/timings).

## Architecture
1. ETS table `:codex_tool_metrics` keyed by tool name.
2. `Codex.Tools.Registry` updates metrics when `invoke/3` succeeds or fails.
3. Wrap tool invocation in `:timer.tc` to compute latency.
4. Telemetry events (`[:codex, :tool, :start]`, etc.) include tool metadata and latency (on completion).
5. Optional `Codex.Tools.reset_metrics/0` for tests.

## Data Schema
```elixir
%{
  "web_search" => %{
    success: 12,
    failure: 3,
    last_error: {:tool_failure, reason},
    last_latency_ms: 152,
    total_latency_ms: 4200
  }
}
```

## API Changes
- `Codex.Tools.metrics/0` and `Codex.Tools.reset_metrics/0`.
- Telemetry event specs documented in `Codex.Telemetry`.

## Risks
- ETS contention under high throughput — mitigate via `:write_concurrency`.
- Large number of tools may expand snapshot; acceptable for in-memory map.

## Implementation Plan
1. Create ETS table during application start (`Codex.Tools` `reset!/0`).
2. Update registry `invoke/3` to wrap calls with timing and update counters.
3. Emit telemetry events (include `:retry?` flag from auto-run).
4. Add docs & examples.

## Verification
- Unit tests: metrics increments on success/failure, reset works.
- Integration: auto-run scenario with retries increments failure then success.
- Telemetry tests capture events to ensure metadata correctness.

## Open Questions
- Should we expose rate (success %)? Could compute client-side — out of scope.

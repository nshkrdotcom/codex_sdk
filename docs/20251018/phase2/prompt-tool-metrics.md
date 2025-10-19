# Prompt: Tool Execution Metrics (2025-10-17)

## Required Reading
- `docs/20251017/tool-metrics.md`
- `docs/design/tools-mcp.md`
- `lib/codex/tools.ex`, `lib/codex/tools/registry.ex`
- `test/codex/tools_test.exs`, `test/codex/thread_auto_run_test.exs`

## TDD Checklist
1. **Red** – author tests for metrics and telemetry:
   - Unit tests verifying `Codex.Tools.metrics/0` counters update on success/failure.
   - Test for `reset_metrics/0` clearing state.
   - Integration test covering retry path in auto-run updating failure then success counts.
   - Telemetry assertion capturing `[:codex, :tool, ...]` events.
2. **Green** – implement ETS-backed metrics, wrap invocations with timing, emit telemetry.
3. **Refactor** – ensure concurrency safety, document API, run `mix format`, `mix test`, `mix codex.verify`.

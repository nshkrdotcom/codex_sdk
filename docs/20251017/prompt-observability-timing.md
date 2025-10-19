# Prompt: Observability Enhancements (2025-10-17)

## Required Reading
- `docs/20251017/observability-timing.md`
- `docs/design/observability-telemetry.md`
- `lib/codex/telemetry.ex`, `lib/codex/exec.ex`
- `test/codex/telemetry_test.exs`

## TDD Checklist
1. **Red** – add coverage:
   - Telemetry tests asserting new `:duration_ms` fields on thread/tool events.
   - Tests verifying exporter config is optional and no-op when env absent.
   - Integration test enabling mock OTLP exporter to confirm spans emitted.
2. **Green** – implement duration calculations, optional exporter wiring, event tagging.
3. **Refactor** – document configuration, update runbook, run `mix format`, `mix test`, `mix codex.verify`.

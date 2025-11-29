# Prompt: Expand telemetry and observability support (TDD)

Required reading:
- docs/20251129/telemetry/telemetry_and_observability.md
- docs/observability-runbook.md
- lib/codex/telemetry.ex, lib/codex/events.ex, lib/codex/thread.ex (telemetry emitters and event metadata)
- test/codex/telemetry_test.exs, test/codex/events_test.exs

Context to carry:
- Feedback metadata includes source info; event payloads expose `thread_id` and `turn_id`.
- OTEL hooks expanded (including mTLS); exec/compaction telemetry is richer.
- Token-usage updates and diff streams provide fine-grained signals during turns.

Instructions (TDD):
1) Read the docs to capture the new telemetry fields and mTLS expectations.
2) Add failing tests that assert source info, thread/turn ids, and token-usage/diff signals are emitted.
3) Implement telemetry schema updates and exporters so the new fields flow through; maintain backwards compatibility.
4) Verify OTEL config supports mTLS and expanded spans/metrics; document defaults.
5) Run targeted tests then `mix test`; no CI-only steps.

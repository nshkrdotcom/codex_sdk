# ADR-010: Introduce Span-Based Tracing and Usage Aggregation

Status: Proposed

Context
- Python: tracing framework (`src/agents/tracing`) installs default exporter/processors; spans for agents/functions/guardrails/handoffs/MCP; `RunConfig` controls tracing_disabled, trace_include_sensitive_data (env-driven default), workflow/group/trace_id metadata; usage aggregated in `Usage` (`usage.py`) and attached to `RunContextWrapper`.
- Elixir: telemetry events only; no span model or processors; no sensitive-data toggle; usage limited to codex response fields.

Decision
- Add tracing provider with spans and processors; default exporter configurable via env; propagate workflow/group/trace_id metadata and sensitive-data inclusion toggle.
- Attach usage aggregator to run context, accumulating per-request tokens and exposing per-request breakdowns.
- Keep emitting telemetry events but correlate with spans; allow disabling tracing per run.

Consequences
- Benefits: parity with Python observability, easier downstream integration, better cost accounting.
- Risks: added complexity and performance overhead; need to avoid leaking sensitive data when toggle is off; must align with codex telemetry.
- Actions: design span data structures and processor interfaces; implement default processor/exporter; integrate into runner; add tests similar to `tests/test_tracing.py`, `tests/test_agent_tracing.py`, `tests/test_usage.py`, `tests/test_agents_logging.py`, `tests/tracing/test_processor_api_key.py`.

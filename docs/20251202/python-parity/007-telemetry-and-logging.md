Python
- Logging uses `logging.getLogger("openai.agents")` (`src/agents/logger.py:1-3`); debug/info messages sprinkled through run/tool code (e.g., tool enablement, errors).
- Tracing framework in `src/agents/tracing/__init__.py:1-118` installs a default trace provider and exporter; exposes span helpers (`agent_span`, `function_span`, `guardrail_span`, `handoff_span`, `mcp_tools_span`, `speech_span`, etc.) and allows adding/replacing processors.
- `RunConfig` fields (`run.py:220-249`) control tracing: disable flag, sensitive-data inclusion, workflow_name/group_id/trace_id/metadata.
- Run loop starts spans per agent turn (`run.py:593-600` and `_start_streaming:1084-1102`), attaches tool lists, errors (max_turns, guardrail trips) via `_error_tracing`, and keeps trace open across streaming.
- Usage accounting stored on `RunContextWrapper.usage` (`run_context.py:20-25`) backed by `Usage` dataclass (`usage.py:7-108`), aggregating per-request token usage and preserving per-request breakdowns.
- Tracing hooks extend to MCP and tool operations (`mcp/util.py:14-210`, `_run_impl.py:107-119`) emitting span errors for tool/guardrail failures.

Elixir status
- Uses `Codex.Telemetry` to emit `[:codex, ...]` events around exec lifecycle and approvals (`lib/codex/thread.ex`, `lib/codex/approvals.ex`); no distributed tracing or span objects.
- Logging not centralized; relies on application logger; no built-in usage aggregation besides codex response usage fields.
- No user-facing trace metadata controls or sensitive-data toggle.

Gaps/deltas
- Missing tracing provider/processors and span taxonomy (agent/function/guardrail/handoff/MCP) with metadata fields.
- No usage aggregator on the context or per-request breakdowns.
- Logging namespace not standardized; sensitive-data inclusion toggle absent.

Porting steps + test plan
- Introduce tracing abstraction mirroring Python spans and processors; allow injecting processors and disabling tracing via options; validate with parity from `tests/test_tracing.py`, `tests/test_agent_tracing.py`, and `tests/tracing/test_processor_api_key.py`.
- Aggregate usage on thread/run context mirroring `Usage.add` semantics and expose final usage; test with `tests/test_usage.py` and codex responses.
- Standardize logger namespace and hook telemetry to tracing spans; add regression tests similar to `tests/test_agents_logging.py` and `tests/test_responses_tracing.py`.***

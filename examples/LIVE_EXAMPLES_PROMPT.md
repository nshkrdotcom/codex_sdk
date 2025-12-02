# Prompt for Creating New Live Examples (Covering ADR-001 to ADR-014)

You will add a **small, focused set of live examples** under `examples/` that run with `mix run` and exercise the real Codex CLI (no mocks, no API token wiring). Before writing anything, **read ADR-001 through ADR-014** (`docs/20251202/adrs/`) to ensure the scenarios below are fully covered. Keep the example count lean—combine related behaviors rather than one file per ADR—and prioritize clarity for users.

## Non-Negotiable Constraints
- **Live Codex CLI only**: No mocks/stubs. Use the installed `codex` binary, resolved like existing `live_*.exs` scripts (`codex_path_override`/`CODEX_PATH`/`System.find_executable("codex")`), and rely on the user’s CLI login (do not add API-key setup).
- **`mix run` entrypoints**: Each example must be runnable via `mix run examples/<file>.exs "optional prompt"`.
- **Keep it short**: Minimal output, readable in a terminal. Avoid complex setup or extra deps.
- **Update plumbing**: Add new files to `examples/run_all.sh` (sequential `mix run` calls) and list them in `examples/README.md`. Do not forget shebang + executable bit for `run_all.sh` if touched.
- **Docs only if helpful**: Don’t clutter the root README with meta text; keep descriptions in `examples/README.md`.

## Coverage Checklist (map to ADRs)
- **Multi-turn runner + tool behavior** (ADR-001/002): max_turns, continuation handling, tool_use_behavior variants, handoff routing.
- **Guardrails + approvals** (ADR-003/011): input/output/tool guardrails, tripwire vs reject, tool approval allow/deny/timeout, safety hooks.
- **Function/hosted tools + structured outputs** (ADR-004/005): function tool schema, structured text/image/file outputs, hosted shell/apply_patch/computer/file_search/image generation stubs.
- **MCP** (ADR-006): hosted_mcp invocation with caching/retries/filters (use a stubbed client object but still live CLI flow; no network).
- **Sessions/resume** (ADR-007): session save/load, conversation_id/previous_response_id handling.
- **Model settings/provider** (ADR-008): model override + model_settings validation.
- **Streaming/cancel + tracing/usage** (ADR-009/010): semantic streaming events, cancel modes, usage aggregation/compaction; trace metadata propagation.
- **Attachments/file search** (ADR-012): `Codex.Files` staging in a live run, structured file/image outputs, file_search vector_store_ids/filters/include_search_results.
- **Parity fixture visibility** (ADR-013): surface a short parity/fixtures summary (informational).
- **Realtime/voice stubs** (ADR-014): show the clear unsupported errors.

## Proposed Example Set (keep to ~6–8 files)
Name them by feature (not ADR number). For each, include a top-of-file comment listing which ADRs it covers.

1. **`live_multi_turn_runner.exs`** — multi-turn loop with `max_turns`, continuation token handling, early-exit/error path; prints attempts, usage, final response. (ADR-001/002/009/010)
2. **`live_tooling_guardrails_approvals.exs`** — combines tool_use_behavior variants, a handoff agent, input/output/tool guardrails, and approval allow/deny/timeout paths; stream events to show guardrail/approval outcomes. (ADR-002/003/011)
3. **`live_structured_hosted_tools.exs`** — function tool with strict schema returning text/image/file outputs; hosted shell/apply_patch/computer with safety; file_search config; shows normalized outputs and approvals. (ADR-004/005/012)
4. **`live_mcp_and_sessions.exs`** — hosted_mcp call with caching/retries/filters (use a local stub client object, no external network), plus session save/load with conversation ids and previous_response_id. (ADR-006/007)
5. **`live_model_streaming_tracing.exs`** — model/model_settings override, streaming with cancel (:immediate/:after_turn), usage aggregation/compaction, trace metadata (workflow/group/trace_id, sensitive toggle). (ADR-008/009/010)
6. **`live_attachments_and_search.exs`** — stages a file via `Codex.Files`, returns it as structured tool output, runs hosted `file_search` with vector_store_ids/filters/include_search_results, demonstrates deduped replays across continuations. (ADR-012)
7. **`live_parity_and_status.exs`** — prints a brief parity/fixture summary and where to find fixtures/tests; no mocks, just informational. (ADR-013)
8. **`live_realtime_voice_stub.exs`** — calls realtime/voice stubs to surface the unsupported_feature errors clearly. (ADR-014)

If combining reduces count while keeping coverage, do it—aim for clarity, not quantity.

## Implementation Notes
- Follow the patterns in existing `live_*` scripts for resolving the `codex` binary and reading CLI auth (no API key handling).
- Keep outputs succinct: print prompt, key events (guardrails/approvals/usage/trace), and final response; avoid excessive logging.
- Use small inline tools/stubs inside the scripts; do not add new mix deps.
- After adding files, update:
  - `examples/run_all.sh` to include the new scripts in a reasonable order.
  - `examples/README.md` with 1–2 line descriptions.
- Run `mix format` and sanity-check `mix run <file>` locally (real codex CLI).

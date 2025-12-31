# Implementation Plan - Gap Analysis Coordinator

Source
- docs/20251231/codex-gap-analysis/00-overview.md

Goals
- Close all documented parity gaps between ./codex and the Elixir SDK, excluding the known CLI bundling difference.
- Preserve API stability; avoid changing defaults unless needed for parity and documented.
- Land changes with tests, docs, and release notes aligned with 0.4.6.

Non-goals
- Modifying vendored CLI under codex/.
- Introducing new, unrelated features.

Dependencies and sequencing
1. Establish shared config override helpers and expand Options/Thread.Options to carry new fields (feeds exec, app-server, tools, and observability work).
2. Align exec JSONL CLI behavior (sandbox defaults, config overrides, instruction forwarding).
3. Expand app-server protocol support (thread_resume history/path, notifications, raw items, fuzzy search).
4. Align tool schemas and guardrails (shell, apply_patch grammar, missing tools, parallel behavior semantics).
5. Implement MCP JSON-RPC client and helpers (skills, prompts, mcp config).
6. Implement sessions/undo support (ghost snapshots, apply helper, history persistence).
7. Wire observability (retry, rate limits, idle timeouts, error normalization).

Cross-cutting considerations
- Prefer feature flags or opt-in settings where behavior changes could be breaking.
- Preserve backward compatibility for tool schemas by accepting both legacy and upstream formats when feasible.
- Keep config parsing strict enough to avoid silently ignoring invalid keys.

Testing and release hygiene
- Add or update focused tests for each change area.
- Keep `mix format`, `mix test`, `mix credo --strict`, and `mix dialyzer` clean.
- Update README, relevant docs in docs/, and examples/ where behavior or options change.
- Update CHANGELOG 0.4.6 and README 0.4.6 highlights.

Acceptance criteria
- All gaps in docs/20251231/codex-gap-analysis/01-07 are implemented or explicitly documented as intentionally unsupported.
- New options and APIs are documented with examples.
- All test and lint commands pass with no new warnings.

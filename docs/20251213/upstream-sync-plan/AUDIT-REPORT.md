# Upstream Sync Documentation Audit Report (2025-12-13)

## Summary

The upstream-sync plan documents contained multiple incorrect commit attributions, several features
that are not present in the synced upstream commits, and a number of Elixir port “gaps” that are
already implemented in the current codebase. These issues materially changed the proposed porting
priorities and the implementation plan.

Key fixes in this audit:
- Corrected upstream scope/versions for both repos.
- Removed/flagged non-existent (in-range) features (notably agents “agent-as-tool `on_stream`”).
- Replaced inaccurate protocol/event descriptions with transport-correct notes (exec JSONL vs core
  protocol vs app-server protocol).
- Updated the Elixir gap analysis to reflect the actual implementation (`Codex.RunConfig` already
  includes `previous_response_id`, `conversation_id`, `session_input_callback`, etc.).

## Errors Found

### Critical

- `openai-agents-python` “Agent-as-Tool Streaming (`on_stream`)” was documented as part of the sync,
  but is **not reachable** from the synced commit `71fa12c` (it exists on `origin/agent-as-tool-streaming`).
- `codex-rs` OTEL configuration was documented with incorrect types/fields (`enabled`, `console`,
  `http/grpc`) that do not match `codex-rs/core/src/config/types.rs` and upstream docs.
- Protocol/event examples in the codex-rs doc referenced non-existent event types (e.g.
  `thread_history_entry`, `config_changed` as JSONL event shapes) without clarifying which transport
  they apply to.

### Major

- Wrong commit attribution for codex “Skills” (used `321625072`, which is a TUI model picker change);
  the skills feature work is centered on `b36ecb6c3` (plus `60479a967`).
- Wrong commit attribution for codex “Models Manager” (used `149696d95`, which is a small follow-up);
  models manager/caching is introduced and evolved across `00cc00ead`, `53a486f7e`, `222a49157`, etc.
- Wrong cache path for models (`~/.codex/models_cache/models.json`); upstream uses
  `~/.codex/models_cache.json` (`MODEL_CACHE_FILE` in `models_manager.rs`).
- Elixir gap analysis claimed missing `previous_response_id` and `session_input_callback`, but both
  are already present in `lib/codex/run_config.ex`.
- Elixir gap analysis and requirements referenced `Codex.Agent.as_tool/2`, but there is no `as_tool`
  API in `lib/codex/agent.ex`.

### Minor

- `openai-agents-python` baseline commit `0d2d771` was labeled as `v0.6.2`; the tag `v0.6.2` points
  to `9fcc68f`.
- Elixir “module counts” and “doctest coverage” claims were incorrect (no doctest usage found; docs
  now use a file-count that is verifiable).

## Omissions

- `openai-agents-python` commit `9f96338` (“Attach context to apply patch operations”) was not
  mentioned in the agents-python changes analysis.
- codex-rs “Review mode” (`4b78e2ab0`) and unified exec event refactors (`0ad54982a`) were not
  surfaced as major protocol-facing changes.
- codex-rs protocol additions for remote models metadata (`codex-rs/protocol/src/openai_models.rs`)
  were not called out.

## Suggested Improvements

- Keep a strict “synced range” boundary: only describe features reachable from the synced commit.
- Always label which codex transport a feature is exposed through:
  - `codex exec --experimental-json` JSONL events
  - core protocol (`codex-rs/protocol`)
  - app-server protocol (`codex-rs/app-server-protocol`)
- When mapping upstream features to Elixir, prefer the SDK’s existing architecture:
  - run-scoped options belong in `Codex.RunConfig` (not `Codex.Options` / `Codex.Thread.Options`)
- Treat backend-dependent features explicitly as “blocked” until the backend surfaces required
  fields (e.g., OpenAI `response_id`, logprobs).

## Severity Assessment

- **Critical**: 3
- **Major**: 6
- **Minor**: 3

## Audit Changes

### docs/20251213/upstream-sync-plan/00-overview.md
- Fixed: agents-python version scope (tags and baseline)
- Removed: non-verified “agent-as-tool on_stream” and doctest/module-count claims
- Updated: codex-rs attributions and aligned priority list with transport-dependent requirements

### docs/20251213/upstream-sync-plan/01-agents-python-changes.md
- Fixed: incorrect code snippets for logprobs + usage normalization
- Added: missing apply-patch context change (`9f96338`)
- Removed: agent-as-tool streaming section from this sync; added “not included” note
- Updated: Elixir mapping to use `Codex.RunConfig` and mark backend dependencies

### docs/20251213/upstream-sync-plan/02-codex-rs-changes.md
- Fixed: OTEL config shape and clarified it is config.toml-driven
- Fixed: skills + models manager commit attributions and cache path
- Added: transport-layer section to prevent protocol/JSONL conflation
- Added: review mode + unified exec refactor callouts

### docs/20251213/upstream-sync-plan/03-elixir-port-gaps.md
- Fixed: module/file counts and removed incorrect gap claims (`previous_response_id`, `session_input_callback`)
- Removed: references to non-existent Elixir APIs (`Codex.Agent.as_tool/2`)
- Reframed: codex-rs features as transport-dependent where appropriate

### docs/20251213/upstream-sync-plan/04-porting-requirements.md
- Updated: requirements to reflect current Elixir architecture and transport realities
- Removed: requirements for features not in the synced upstream range

### docs/20251213/upstream-sync-plan/05-implementation-plan.md
- Updated: plan to begin with a transport decision gate
- Removed: phases based on incorrect gap assumptions (e.g., session callbacks already exist)

## Open Questions / Follow-ups

- Implementing `auto_previous_response_id` parity depends on whether the Elixir SDK backend can
  surface an OpenAI `response_id`. The current exec JSONL stream does not.
- Skills/models/config layers may require adding a core/app-server protocol transport to the Elixir
  SDK; this is a strategic scope decision rather than a straightforward port.

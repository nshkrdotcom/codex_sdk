# Gap Analysis: codex 987dd7fde..810ebe0d2 (2025-12-27)

## Scope and assumptions

- Scope is the vendored `codex` update from `987dd7fde` to `810ebe0d2`.
- The Elixir SDK does not bundle the runtime; we assume a system `codex` binary.
- Only SDK-visible surfaces are in scope: exec JSONL events, app-server protocol,
  model registry behavior, and config-driven behavior we read in Elixir.
- TUI-only changes, packaging, and platform-specific runtime changes are out of scope.

## Upstream changes with SDK impact

1. **App-server protocol error details**
   - `TurnError` now carries `additional_details` (v2 protocol).
   - `StreamErrorEvent` now carries `additional_details` (core protocol).
   - Files: `codex/codex-rs/app-server-protocol/src/protocol/v2.rs`,
     `codex/codex-rs/protocol/src/protocol.rs`.

2. **Config layering + project root markers**
   - System config file `/etc/codex/config.toml` is now honored.
   - Project-local `.codex/config.toml` layers are discovered between `cwd` and
     project root.
   - New `project_root_markers` controls how project root is detected.
   - Files: `codex/codex-rs/core/src/config_loader/mod.rs`,
     `codex/docs/config.md`.

3. **Config surface updates**
   - New `developer_instructions` config key.
   - `instructions` is now ignored (legacy).
   - `model_reasoning_summary_format` and `ghost_commit` removed from docs.
   - `/undo` removed from slash commands; skills docs moved to developer site.
   - Files: `codex/docs/config.md`, `codex/docs/example-config.md`,
     `codex/docs/slash_commands.md`, `codex/docs/skills.md`.

4. **Models registry update**
   - `codex-rs/core/models.json` updated; `minimal_client_version` is string
     (e.g. "0.60.0") upstream while `priv/models.json` currently stores arrays.
   - Files: `codex/codex-rs/core/models.json`, `priv/models.json`.

## Current SDK gaps

| Area | Upstream change | Current Elixir SDK behavior | Gap | Priority |
| --- | --- | --- | --- | --- |
| App-server errors | `additional_details` in `TurnError` | `Codex.Events.Error` drops details; app-server adapter only reads `message` | Missing `additional_details` and retry metadata in error events and normalization | P0 |
| Config layering | `/etc/codex/config.toml`, `.codex/config.toml`, `project_root_markers` | `Codex.Models.remote_models_enabled?/0` only scans `$CODEX_HOME/config.toml` | Remote model gating ignores system/project layers and new markers | P1 |
| Models registry | `minimal_client_version` now strings in upstream file | `priv/models.json` uses arrays; parser only handles arrays | Data format mismatch + parser not robust to string | P1 |
| Docs/examples | Config docs and slash commands updated upstream | SDK docs still point to `$CODEX_HOME/config.toml` only; no mention of project layers or `developer_instructions` | Documentation drift | P2 |

## Technical plan to reach parity

### P0 - App-server error details

**Goal:** surface `additional_details` and retry metadata across app-server error notifications.

1. Extend `Codex.Events.Error` to include optional fields:
   - `additional_details :: String.t() | nil`
   - `will_retry :: boolean() | nil`
   - `codex_error_info :: map() | nil` (optional passthrough)
2. Update parsing/serialization in `lib/codex/events.ex` to accept:
   - `additional_details` from `error.additionalDetails` or `error.additional_details`
   - `will_retry` from top-level `params.willRetry` (app-server notification)
3. Update `lib/codex/app_server/notification_adapter.ex`:
   - Map `ErrorNotification` fields into the new `Codex.Events.Error` struct.
   - Preserve existing `message` behavior for backwards compatibility.
4. Update `lib/codex/error.ex` normalization:
   - Include `additional_details` and `codex_error_info` in the `details` map.
   - Keep `message` as the primary display string.
5. Tests:
   - Add app-server notification fixture tests to assert new fields are preserved.
   - Ensure existing exec JSONL error events still parse (fields remain optional).

### P1 - Config layering and project root markers

**Goal:** make SDK behavior for remote models match codex config layering.

1. Implement a lightweight config layer loader:
   - New module: `lib/codex/config/layer_stack.ex` (or similar).
   - Inputs: `codex_home`, `cwd` (default to `File.cwd!()`), optional overrides.
   - Layer order (lowest to highest precedence):
     - System: `/etc/codex/config.toml` (if readable)
     - User: `$CODEX_HOME/config.toml` (always include empty layer if missing)
     - Project: `.codex/config.toml` for each ancestor between `project_root` and `cwd`
     - Session overrides: for SDK-owned flags (optional)
2. Implement project root detection mirroring upstream:
   - Read `project_root_markers` from merged system + user layers only.
   - Default markers: `[".git"]`.
   - If markers is `[]`, treat `cwd` as root and skip ancestor walk.
3. Implement config parsing strategy:
   - Option A: add a TOML parser dependency and decode full tables.
   - Option B: keep a minimal parser that only extracts:
     - `features.remote_models`
     - `project_root_markers`
   - Prefer a real TOML parser to avoid drift as config grows.
4. Update `Codex.Models`:
   - Add an optional `cwd` argument to `list/1` and `list_visible/2` (backwards compatible).
   - Use the config loader to compute `remote_models_enabled?` from effective layers.
5. Tests:
   - System config toggles `features.remote_models`.
   - Project `.codex/config.toml` overrides user config.
   - `project_root_markers` empty list disables ancestor search.

### P1 - Models registry parity

**Goal:** align bundled model data and support both `minimal_client_version` formats.

1. Sync `priv/models.json` with upstream `codex/codex-rs/core/models.json`.
2. Update `Codex.Models.parse_client_version/1` to accept:
   - Array format: `[major, minor, patch]`
   - String format: `"0.60.0"` -> `{0, 60, 0}`
   - Fallback: `{0, 0, 0}` for invalid input
3. Add unit tests for both formats to avoid regressions.
4. Confirm any model defaults in `lib/codex/models.ex` still match upstream presets.

### P2 - Docs and examples alignment

**Goal:** keep SDK docs consistent with upstream config behavior and removed features.

1. Update docs that mention remote model gating:
   - `README.md`
   - `docs/06-examples.md`
   - Include `/etc/codex/config.toml`, `.codex/config.toml`, and `project_root_markers`.
2. Add note for `developer_instructions` config key:
   - Mention that it injects before `AGENTS.md`.
   - Clarify that `instructions` is ignored upstream.
3. Remove or update mentions of:
   - `model_reasoning_summary_format`
   - `ghost_commit`
   - `/undo` slash command
   - `skills.md` -> link to developer documentation site

## Non-actions (upstream changes with no SDK impact)

- TUI-only features: transcript selection, external editor UI, redraw throttling.
- Runtime packaging/test harness changes (cargo-bin, windows-sys gating).
- Windows sandbox implementation details.

## Suggested validation

- `mix test` (ensure new error fields and config loader tests pass).
- `mix format` for any new modules.

# OpenAI Codex CLI (codex-rs) - Upstream Changes Analysis

## Version / Scope

- **Previous**: `6eeaf46ac`
- **Current**: `a2c86e5d8`
- **Key Tag Within Range**: `rust-v0.73.0-alpha.1`

This sync range is large. This document focuses on changes that affect SDK work:
- configuration shape (what the SDK can/should surface)
- protocol/wire types (what the SDK must decode/encode)
- SDK-relevant features (models, skills, observability)

## Transport Layers (Important for Porting)

Codex exposes multiple “interfaces”; not every core feature is surfaced everywhere:

1. **`codex exec --experimental-json`** (`codex-rs/exec/src/exec_events.rs`) — a small JSONL event
   set (`thread.started`, `turn.started`, `item.*`, `turn.completed`, `turn.failed`, `error`).
2. **Core protocol** (`codex-rs/protocol/src/protocol.rs`) — rich `Op` requests + `EventMsg` stream
   used by the TUI and internal components.
3. **App-server protocol** (`codex-rs/app-server-protocol/`) — RPC + thread-history types used by
   the IDE extension / app-server.

The current Elixir SDK consumes exec JSONL events. Porting protocol/app-server features requires a
new integration surface.

---

## 1. OTEL Telemetry Export

### Commit: `ad7b9d63c`

### What Changed Upstream

- Adds OpenTelemetry exporter support (disabled by default).
- Upstream documentation describes this as OTEL **log event** export configured via
  `~/.codex/config.toml`.

### References

- Docs: `codex/docs/config.md` (“Observability and telemetry → otel”)
- Config types: `codex-rs/core/src/config/types.rs` (`OtelConfigToml`, `OtelExporterKind`, `OtelConfig`)
- Provider init: `codex-rs/core/src/otel_init.rs`
- OTEL provider: `codex-rs/otel/src/otel_provider.rs`, `codex-rs/otel/src/config.rs`

### Elixir Port Notes

- Distinguish **Elixir-side OTLP export** (already implemented via `lib/codex/telemetry.ex`) from
  codex-rs’ own OTEL export.
- Codex-rs OTEL export is **config.toml-driven**; “pass OTEL env vars to the subprocess” does not
  match the upstream user-facing surface.
- If the SDK must control codex-rs OTEL config programmatically, consider running codex with an
  isolated `CODEX_HOME` containing a generated `config.toml`.

**Relevance**: High (observability), but can be “docs-only” if users manage `~/.codex/config.toml`.

---

## 2. Config Loader + ConfigService

### Commit: `92098d36e`

### What Changed Upstream

- Refactors config loading into `core/src/config_loader/` with layered precedence:
  - MDM > System > Session flags > User
- Introduces ConfigService (`core/src/config/service.rs`) with versioned writes:
  - versions configs as `sha256:<hex>` strings
  - supports atomic single-value writes and batch writes with optimistic concurrency (`expected_version`)

### References

- Loader state: `codex-rs/core/src/config_loader/state.rs`
- Version hashing: `codex-rs/core/src/config_loader/fingerprint.rs`
- Service: `codex-rs/core/src/config/service.rs`
- Loader README: `codex-rs/core/src/config_loader/README.md`

### Elixir Port Notes

This is primarily relevant if the Elixir SDK intends to speak the app-server config RPC; it is not
surfaced via `codex exec --experimental-json`.

**Relevance**: Medium (enterprise / IDE use cases)

---

## 3. Remote Models (ModelsManager)

### Key Commits

- `00cc00ead` — introduce `ModelsManager`
- `53a486f7e` — remote models feature flag
- `222a49157` — disk cache + TTL + ETag

### What Changed Upstream

- Adds remote model discovery (`/models`) behind feature `RemoteModels`.
- Persists a cache snapshot at `codex_home/models_cache.json` (default `~/.codex/models_cache.json`).
- Uses a 5-minute TTL (`DEFAULT_MODEL_CACHE_TTL`) and stores `etag` for conditional refresh.
- Adds protocol types for models metadata in `codex-rs/protocol/src/openai_models.rs`.

### References

- Manager: `codex-rs/core/src/openai_models/models_manager.rs`
- Cache: `codex-rs/core/src/openai_models/cache.rs`
- Protocol types: `codex-rs/protocol/src/openai_models.rs`

### Elixir Port Notes

The Elixir SDK currently hardcodes a small list of known models in `lib/codex/models.ex`. To match
upstream dynamic discovery, decide how to surface `/models`:

- app-server integration (closest to upstream)
- direct API client
- reading codex-managed caches as a best-effort (less ideal)

**Relevance**: Medium (model pickers, validation)

---

## 4. Skills

### Key Commits

- `b36ecb6c3` — explicit SKILL.md content injection on selection
- `60479a967` — enforce length limits by characters

### What Changed Upstream

- Discovers skills on disk:
  - `~/.codex/skills/**/SKILL.md` (recursive)
  - `<repo_root>/.codex/skills/**/SKILL.md` (repo root derived from git)
  Hidden entries and symlinks are skipped.
- Validates YAML frontmatter with `name` (≤64 chars) and `description` (≤1024 chars).
- Injects a runtime “## Skills” section (name/description/path + usage rules) into user instructions
  when feature `Skills` is enabled.
- Allows explicit skill selection via `UserInput::Skill { name, path }`; when present, core injects
  the full `SKILL.md` contents for the turn.
- Surfaces discovery results in `SessionConfiguredEvent.skill_load_outcome` (core protocol).

### References

- Loader: `codex-rs/core/src/skills/loader.rs`
- Runtime section: `codex-rs/core/src/skills/render.rs`, `codex-rs/core/src/project_doc.rs`
- Explicit injection: `codex-rs/core/src/skills/injection.rs`
- Protocol input type: `codex-rs/protocol/src/user_input.rs`
- SessionConfigured payload: `codex-rs/protocol/src/protocol.rs` (`SkillLoadOutcomeInfo`)

### Elixir Port Notes

If the Elixir SDK stays on the exec JSONL transport, these protocol surfaces are not currently
visible. If adopting the core/app-server protocol, the SDK must add:
- encoding for `UserInput::Skill`
- decoding/surfacing of `skill_load_outcome`

**Relevance**: High (customization), but transport-dependent.

---

## 5. Shell Snapshotting

### Key Commits

- `7836aedda` — initial shell snapshotting
- `29381ba5c` — extend snapshot usage for shell command paths

### What Changed Upstream

- Feature-flagged shell snapshot stored under `codex_home/shell_snapshots/<uuid>.sh`.
- 10s timeout and automatic cleanup on session end (drop).
- Snapshot captures functions, shell options, aliases, and exports; PowerShell/Cmd are currently gated.

### References

- Implementation: `codex-rs/core/src/shell_snapshot.rs`

**Relevance**: Low (debugging), typically not SDK-exposed.

---

## 6. Review Mode & Unified Exec Event Refactors

### Key Commits

- `4b78e2ab0` — “review everywhere”
- `0ad54982a` — unified exec event rework

### What Changed Upstream

- Adds review request types (`ReviewRequest`, `ReviewTarget`) and review mode lifecycle events
  (`EnteredReviewMode`, `ExitedReviewMode`) in the core protocol.
- Refactors unified exec/session eventing and extends/renames some event payloads.

### References

- Protocol: `codex-rs/protocol/src/protocol.rs`
- Exec changes: `codex-rs/exec/src/lib.rs`, `codex-rs/core/src/unified_exec/`

**Relevance**: Medium — only relevant if the Elixir SDK speaks the core protocol (exec JSONL does not
surface these).

---

## 7. AbsolutePathBuf Sandbox Config

### Commit: `642b7566d`

### What Changed Upstream

- Changes sandbox `writable_roots` (workspace-write) to `AbsolutePathBuf`.
- Resolves relative paths in `config.toml` against the config file’s directory.

### References

- Config: `codex-rs/core/src/config/types.rs` (`SandboxWorkspaceWrite`)
- Absolute path utility: `codex-rs/utils/absolute-path/src/lib.rs`

**Relevance**: Medium if the SDK exposes writable roots / `--add-dir` style options.

---

## 8. Exec Policy File Rename

### Commit: `e0d7ac51d`

### What Changed Upstream

- Exec policy files moved from `~/.codex/policy/*.codexpolicy` to `~/.codex/rules/*.rules`.

**Relevance**: Low (docs-only unless SDK manages these files)

---

## Summary: Required Changes for Elixir Port (From This Sync)

- Clarify transport target (exec JSONL vs core/app-server protocol); many “core” features require a
  new integration layer.
- Correctly document codex-rs OTEL config (TOML-based) vs Elixir-side OTLP export (`lib/codex/telemetry.ex`).
- Treat models/skills/config layers as transport-dependent features rather than unconditional SDK
  requirements.

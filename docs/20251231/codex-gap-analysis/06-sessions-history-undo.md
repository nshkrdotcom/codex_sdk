# Sessions, History, and Undo Gaps

Agent: sessions

Upstream references
- `codex/docs/getting-started.md`
- `codex/codex-rs/core/src/tasks/ghost_snapshot.rs`
- `codex/codex-rs/core/src/tasks/undo.rs`
- `codex/codex-rs/cli/src/main.rs`

Elixir references
- `lib/codex/sessions.ex`
- `lib/codex/thread.ex`
- `lib/codex/app_server.ex`

Gaps and deviations
- Gap: ghost snapshot and undo workflows are not surfaced in the SDK. Codex CLI creates ghost snapshots for undo and has undo tasks; SDK has no API to trigger undo or inspect ghost snapshot items. Refs: `codex/codex-rs/core/src/tasks/ghost_snapshot.rs`, `codex/codex-rs/core/src/tasks/undo.rs`.
- Gap: `codex apply` CLI command (apply last diff) is not exposed. Provide a wrapper or add an SDK helper that replays file_change items into local patches. Refs: `codex/codex-rs/cli/src/main.rs`, `lib/codex/items.ex`.
- Gap: thread/resume advanced options (history, path) are not exposed on app-server; needed for advanced resume workflows. Refs: `codex/codex-rs/app-server-protocol/src/protocol/v2.rs`, `lib/codex/app_server.ex`.
- Gap: history persistence controls from config (`history.persistence`, `history.max_bytes`) are not surfaced as SDK options; only available via manual config overrides. Refs: `codex/docs/config.md`, `lib/codex/thread/options.ex`.
- Deviation: Sessions.list_sessions reads a subset of metadata fields; if new metadata fields are added upstream, they are ignored. Consider parsing unknown keys into a `metadata` field. Refs: `lib/codex/sessions.ex`.

Implementation notes
- Enable experimental_raw_events and add parsing for ghost snapshot items if implementing undo or snapshot awareness.
- For `codex apply`, a minimal wrapper can shell out to `codex apply` and surface stdout/stderr for parity.

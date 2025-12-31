# Prompt - App-Server Protocol and Sessions Parity

Goal
Implement all work described in these plans:
- docs/20251231/codex-gap-analysis/plans/plan-00-overview.md
- docs/20251231/codex-gap-analysis/plans/plan-02-app-server-protocol.md
- docs/20251231/codex-gap-analysis/plans/plan-06-sessions-history-undo.md

Required reading before coding
Gap analysis docs
- docs/20251231/codex-gap-analysis/02-app-server-protocol.md
- docs/20251231/codex-gap-analysis/06-sessions-history-undo.md

Upstream references
- codex/codex-rs/app-server-protocol/src/protocol/v2.rs
- codex/codex-rs/app-server-protocol/src/protocol/common.rs
- codex/docs/getting-started.md
- codex/codex-rs/core/src/tasks/ghost_snapshot.rs
- codex/codex-rs/core/src/tasks/undo.rs
- codex/codex-rs/cli/src/main.rs

Elixir sources
- lib/codex/app_server.ex
- lib/codex/app_server/params.ex
- lib/codex/app_server/notification_adapter.ex
- lib/codex/app_server/item_adapter.ex
- lib/codex/transport/app_server.ex
- lib/codex/items.ex
- lib/codex/thread.ex
- lib/codex/sessions.ex
- lib/codex/events.ex

Context and constraints
- Ignore the known CLI bundling difference; do not edit codex/ except for reference.
- Preserve backward compatibility; add v1 compatibility helpers or explicit errors as needed.
- Use ASCII-only edits.

Implementation requirements
- Add thread_resume support for history and path.
- Add skills/list force_reload support.
- Add fuzzy_file_search helper for v1.
- Handle rawResponseItem/completed and deprecationNotice notifications.
- Parse raw response items when experimental_raw_events is enabled.
- Avoid passing sandbox defaults unless explicitly set.
- Surface ghost snapshot and undo workflows in the SDK.
- Provide an apply helper consistent with codex apply (without bundling the CLI).
- Expose history persistence options and preserve unknown session metadata.

Documentation and release requirements
- Update README.md and any affected guides in docs/ and examples/.
- Update CHANGELOG.md 0.4.6 entry with the changes implemented here.
- Update the 0.4.6 highlights in README.md.

Testing and quality requirements
- Run: mix format
- Run: mix test
- Run: MIX_ENV=test mix credo --strict
- Run: MIX_ENV=dev mix dialyzer
- No warnings or errors are acceptable.

Deliverable
- Provide a concise change summary and list the tests executed.

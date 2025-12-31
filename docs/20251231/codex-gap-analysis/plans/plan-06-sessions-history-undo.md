# Implementation Plan - Sessions, History, and Undo

Source
- docs/20251231/codex-gap-analysis/06-sessions-history-undo.md

Goals
- Surface ghost snapshot and undo workflows in the SDK.
- Provide an apply helper consistent with `codex apply` behavior.
- Expose history persistence controls.

Scope
- Sessions API, app-server item parsing, and new helpers for undo/apply.
- Config options for history persistence.

Plan
1. Add raw item types for ghost snapshots and undo tasks.
   - Parse raw response items when experimental_raw_events is enabled.
   - Files: lib/codex/app_server/item_adapter.ex, lib/codex/items.ex.
2. Provide an undo helper API.
   - Implement a wrapper that triggers the undo workflow (app-server or exec task).
   - Surface clear errors if undo is unavailable for the transport.
   - Files: lib/codex/sessions.ex or new Codex.Undo module.
3. Implement apply helper.
   - Provide a helper that replays file_change items or shells out to `codex apply`
     when available (without relying on bundled CLI).
   - Files: lib/codex/sessions.ex, lib/codex/items.ex, lib/codex/exec.ex.
4. Expose history persistence options.
   - Add history.persistence and history.max_bytes to options/config overrides.
   - Files: lib/codex/thread/options.ex, lib/codex/options.ex.
5. Preserve unknown metadata fields in Sessions.list_sessions.
   - Add a metadata map for unrecognized fields to avoid dropping data.
   - Files: lib/codex/sessions.ex.
6. Align thread_resume options with app-server v2.
   - Ensure history and path are supported (shared with plan-02).
   - Files: lib/codex/app_server.ex.

Tests
- Item parsing tests for ghost snapshot/undo raw events.
- Sessions metadata preservation tests.
- Apply/undo helper tests with stubbed data.

Docs
- Update README and docs/ to describe undo/apply workflows and history persistence.

Acceptance criteria
- Undo and apply workflows are discoverable and test-covered.
- History persistence options are documented and forwarded correctly.

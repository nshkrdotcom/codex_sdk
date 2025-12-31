# Implementation Plan - App-Server Protocol

Source
- docs/20251231/codex-gap-analysis/02-app-server-protocol.md

Goals
- Support missing app-server protocol fields and methods.
- Surface raw response items and deprecation notifications.
- Avoid overriding server defaults for sandbox unless explicitly set.

Scope
- App-server request/response structs and adapters.
- Notification and item parsing.
- Optional compatibility helpers for v1 endpoints.

Plan
1. Extend thread resume parameters.
   - Add history and path options to Codex.AppServer.thread_resume/3.
   - Update request params struct or builder.
   - Files: lib/codex/app_server.ex, lib/codex/app_server/params.ex.
2. Add skills_list force_reload.
   - Accept a force_reload flag and pass through to app-server.
   - Files: lib/codex/app_server.ex.
3. Implement fuzzy file search (v1) helper.
   - Add Codex.AppServer.fuzzy_file_search/3 with v1 request shape.
   - Files: lib/codex/app_server.ex, lib/codex/app_server/params.ex.
4. Add v1 compatibility layer (if required).
   - Implement minimal v1 conversation endpoints or provide explicit error when the
     server only supports v1 and the SDK expects v2.
   - Files: lib/codex/app_server.ex or a new Codex.AppServer.V1 module.
5. Expand notification handling.
   - Handle rawResponseItem/completed and deprecationNotice in NotificationAdapter.
   - Introduce new event structs if needed for raw response payloads.
   - Files: lib/codex/app_server/notification_adapter.ex, lib/codex/events.ex.
6. Parse raw response items in ItemAdapter.
   - Add a raw item struct and wire parsing for experimental_raw_events.
   - Files: lib/codex/app_server/item_adapter.ex, lib/codex/items.ex.
7. Avoid default sandbox override for app-server.
   - Only pass sandbox fields when explicitly set by the caller.
   - Files: lib/codex/transport/app_server.ex, lib/codex/app_server/params.ex.

Tests
- Add request/response tests for thread_resume history/path and skills_list force_reload.
- Add tests for fuzzy_file_search payloads.
- Add notification parsing tests for rawResponseItem/completed and deprecationNotice.
- Add item parsing tests for raw response items.

Docs
- Update README and docs/ for new APIs and compatibility notes.
- Document experimental_raw_events behavior when raw items are surfaced.

Acceptance criteria
- New protocol fields are serialized and parsed correctly.
- Raw response events are accessible without breaking existing item parsing.
- Default sandbox behavior matches upstream app-server expectations.

# App-Server Protocol Gaps

Agent: app-server

Upstream references
- `codex/codex-rs/app-server-protocol/src/protocol/common.rs`
- `codex/codex-rs/app-server-protocol/src/protocol/v2.rs`

Elixir references
- `lib/codex/app_server.ex`
- `lib/codex/app_server/notification_adapter.ex`
- `lib/codex/app_server/item_adapter.ex`
- `lib/codex/app_server/params.ex`

Gaps and deviations
- Gap: thread/resume supports history and path in v2, but Elixir only accepts thread_id. Implement optional `history` and `path` params in `Codex.AppServer.thread_resume/3`. Refs: `codex/codex-rs/app-server-protocol/src/protocol/v2.rs`, `lib/codex/app_server.ex`.
- Gap: skills/list supports force_reload, but SDK only passes cwds. Add `force_reload` in `Codex.AppServer.skills_list/2`. Refs: `codex/codex-rs/app-server-protocol/src/protocol/v2.rs`, `lib/codex/app_server.ex`.
- Gap: fuzzy file search request (v1) is not exposed; this powers the @ file search in TUI. Add `Codex.AppServer.fuzzy_file_search/3` for compatibility. Refs: `codex/codex-rs/app-server-protocol/src/protocol/common.rs`, `lib/codex/app_server.ex`.
- Gap: v1 conversation APIs (newConversation, listConversations, resumeConversation, sendUserMessage, sendUserTurn, interruptConversation, add/remove listener) are not implemented; older servers will fail. Consider adding a compatibility module or explicit fallback. Refs: `codex/codex-rs/app-server-protocol/src/protocol/common.rs`, `lib/codex/app_server.ex`.
- Gap: NotificationAdapter lacks explicit handling for `rawResponseItem/completed` and `deprecationNotice`. These currently fall through to AppServerNotification, making it hard to consume raw response items or deprecation warnings. Refs: `codex/codex-rs/app-server-protocol/src/protocol/common.rs`, `lib/codex/app_server/notification_adapter.ex`.
- Gap: experimental_raw_events are supported in thread/start, but ItemAdapter does not parse raw response items (ghost snapshots, compaction, etc). Add a raw item struct or a passthrough event type. Refs: `lib/codex/app_server/item_adapter.ex`, `lib/codex/items.ex`.
- Gap: SDK always sends a sandbox value for app-server threads due to :default mapping; this overrides server-side defaults and trust flow. Consider skipping sandbox unless explicitly set. Refs: `lib/codex/transport/app_server.ex`, `lib/codex/app_server/params.ex`.

Implementation notes
- Add a small v1 compatibility layer that mirrors the protocol structs if supporting older app-servers is required.
- For rawResponseItem/completed, consider a dedicated event struct that surfaces the raw item payload without forcing conversion to Codex.Items.

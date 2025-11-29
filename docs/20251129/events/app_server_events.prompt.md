# Prompt: Implement app-server event changes in the Elixir SDK (TDD)

Required reading:
- docs/20251129/events/app_server_events.md
- docs/05-api-reference.md (event shapes and streaming semantics)
- lib/codex/events.ex, lib/codex/thread.ex, lib/codex/items.ex (event parsing/dispatch)
- test/codex/events_test.exs, test/codex/thread_test.exs (existing coverage for event handling)

Context to carry:
- New events: `thread/tokenUsage/updated`, `turn/diff/updated`, explicit compaction notifications.
- Item/error notifications now include `thread_id` and `turn_id`.
- Token usage and diff events should stream alongside existing turn/item updates.

Instructions (TDD):
1) Read the required docs to understand expected payloads and semantics.
2) Add/extend decoding structs and dispatch so the new events and ids are accepted; prefer explicit `thread_id`/`turn_id`.
3) Write failing tests in the listed test files (or new ones) for each new event and id propagation.
4) Implement the parsing/handling to make tests pass without regressing legacy events.
5) Ensure streaming handlers surface token-usage/diff data; update docs/API types if exposed.
6) Run `mix test` (and targeted file tests) until green. No CI-only steps.

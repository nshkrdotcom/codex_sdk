# App-server events to track in the Elixir SDK

Summary of upstream changes (2025-10-19 .. 2025-11-28):
- Added new v2 notifications: `thread/tokenUsage/updated` and `turn/diff/updated`, plus explicit compaction events for turns.
- Item and error notifications now carry `thread_id` and `turn_id` fields for better correlation.
- Streamed token usage and diff events are emitted alongside existing turn and item streams.
- Process IDs surfaced for event handling to aid correlation.

Impact on the Elixir SDK:
- Event parsing in `CodexSdk` should accept the new event names and payload shapes.
- When normalizing events, prefer the `thread_id`/`turn_id` fields instead of inferring from context.
- Update any telemetry or logging that assumed only legacy event names so consumers see the new events.

Action items:
- Extend event decoding structs/tests to cover `thread/tokenUsage/updated`, `turn/diff/updated`, and compaction notifications.
- Add regression coverage for payloads that include `thread_id` and `turn_id`.
- Verify streaming handlers surface token-usage deltas without breaking existing turn/item handling.

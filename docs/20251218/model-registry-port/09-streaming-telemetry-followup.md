# Streaming Telemetry Follow-up

## Problem

The live telemetry example attaches handlers for thread lifecycle, usage, diff, and compaction
events. In streamed runs, the SDK emits only progress telemetry (usage/diff/compaction). The
thread lifecycle events (`[:codex, :thread, :start|:stop|:exception]`) are emitted only in the
blocking exec path, so the streamed example can appear idle for long stretches until a turn
completes.

## Decision

Emit thread lifecycle telemetry for streamed exec runs, but keep the change minimal:

- Add `[:codex, :thread, :start]` and `[:codex, :thread, :stop]` in the streamed exec path so
  streamed runs show immediate progress.
- Treat turn-level failures (`turn.failed` or `turn.completed` with `status=failed`) as `:error`
  results in the stop event metadata, matching the blocking path.
- Do not attempt to intercept transport-level exceptions raised by the stream enumerable. Catching
  those would require wrapping or altering the underlying enumerable, which risks changing lazy
  semantics. Transport exceptions will continue to raise to the caller.

This keeps real-time telemetry visible for the primary streaming API (`Thread.run_streamed/3`)
without reworking the exec streaming internals.

## Implementation Notes

- Implement lifecycle emission in `Thread.run_turn_streamed_exec_jsonl/3`, reusing the same
  metadata fields as the blocking path (input, originator, span_token, trace metadata).
- Track `thread_id`/`turn_id`/`source` incrementally from streamed events to populate stop metadata.
- Emit stop telemetry only when a terminal turn event is observed, so early consumer cancellation
  does not produce misleading lifecycle events.
- Update the live telemetry example to communicate that runs can take 30-60s and that some telemetry
  updates may only arrive at completion depending on the prompt.

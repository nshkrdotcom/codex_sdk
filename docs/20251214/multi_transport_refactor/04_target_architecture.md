# Target Architecture for `codex_sdk` (Exec + App-Server)

## Goal

Support both upstream transports:

- **Exec JSONL**: `codex exec` JSONL output (`--experimental-json` in `codex_sdk` today)
- **App-server JSON-RPC**: `codex app-server` (new)

…while keeping a unified, Elixir-native public API (threads, turns, streaming events, approvals).

## High-level approach

1. Introduce a **transport abstraction** so `Codex.Thread` is no longer hard-wired to `Codex.Exec`.
2. Implement a new **app-server transport** as a long-lived supervised process that:
   - speaks newline-delimited JSON-RPC over stdio
   - maps app-server notifications into the existing `Codex.Events`/`Codex.Items` model
   - handles server-initiated approval requests using existing `Codex.Approvals.Hook` callbacks
3. Keep `exec` as the default transport for backwards compatibility.

## Proposed module layout

### Transport behaviour

Add a `Codex.Transport` behaviour (or similar) that defines the minimum needed by `Codex.Thread`:

- `run_turn(thread, input, turn_opts)`
- `run_turn_streamed(thread, input, turn_opts)`
- `interrupt(thread, turn_id)` (optional for exec; meaningful for app-server)

Then:
- `Codex.Transport.ExecJsonl` wraps existing `Codex.Exec` logic
- `Codex.Transport.AppServer` wraps a connection process

### App-server connection process

Implement a `Codex.AppServer.Connection` GenServer that owns:

- the subprocess (`codex app-server`)
- stdout/stderr buffering + JSON line decoding
- request id allocation + in-flight request map
- subscriber registry for notifications

Rough responsibilities:

1. **Startup**
   - spawn `codex app-server`
   - send `initialize` request + wait for response
   - send `initialized` notification
   - transition to `:ready`
   - docs: `codex/codex-rs/app-server/README.md:39`

2. **Client requests (call/response)**
   - `GenServer.call(conn, {:request, method, params})`
   - send JSON with `id`, `method`, `params`
   - match incoming `{ "id": ..., "result": ... }` responses back to the caller

3. **Server notifications (streaming)**
   - parse `{ "method": "...", "params": ... }` messages
   - map them into canonical `Codex.Events` structs
   - broadcast to subscribers (per thread/turn filtering)

4. **Server requests (approvals)**
   - parse `{ "id": ..., "method": "item/*/requestApproval", "params": ... }`
   - translate into an approval “event”
   - invoke `Codex.Approvals.Hook.review_command/3` or `review_file/3` (see `lib/codex/approvals/hook.ex:94`)
   - send the response JSON-RPC `{ "id": ..., "result": ... }`

## Event model strategy

### Canonical events

Keep `Codex.Events` as the canonical event surface, and adapt app-server notifications into it.

This is already partially anticipated:
- `Codex.Events` accepts both dot and slash variants for some types (see `lib/codex/events.ex:369` and `lib/codex/events.ex:379`).

### Adapter layer

Add an adapter that converts app-server notifications into maps compatible with `Codex.Events.parse!/1`:

- app-server notification: `{ "method": "turn/started", "params": { ... } }`
- normalized event map: `%{"type" => "turn.started", ...}`
- parse into `%Codex.Events.TurnStarted{...}`

Similarly, app-server thread items are camelCase unions; normalize them into the snake_case item maps expected by `Codex.Items.parse!/1` (see `lib/codex/items.ex:219`).

## Public API shape

### Backwards compatible default

Keep:
- `Codex.start_thread/2`
- `Codex.resume_thread/3`
- `Codex.Thread.run_turn/3` and `run_turn_streamed/3`

Add a new option to choose transport (default `:exec`):

- `transport: :exec | {:app_server, pid()}`

For `{:app_server, pid()}`, the returned `%Codex.Thread{}` must carry a reference to the connection process.

### “Full parity” API additions (app-server-only)

Expose new capabilities behind `Codex.AppServer.*` or `Codex.Thread.*` additions:

- thread history: `thread/list`, `thread/archive`, `thread/compact`
- `model/list`
- `config/read`, `config/value/write`, `config/batchWrite`
- `skills/list`
- `review/start`
- account endpoints and OAuth flows

## Process supervision

Add a supervision tree for app-server connections:

- `Codex.AppServer.Supervisor` (DynamicSupervisor)
- each connection supervised and restartable

Threads reference their owning connection pid; on connection restart, threads become invalid unless reattached. Document this explicitly.

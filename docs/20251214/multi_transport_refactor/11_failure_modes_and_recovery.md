# Failure Modes & Recovery

This document specifies how `codex_sdk` must handle failures, timeouts, and recovery scenarios when using the app-server transport.

## Process Lifecycle Failures

### F1: App-Server Process Fails to Start

**Trigger**: `codex app-server` binary not found, permission denied, or immediate crash.

**Detection**:
- `:exec.run/2` returns `{:error, reason}`
- Process exits immediately before handshake completes

**Recovery**:
```elixir
case start_app_server(opts) do
  {:error, :enoent} ->
    {:error, {:codex_not_found, opts.codex_path}}
  {:error, {:exit_status, code}} ->
    {:error, {:startup_failed, code, stderr}}
  {:error, reason} ->
    {:error, {:startup_failed, reason}}
end
```

**User-facing behavior**: `Codex.AppServer.connect/1` returns `{:error, reason}`. No retry by default.

### F2: App-Server Process Crashes Mid-Session

**Trigger**: Process receives signal, unhandled panic, OOM kill.

**Detection**:
- `{:DOWN, os_pid, :process, _pid, reason}` message received
- Where `reason` is not `:normal`

**Recovery**:
1. Mark connection state as `:crashed`
2. Fail all in-flight requests with `{:error, {:connection_lost, reason}}`
3. Notify all subscribers with `{:app_server_crashed, reason}`
4. Any thread handles referencing this connection become invalid

**Thread invalidation**:
```elixir
# In Thread struct
defstruct [
  :transport,     # :exec | {:app_server, conn_pid}
  :transport_ref  # monitor ref for app-server connection
]

# On connection crash
def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
  # All threads using this connection are now invalid
  {:stop, {:connection_crashed, reason}, state}
end
```

**Reconnect strategy**: NOT automatic. Users must explicitly create a new connection. Rationale: app-server state is lost on crash; automatic reconnect could cause confusion about thread state.

### F3: App-Server Process Graceful Shutdown

**Trigger**: Server sends clean exit, e.g., during system shutdown.

**Detection**:
- `{:DOWN, os_pid, :process, _pid, :normal}` message

**Recovery**:
1. Mark connection as `:closed`
2. Fail any in-flight requests with `{:error, :connection_closed}`
3. Clean up resources

---

## Handshake Failures

### F4: Initialize Request Times Out

**Trigger**: Server doesn't respond to `initialize` within timeout.

**Detection**: `GenServer.call` timeout on initial request.

**Default timeout**: 10 seconds (configurable via `init_timeout_ms`).

**Recovery**:
```elixir
case send_request(conn, "initialize", params, timeout: init_timeout_ms) do
  {:ok, response} ->
    send_notification(conn, "initialized")
    {:ok, conn}
  {:error, :timeout} ->
    kill_process(conn)
    {:error, {:init_timeout, init_timeout_ms}}
end
```

### F5: Initialize Request Returns Error

**Trigger**: Server rejects initialization (e.g., incompatible client version).

**Detection**: Response contains `error` field instead of `result`.

**Recovery**:
```elixir
case response do
  %{"error" => %{"message" => msg}} ->
    kill_process(conn)
    {:error, {:init_rejected, msg}}
end
```

### F6: Already Initialized Error

**Trigger**: Client sends `initialize` twice.

**Upstream behavior**: Returns error `"Already initialized"`.

**Prevention**: Track initialization state in Connection GenServer; reject duplicate init calls at Elixir level.

---

## Request/Response Failures

### F7: Request Times Out

**Trigger**: Server doesn't respond within timeout.

**Default timeouts**:
| Method | Default Timeout |
|--------|-----------------|
| `turn/start` | 300,000 ms (5 min) |
| `thread/*` | 30,000 ms |
| `skills/list` | 30,000 ms |
| `config/*` | 10,000 ms |
| `command/exec` | Configurable via `timeoutMs` param |

**Detection**: Caller's `GenServer.call` times out.

**Recovery**:
1. Remove request from in-flight map
2. Return `{:error, {:timeout, method, timeout_ms}}`
3. Connection remains usable (request may still complete server-side)

**Important**: A timed-out `turn/start` does NOT automatically interrupt the turn. The turn continues server-side. Use `turn/interrupt` explicitly if needed.

### F8: Request Returns Error Response

**Trigger**: Server returns `{"id": N, "error": {...}}`.

**Error format** (see `codex/codex-rs/app-server-protocol/src/jsonrpc_lite.rs:57-71`):
```json
{
  "id": 42,
  "error": {
    "code": -32000,
    "message": "Thread not found",
    "data": {"details":"..."}
  }
}
```

**Recovery**: Return `{:error, %Codex.AppServer.Error{message: msg, code: code, data: data, request_id: id}}`.

### F9: Malformed Response

**Trigger**: Server sends invalid JSON or response missing `id`.

**Detection**: JSON parse failure or missing `id` field.

**Recovery**:
- Log warning
- For responses: cannot correlate to request, log and continue
- For notifications: skip and continue
- Consider connection unhealthy after N consecutive malformed messages

### F10: Response ID Mismatch

**Trigger**: Server sends response with `id` that doesn't match any in-flight request.

**Possible causes**:
- Client timed out and removed request before response arrived
- Protocol bug

**Recovery**: Log warning, discard response, continue.

---

## Notification Handling Failures

### F11: Unknown Notification Method

**Trigger**: Server sends notification with unrecognized `method`.

**Example**: Future protocol version adds new notification type.

**Recovery**: Log at debug level, discard. Do NOT crash. Forward compatibility is important.

### F12: Malformed Notification Params

**Trigger**: Notification has wrong param structure.

**Recovery**:
- Attempt lenient parsing (missing optional fields → defaults)
- If parsing fails completely, log warning and discard
- Do NOT fail the connection

---

## Approval Request Failures

### F13: Approval Request Times Out (Client Side)

**Trigger**: Hook's `await/2` callback returns `{:error, :timeout}`.

**Default timeout**: Configurable via `approval_timeout_ms` (default: 30,000 ms).

**Recovery**:
1. Send `Decline` response to server
2. Log that approval timed out
3. Turn will proceed with declined status

```elixir
case Hook.await(ref, timeout) do
  {:ok, decision} -> send_approval_response(request_id, decision)
  {:error, :timeout} ->
    Logger.warning("Approval timeout for #{request_id}")
    send_approval_response(request_id, :decline)
end
```

### F14: Approval Hook Crashes

**Trigger**: Hook callback raises exception.

**Recovery**:
1. Catch exception
2. Log error with stacktrace
3. Send `Decline` response (fail-safe)
4. Continue processing

```elixir
try do
  Hook.review_command(event, context, opts)
rescue
  e ->
    Logger.error("Approval hook crashed: #{Exception.message(e)}")
    send_approval_response(request_id, :decline)
end
```

### F15: Approval Response Fails to Send

**Trigger**: Connection dies between receiving approval request and sending response.

**Recovery**: Connection crash handling (F2) takes over. Turn on server side will eventually timeout.

---

## Stdio Buffering Issues

### F16: Partial Line in Buffer at EOF

**Trigger**: Process exits with incomplete line in stdout buffer.

**Recovery**:
1. On process exit, check if buffer contains data
2. If buffer is non-empty but no newline, log warning
3. Attempt to parse as JSON anyway (might be complete message without trailing newline)
4. If parse fails, include in error diagnostics

### F17: Stdout/Stderr Interleaving

**Trigger**: App-server writes to both stdout and stderr.

**Upstream behavior**: JSON-RPC goes to stdout; logs/errors may go to stderr.

**Recovery**:
- Keep stdout and stderr buffers separate
- Only parse stdout for JSON-RPC
- Collect stderr for diagnostics on crash/error

### F18: Very Large Message

**Trigger**: Single JSON message exceeds memory limits.

**Mitigation**: Set reasonable buffer limits (e.g., 100 MB).

**Recovery**: If buffer exceeds limit, kill connection with `{:error, :message_too_large}`.

---

## Concurrency Issues

### F19: Out-of-Order Responses

**Trigger**: Server sends responses in different order than requests.

**Example**:
```
Client: Request id=1
Client: Request id=2
Server: Response id=2
Server: Response id=1
```

**Handling**: Use request ID map, not queue. Order doesn't matter.

### F20: Notifications During Request

**Trigger**: Server sends notifications while client is waiting for response.

**Example**:
```
Client: turn/start (id=1)
Server: turn/started (notification)
Server: item/started (notification)
Server: item/agentMessage/delta (notification)
Server: Response (id=1)
```

**Handling**: Process all messages in order:
1. For notifications: dispatch to subscribers immediately
2. For responses: match to waiting caller
3. Do NOT block notifications waiting for responses

### F21: Multiple Turns Concurrent on Same Thread

**Trigger**: Client calls `turn/start` while previous turn still in progress.

**Upstream behavior**: Should return error (only one active turn per thread).

**Elixir handling**: Track turn state per thread; reject concurrent turn attempts at SDK level with clear error.

---

## Resource Exhaustion

### F22: Too Many In-Flight Requests

**Trigger**: Client sends many requests without waiting for responses.

**Mitigation**: Configurable limit (default: 100 concurrent requests).

**Recovery**: When limit reached, new requests return `{:error, :too_many_requests}`.

### F23: Subscriber Mailbox Growth

**Trigger**: Notification subscriber doesn't consume fast enough.

**Mitigation**:
- Use `Process.monitor/1` on subscribers
- Drop notifications for dead subscribers
- Consider bounded subscription queues

### F24: Memory Growth from Buffered Events

**Trigger**: Large turn with many events; nobody consuming stream.

**Mitigation**:
- Streaming API (don't buffer entire turn)
- If blocking API, warn in docs about memory usage for large turns

---

## Recovery Strategies Summary

| Failure | Auto-Recovery | Manual Recovery |
|---------|---------------|-----------------|
| Process crash | No | Create new connection |
| Init timeout | No | Retry with new connection |
| Request timeout | Yes (connection stays open) | Retry request |
| Malformed message | Yes (skip and continue) | None needed |
| Approval timeout | Yes (decline) | Configure longer timeout |
| Unknown notification | Yes (ignore) | None needed |

---

## Monitoring & Observability

### Telemetry Events

```elixir
# Connection events
[:codex, :app_server, :connection, :start]
[:codex, :app_server, :connection, :stop]      # reason: :normal | :crashed | :killed
[:codex, :app_server, :connection, :error]

# Request events
[:codex, :app_server, :request, :start]        # method, params
[:codex, :app_server, :request, :stop]         # duration, result
[:codex, :app_server, :request, :timeout]      # method, timeout_ms

# Notification events
[:codex, :app_server, :notification, :received] # method
[:codex, :app_server, :notification, :unknown]  # method (unrecognized)

# Approval events
[:codex, :app_server, :approval, :requested]
[:codex, :app_server, :approval, :completed]    # decision, duration
[:codex, :app_server, :approval, :timeout]
```

### Health Checks

```elixir
def health_check(conn) do
  case send_request(conn, "thread/list", %{limit: 1}, timeout: 5000) do
    {:ok, _} -> :healthy
    {:error, reason} -> {:unhealthy, reason}
  end
end
```

---

## Thread Survival Across Connection Issues

**Important clarification**: Threads are persisted server-side as rollout files. The thread data survives connection loss.

**What survives**:
- Thread history (persisted to disk)
- Thread ID (can be used with new connection)

**What doesn't survive**:
- Active turn state (turn may complete or fail server-side)
- Notification subscriptions (must re-subscribe)

**Recovery pattern**:
```elixir
# After connection loss, to continue a thread:
{:ok, new_conn} = Codex.AppServer.connect(opts)
{:ok, _} = Codex.AppServer.thread_resume(new_conn, thread_id)
# Thread is now usable again
```

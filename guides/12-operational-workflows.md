# Operational Workflows

This guide covers the newly synced runtime workflows that sit between local
authoring and normal thread execution:

- marketplace acquisition
- MCP inventory and thread-scoped MCP execution
- thread history injection and memory controls
- filesystem watches

## Marketplace Acquisition

There are now two runtime entry points for adding a marketplace source:

- `Codex.CLI.marketplace_add/2`
- `Codex.AppServer.marketplace_add/3`

CLI passthrough:

```elixir
{:ok, result} =
  Codex.CLI.marketplace_add(
    "./source-marketplace",
    cwd: "/tmp/workspace",
    env: %{"CODEX_HOME" => "/tmp/codex-home"}
  )

IO.puts(result.stdout)
```

App-server request:

```elixir
{:ok, conn} =
  Codex.AppServer.connect(codex_opts,
    cwd: "/tmp/workspace",
    process_env: %{"CODEX_HOME" => "/tmp/codex-home"}
  )

{:ok, response} =
  Codex.AppServer.marketplace_add(
    conn,
    "./source-marketplace",
    ref_name: "main",
    sparse_paths: ["plugins/demo-plugin"]
  )

IO.inspect(response)
```

Use isolated `CODEX_HOME` values for examples, tests, and migration flows so
you do not mutate your real installed marketplace set unintentionally.

## Thread Repair And Memory Controls

### Inject raw response items

`thread/inject_items` appends raw Responses API items to the thread's
model-visible history.

```elixir
items = [
  %{
    "type" => "message",
    "role" => "assistant",
    "content" => [%{"type" => "output_text", "text" => "Recovered checkpoint"}]
  }
]

{:ok, %{}} = Codex.AppServer.thread_inject_items(conn, thread_id, items)
```

Use this when a host flow needs to reconstruct or repair thread-visible state
after an out-of-band recovery step.

### Toggle thread memory mode

`thread/memoryMode/set` is experimental and requires `experimental_api: true`
when connecting.

```elixir
{:ok, conn} = Codex.AppServer.connect(codex_opts, experimental_api: true)
{:ok, %{}} = Codex.AppServer.thread_memory_mode_set(conn, thread_id, :disabled)
```

Accepted local forms:

- `:enabled`
- `:disabled`
- `"enabled"`
- `"disabled"`

### Reset memory state

`memory/reset` is also experimental and destructive. Use it only with an
isolated `CODEX_HOME` unless you explicitly want to clear the active memory
store for that Codex home.

```elixir
{:ok, conn} = Codex.AppServer.connect(codex_opts, experimental_api: true)
{:ok, %{}} = Codex.AppServer.memory_reset(conn)
```

## MCP Inventory And Execution

The app-server MCP helper now supports:

- inventory detail filtering
- resource reads
- thread-scoped tool calls

### Inventory detail

```elixir
{:ok, %{"data" => servers}} =
  Codex.AppServer.Mcp.list_servers(conn, detail: :tools_and_auth_only)
```

Accepted detail selectors:

- `:full`
- `:tools_and_auth_only`

### Resource reads

```elixir
{:ok, %{"contents" => contents}} =
  Codex.AppServer.Mcp.resource_read(conn, thread_id, "codex_apps", "test://resource")
```

### Tool calls

```elixir
{:ok, response} =
  Codex.AppServer.Mcp.tool_call(
    conn,
    thread_id,
    "docs",
    "search",
    arguments: %{"query" => "rate limits"},
    meta: %{"source" => "sdk"}
  )

IO.inspect(response["structuredContent"])
```

Treat MCP tool execution as an external side-effect boundary. Do not auto-run
arbitrary tools just because they are discoverable.

## Filesystem Watches

The thin app-server filesystem wrapper now includes `fs/watch` and `fs/unwatch`.
Notifications still arrive through the normal `subscribe/2` channel as
`fs/changed`.

```elixir
:ok = Codex.AppServer.subscribe(conn, methods: ["fs/changed"])
{:ok, %{"path" => watched_path}} = Codex.AppServer.fs_watch(conn, "watch_1", "/tmp/demo.txt")

receive do
  {:codex_notification, "fs/changed", params} ->
    IO.inspect(params, label: "fs changed")
after
  5_000 ->
    IO.puts("No fs/changed notification observed")
end

{:ok, %{}} = Codex.AppServer.fs_unwatch(conn, "watch_1")
```

Use stable watch ids that your host can correlate back to the subscribed
workflow.

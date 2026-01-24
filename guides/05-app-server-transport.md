# App-server Transport (JSON-RPC over stdio)

This guide covers using the **stateful** `codex app-server` transport from Elixir via `Codex.AppServer`.

The SDK supports two external Codex transports:

- **Exec JSONL (default, backwards compatible)**: `codex exec --json`
- **App-server JSON-RPC (optional)**: `codex app-server` (newline-delimited JSON messages over stdio)

Use app-server when you need upstream v2 APIs that are not exposed via exec JSONL (threads list/archive, skills/models/config APIs, server-driven approvals, etc.).

## Prerequisites

- A `codex` CLI install that supports `codex app-server` (run `codex app-server --help`).
- Auth via either:
  - `CODEX_API_KEY` (or `auth.json` `OPENAI_API_KEY`), or
  - a Codex CLI login under `CODEX_HOME` (default `~/.codex`).

The SDK resolves the `codex` executable via `codex_path_override` → `CODEX_PATH` → `System.find_executable("codex")`.

## Connect / Disconnect

`Codex.AppServer.connect/2` starts a supervised `codex app-server` subprocess and performs the required `initialize` → `initialized` handshake automatically.

```elixir
{:ok, codex_opts} = Codex.Options.new(%{api_key: System.get_env("CODEX_API_KEY")})
{:ok, conn} = Codex.AppServer.connect(codex_opts)

# ... use conn ...

:ok = Codex.AppServer.disconnect(conn)
```

### Client identity

You can identify your application in the handshake:

```elixir
{:ok, conn} =
  Codex.AppServer.connect(codex_opts,
    client_name: "my_app",
    client_title: "My App",
    client_version: "1.2.3"
  )
```

## Use app-server as a transport for threads/turns

To keep your existing `Codex.Thread.*` usage but switch the underlying transport, set `transport: {:app_server, conn}` in thread options:

```elixir
{:ok, conn} = Codex.AppServer.connect(codex_opts)

{:ok, thread} =
  Codex.start_thread(codex_opts, %{
    transport: {:app_server, conn},
    working_directory: "/path/to/project",
    ask_for_approval: :untrusted,
    sandbox: :workspace_write
  })

{:ok, result} = Codex.Thread.run(thread, "List files and summarize what you see")
```

Streaming works the same way:

```elixir
{:ok, stream} = Codex.Thread.run_streamed(thread, "List the top-level files and summarize them")
Enum.each(stream, &IO.inspect/1)
```

## Call app-server v2 APIs directly

App-server enables additional APIs that are not available via exec JSONL. Examples:

```elixir
{:ok, conn} = Codex.AppServer.connect(codex_opts)

{:ok, %{"data" => skills}} =
  Codex.AppServer.skills_list(conn, cwds: ["/path/to/project"], force_reload: true)
{:ok, %{"data" => models}} = Codex.AppServer.model_list(conn, limit: 25)

When you need feature-flag gating or to load the underlying `SKILL.md` contents,
use `Codex.Skills.list/2` and `Codex.Skills.load/2`, which honor `features.skills`.

{:ok, %{"config" => config}} = Codex.AppServer.config_read(conn, include_layers: false)
{:ok, _} = Codex.AppServer.config_write(conn, "features.web_search_request", true)

{:ok, %{"data" => threads, "nextCursor" => cursor}} = Codex.AppServer.thread_list(conn, limit: 10)

{:ok, %{"files" => files}} =
  Codex.AppServer.fuzzy_file_search(conn, "readme", roots: ["/path/to/project"])
```

Additional v2 APIs include:

- `Codex.AppServer.thread_read/3`, `thread_fork/3`, `thread_rollback/3`, `thread_loaded_list/2`
- `Codex.AppServer.collaboration_mode_list/1` and `Codex.AppServer.apps_list/2`
- `Codex.AppServer.config_requirements/1` and `Codex.AppServer.skills_config_write/3`

When `include_layers: true`, `config_read/2` returns a `layers` list. Recent Codex versions encode each layer's `name` as a tagged union (`ConfigLayerSource`), for example:

```elixir
%{
  "name" => %{"type" => "user", "file" => "/home/me/.codex/config.toml"},
  "version" => "sha256:…",
  "config" => %{}
}
```

See `Codex.AppServer`, Codex.AppServer.Account, and Codex.AppServer.Mcp for the full request surface.

## Thread management

Common thread-history operations are exposed via:

- `Codex.AppServer.thread_list/2` (supports `sort_key` and `archived`)
- `Codex.AppServer.thread_archive/2`
- `Codex.AppServer.thread_read/3` (with optional `include_turns`)
- `Codex.AppServer.thread_fork/3` and `Codex.AppServer.thread_rollback/3`
- `Codex.AppServer.thread_loaded_list/2`
- `Codex.AppServer.thread_resume/3` accepts optional `history` and `path` overrides

### Removed APIs

- `thread_compact/2` - Removed upstream; compaction is now automatic server-side

## Legacy v1 APIs

Older app-server builds only implement the v1 conversation endpoints. Use
`Codex.AppServer.V1` for those flows:

```elixir
{:ok, conn} = Codex.AppServer.connect(codex_opts)

{:ok, convo} = Codex.AppServer.V1.new_conversation(conn, %{})
{:ok, _} = Codex.AppServer.V1.send_user_message(conn, convo["conversationId"], "Hello!")
```

## Notifications and server requests (approvals)

App-server is bidirectional: the server can send notifications at any time, and it can also send **requests** that require a response (approvals).

Subscribe from any process:

```elixir
:ok = Codex.AppServer.subscribe(conn)
```

Messages arrive as:

- Notifications: `{:codex_notification, method, params}`
- Server requests: `{:codex_request, id, method, params}`

You can filter by thread id and/or method list:

```elixir
:ok = Codex.AppServer.subscribe(conn,
  thread_id: "thr_123",
  methods: ["turn/completed", "item/completed", "item/commandExecution/requestApproval"]
)
```

### Raw response items and deprecations

When `experimental_raw_events` is enabled on `thread/start` or
`Codex.AppServer.V1.add_conversation_listener/3`, the server emits
`rawResponseItem/completed` notifications. The SDK maps these to
`%Codex.Events.RawResponseItemCompleted{}` and parses known item types such as
ghost snapshots and compaction payloads. Deprecation warnings are surfaced as
`%Codex.Events.DeprecationNotice{}` from `deprecationNotice` notifications.

Config warnings are surfaced as `%Codex.Events.ConfigWarning{}` from
`configWarning` notifications.

### Request user input

When the agent calls `request_user_input`, app-server sends an
`item/tool/requestUserInput` request. The SDK emits `%Codex.Events.RequestUserInput{}`.
Respond with a `Codex.Protocol.RequestUserInput.Response` payload:

```elixir
response = %Codex.Protocol.RequestUserInput.Response{
  answers: %{
    "q1" => %Codex.Protocol.RequestUserInput.Answer{answers: ["yes"]}
  }
}

:ok = Codex.AppServer.respond(conn, id, Codex.Protocol.RequestUserInput.Response.to_map(response))
```

### Manual approval handling (UI loop)

When Codex needs approval for a command or file change during a `turn/start`, it sends a server request:

- `item/commandExecution/requestApproval`
- `item/fileChange/requestApproval`

Respond by echoing the request `id` back with a result payload containing `decision`.

```elixir
receive do
  {:codex_request, id, "item/commandExecution/requestApproval", _params} ->
    :ok = Codex.AppServer.respond(conn, id, %{decision: "accept"})
end
```

Supported `decision` values include:

- `"accept"`
- `"acceptForSession"`
- `"decline"`
- `"cancel"`
- `%{"acceptWithExecpolicyAmendment" => %{"execpolicyAmendment" => ["git", "status"]}}`

Note: request `id` can be an integer or a string.

### Headless auto-approval via `Codex.Approvals.Hook`

When running turns via `Codex.Thread.*`, you can auto-respond to app-server approvals using `approval_hook` on thread options.

Supported hook returns (backwards compatible):

- `:allow` → `"accept"`
- `{:allow, for_session: true}` → `"acceptForSession"`
- `{:allow, execpolicy_amendment: ["cmd", "arg"]}` → `"acceptWithExecpolicyAmendment"`
- `{:deny, reason}` → `"decline"`

## Turn diffs

On app-server, `turn/diff/updated` provides a **unified diff string**. The SDK surfaces it on `Codex.Events.TurnDiffUpdated.diff`.

## Skills

Skills require the experimental feature flag to be enabled in your codex config:

```toml
# ~/.codex/config.toml
[features]
skills = true
```

Skills can have one of three scopes: `"User"`, `"Repo"`, or `"Public"`.

### Skills caveat

App-server v2 does not support sending `UserInput::Skill` directly today (the union does not include it). Use `skills/list` to discover skills and inject content as text if you need an emulation layer.

## Sandbox Notes

Under `workspace-write` sandbox mode, both `.git/` and `.codex/` directories are automatically marked read-only to prevent privilege escalation.

## Troubleshooting

### `skills/list` returns `-32600` “unknown variant”

If you see a JSON-RPC error like:

- `code: -32600`
- `message: "Invalid request: unknown variant `skills/list` ..."`

your installed `codex app-server` is running a protocol version that does not implement `skills/list` yet. Upgrade the Codex CLI and retry.

## Working live examples

Runnable scripts (against a real `codex` install) live under `examples/`:

- `examples/live_app_server_basic.exs`
- `examples/live_app_server_streaming.exs`
- `examples/live_app_server_approvals.exs`
- `examples/live_app_server_mcp.exs`

Run them with:

```bash
mix run examples/live_app_server_basic.exs
mix run examples/live_app_server_streaming.exs "Reply with exactly ok and nothing else."
mix run examples/live_app_server_approvals.exs
mix run examples/live_app_server_mcp.exs
```

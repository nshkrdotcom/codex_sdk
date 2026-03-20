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

Native OAuth is also available when you want the SDK to manage ChatGPT login
instead of relying on a pre-existing CLI login:

- `oauth: [storage: :file | :auto]` ensures persistent auth exists under the
  effective child `CODEX_HOME` before the child launches
- `oauth: [storage: :memory]` performs external `chatgptAuthTokens` login after
  initialization and optionally auto-answers refresh requests

The SDK resolves the `codex` executable via `codex_path_override` → `CODEX_PATH` → `System.find_executable("codex")`.

If you need the literal command surface instead of the managed JSON-RPC connection,
`Codex.CLI.app_server/1` launches a raw `codex app-server` subprocess session and
`Codex.CLI.run/2` can be used for one-shot passthrough commands.

## Connect / Disconnect

`Codex.AppServer.connect/2` starts a supervised `codex app-server` subprocess and performs the required `initialize` → `initialized` handshake automatically.
If the application supervision tree is unavailable, `connect/2` returns `{:error, :supervisor_unavailable}`.
Pass `experimental_api: true` when you need upstream experimental fields such as
`approvals_reviewer`, granular approval policies, or memory-mode external OAuth auth.

```elixir
{:ok, codex_opts} = Codex.Options.new(%{api_key: System.get_env("CODEX_API_KEY")})
{:ok, conn} = Codex.AppServer.connect(codex_opts, experimental_api: true)

# ... use conn ...

:ok = Codex.AppServer.disconnect(conn)
```

### Child cwd and environment isolation

`Codex.AppServer.connect/2` can also isolate the managed child process itself:

```elixir
tmp_home = Path.join(System.tmp_dir!(), "codex-sdk-app-server-home")

{:ok, conn} =
  Codex.AppServer.connect(codex_opts,
    cwd: "/path/to/project",
    process_env: %{
      "CODEX_HOME" => tmp_home,
      "HOME" => Path.dirname(tmp_home),
      "USERPROFILE" => Path.dirname(tmp_home)
    }
  )
```

Use this when you need hermetic plugin/config examples or a temporary `CODEX_HOME`
without mutating the caller's shell state. `process_env` is the preferred name;
`env` is accepted as an alias for parity with `Codex.CLI.start/2`.

These launch options apply to the app-server child process. Per-thread working
directories still belong on `thread/start`, `thread/resume`, or
`Codex.Thread.Options`.

### OAuth-aware connect

Persistent child auth:

```elixir
{:ok, conn} =
  Codex.AppServer.connect(codex_opts,
    process_env: %{"CODEX_HOME" => "/tmp/codex-home"},
    oauth: [mode: :auto, storage: :file, interactive?: true]
  )
```

Memory-only external auth:

```elixir
{:ok, conn} =
  Codex.AppServer.connect(codex_opts,
    experimental_api: true,
    process_env: %{"CODEX_HOME" => "/tmp/codex-home"},
    oauth: [mode: :auto, storage: :memory, auto_refresh: true]
  )
```

Notes:

- `storage: :file | :auto` resolves auth relative to the child `cwd` and
  `process_env`, then launches the child with that same environment
- `storage: :memory` keeps tokens in memory, calls `account/login/start` with
  `chatgptAuthTokens`, and starts a connection-owned refresh responder
- set `auto_refresh: false` when you want to handle
  `account/chatgptAuthTokens/refresh` yourself via `subscribe/2`

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
{:ok, conn} = Codex.AppServer.connect(codex_opts, experimental_api: true)

{:ok, thread} =
  Codex.start_thread(codex_opts, %{
    transport: {:app_server, conn},
    working_directory: "/path/to/project",
    ephemeral: true,
    service_name: "my_app",
    service_tier: :flex,
    ask_for_approval: %{
      type: :granular,
      sandbox_approval: true,
      rules: true,
      request_permissions: true
    },
    approvals_reviewer: :guardian_subagent,
    sandbox: :workspace_write
  })

{:ok, result} = Codex.Thread.run(thread, "List files and summarize what you see")
```

Streaming works the same way:

```elixir
{:ok, stream} =
  Codex.Thread.run_streamed(
    thread,
    "List the top-level files and summarize them",
    service_tier: :priority
  )
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

encoded = Base.encode64("hello from app-server")
{:ok, _} = Codex.AppServer.fs_write_file(conn, "/tmp/demo.txt", encoded)
{:ok, %{"dataBase64" => encoded_back}} = Codex.AppServer.fs_read_file(conn, "/tmp/demo.txt")
IO.puts(Base.decode64!(encoded_back))

{:ok, %{"marketplaces" => marketplaces}} = Codex.AppServer.plugin_list(conn, cwds: [File.cwd!()])
{:ok, _} = Codex.AppServer.thread_shell_command(conn, "thr_123", "git status --short")
```

Additional v2 APIs include:

- `Codex.AppServer.thread_read/3`, `thread_fork/3`, `thread_shell_command/3`, `thread_rollback/3`, `thread_loaded_list/2`
- `Codex.AppServer.fs_read_file/2`, `fs_write_file/3`, `fs_create_directory/3`, `fs_get_metadata/2`, `fs_read_directory/2`, `fs_remove/3`, `fs_copy/4`
- `Codex.AppServer.plugin_read/3`, `plugin_install/4`, `plugin_uninstall/3`
- `Codex.AppServer.collaboration_mode_list/1` and `Codex.AppServer.apps_list/2`
- `Codex.AppServer.config_requirements/1` and `Codex.AppServer.skills_config_write/3`

Current upstream routing and sync controls are also covered:

- `ephemeral`, `service_name`, and `service_tier` flow through thread lifecycle calls
- per-turn `service_tier` can be passed through `Codex.Thread.run/3`
- `plugin_install/4` and `plugin_uninstall/3` accept `force_remote_sync: true`
- raw plugin maps preserve newer auth metadata such as `needsAuth`

`thread_shell_command/3` is a thin wrapper over the app-server's thread-bound
`!` workflow, so treat it with the same care you would give shell access in the
interactive CLI.

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
- `Codex.AppServer.thread_unarchive/2`
- `Codex.AppServer.thread_compact/2` (uses upstream `thread/compact/start`)
- `Codex.AppServer.thread_read/3` (with optional `include_turns`)
- `Codex.AppServer.thread_fork/3` and `Codex.AppServer.thread_rollback/3`
- `Codex.AppServer.thread_loaded_list/2`
- `Codex.AppServer.thread_resume/3` accepts optional `history`, `path`, and `service_tier` overrides

## Subagent host controls

When a parent turn spawns child threads, the deterministic host-side control
surface lives in `Codex.Subagents`.

In the current vendored runtime, child spawning is still gated behind the
experimental `features.multi_agent` config flag, so enable that before you
expect a parent turn to create children.

Use it for:

- listing subagent threads with `Codex.Subagents.list/2`
- discovering spawned children for a known parent with `Codex.Subagents.children/3`
- reading a known child thread with `Codex.Subagents.read/3`
- parsing typed source metadata with `Codex.Subagents.source/1`
- extracting the parent id with `Codex.Subagents.parent_thread_id/1`
- confirming whether a thread is a spawned child with `Codex.Subagents.child_thread?/1`
- polling a known child thread to a terminal turn state with `Codex.Subagents.await/3`

The typed source structs are:

- `Codex.Protocol.SessionSource`
- `Codex.Protocol.SubAgentSource`

This surface is intentionally limited to inspection and polling over existing
threads. Decisions such as whether to delegate, how many children to create, or
which role to use still belong in the parent prompt rather than helper APIs.

For a runnable live flow that combines prompt-mediated delegation with the full
host-side helper surface, see `examples/live_subagent_host_controls.exs`.

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
  methods: [
    "turn/completed",
    "item/completed",
    "item/commandExecution/requestApproval",
    "item/permissions/requestApproval",
    "item/autoApprovalReview/started",
    "item/autoApprovalReview/completed",
    "serverRequest/resolved"
  ]
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

Current upstream builds also emit `mcpServer/startupStatus/updated`. The SDK
maps that notification to `%Codex.Events.McpServerStartupStatusUpdated{}`,
normalizing the startup `status` and any optional error payload.

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

Question payloads now include `is_other` and `is_secret` when upstream sets them.

### Manual approval handling (UI loop)

When Codex needs approval for a command, file change, or extra permissions during a `turn/start`,
it sends a server request:

- `item/commandExecution/requestApproval`
- `item/fileChange/requestApproval`
- `item/permissions/requestApproval`

Respond by echoing the request `id` back with a result payload containing `decision`.

```elixir
receive do
  {:codex_request, id, "item/commandExecution/requestApproval", _params} ->
    :ok = Codex.AppServer.respond(conn, id, %{decision: "accept"})

  {:codex_request, id, "item/permissions/requestApproval", params} ->
    requested =
      params["permissions"]
      |> Codex.Protocol.RequestPermissions.RequestPermissionProfile.from_map()

    response =
      %Codex.Protocol.RequestPermissions.Response{
        permissions:
          requested
          |> Codex.Protocol.RequestPermissions.RequestPermissionProfile.to_map()
          |> Codex.Protocol.RequestPermissions.GrantedPermissionProfile.from_map(),
        scope: :turn
      }
      |> Codex.Protocol.RequestPermissions.Response.to_map()

    :ok = Codex.AppServer.respond(conn, id, response)
end
```

Supported `decision` values include:

- `"accept"`
- `"acceptForSession"`
- `"decline"`
- `"cancel"`
- `%{"acceptWithExecpolicyAmendment" => %{"execpolicyAmendment" => ["git", "status"]}}`

Note: request `id` can be an integer or a string.

Permissions approvals are different: they do not use string decisions. Reply with a structured
payload containing `"permissions"` and `"scope"` (`"turn"` or `"session"`). Denials are encoded as
an empty granted-permissions profile, not `"decline"`.

### Additional request families

Current upstream builds can also send these server requests:

- `mcpServer/elicitation/request`
- `item/permissions/requestApproval`
- `item/tool/call`
- `account/chatgptAuthTokens/refresh`

And these notifications for review lifecycle / request correlation:

- `item/autoApprovalReview/started`
- `item/autoApprovalReview/completed`
- `serverRequest/resolved`

The SDK's app-server streaming transport surfaces these as typed
`%Codex.Events.*{}` structs, so callers do not need to parse raw JSON-RPC
methods manually. In particular, `%Codex.Events.CommandApprovalRequested{}` now
preserves upstream command approval metadata such as `approval_id`,
`command_actions`, `network_approval_context`, `additional_permissions`,
`proposed_network_policy_amendments`, and `available_decisions`, while
`%Codex.Events.FileApprovalRequested{}` surfaces `grant_root` when the server
includes it. Use `Codex.AppServer.respond/3` with the corresponding protocol
payload maps.

### Headless auto-approval via `Codex.Approvals.Hook`

When running turns via `Codex.Thread.*`, you can auto-respond to app-server approvals using `approval_hook` on thread options.

Supported hook returns (backwards compatible):

- `:allow` → `"accept"`
- `{:allow, for_session: true}` → `"acceptForSession"`
- `{:allow, execpolicy_amendment: ["cmd", "arg"]}` → `"acceptWithExecpolicyAmendment"`
- `{:deny, reason}` → `"decline"`

Permissions approvals use `review_permissions/3` when implemented:

- `:allow` → grant the full requested profile for the current turn
- `{:allow, permissions: subset}` → grant the intersected subset for the current turn
- `{:allow, permissions: subset, scope: :session}` → grant the intersected subset for the session
- `{:deny, reason}` → respond with an empty granted-permissions profile and turn scope

To see live `item/permissions/requestApproval` requests from Codex itself, prefer a granular
approval policy with `request_permissions: true`; the legacy string policies are not enough to
reliably exercise that request path on newer builds. That path also requires the connection to be
initialized with `experimental_api: true`, and stock CLI installs still keep
`request_permissions_tool`, `exec_permission_approvals`, and `guardian_approval`
disabled by default.

See `examples/live_app_server_filesystem.exs` for a runnable `fs/*` walkthrough
and `examples/live_app_server_plugins.exs` for `plugin/list` + `plugin/read`.
Those live scripts probe the connected build first and self-skip when current
Codex binaries do not advertise the older parity methods. The plugin example
creates a disposable repo-local marketplace fixture under the system temp
directory, launches the child process with an isolated temporary `CODEX_HOME`,
and therefore does not need an existing plugin install, does not require a
prior Codex login, does not mutate your real `$CODEX_HOME`, and prints
`needsAuth` whenever the connected runtime includes that field.
`examples/live_app_server_approvals.exs` demonstrates command/file approvals, enables live
permissions approvals with granular `request_permissions: true`, launches the
child inside a disposable temp workspace plus temporary `CODEX_HOME`, enables
the under-development approval feature flags only in that isolated home, retries
without `experimentalApi` when the connected build rejects it, and prints a
deterministic structured-grant fallback when live permissions requests are still
unavailable.
The SDK accepts both `%{type: :granular, ...}` and `%{granular: %{...}}` for these approval
policies and now rejects malformed granular maps instead of silently omitting `approvalPolicy`.
MCP-qualified tool names shown to OpenAI are sanitized to ASCII alphanumerics plus `_` and `-`
before hash/truncation, while original MCP server/tool names are preserved for actual MCP calls.

## Turn diffs

On app-server, `turn/diff/updated` provides a **unified diff string**. The SDK surfaces it on `Codex.Events.TurnDiffUpdated.diff`.

## Skills

Skills require the experimental feature flag to be enabled in your codex config:

```toml
# ~/.codex/config.toml
[features]
skills = true
```

Current upstream skill scopes are `user`, `repo`, `system`, and `admin`.

### Skills caveat

App-server v2 input blocks support both `skill` and `mention`, so you can send
them directly via `thread/start` or `turn/start` payloads after discovering the
target with `skills/list`, `plugin/list`, or app metadata APIs.

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

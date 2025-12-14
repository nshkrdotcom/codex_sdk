# Public API Proposal

This document specifies the Elixir public API for the multi-transport refactor, including backwards compatibility considerations.

## Design Principles

1. **Backwards compatible by default**: Existing code using `Codex.start_thread/2` continues to work unchanged
2. **Transport-agnostic core API**: `Codex.Thread` operations work regardless of transport
3. **Transport-specific extensions**: App-server-only features are clearly namespaced
4. **Progressive disclosure**: Simple use cases stay simple; advanced features are opt-in

---

## Module Structure

```
lib/codex/
├── codex.ex                    # Main entry point (unchanged interface)
├── thread.ex                   # Thread struct + operations (transport-agnostic)
├── options.ex                  # Codex options (unchanged)
├── transport.ex                # NEW: Transport behaviour
├── transport/
│   ├── exec_jsonl.ex           # NEW: Exec transport (wraps existing Codex.Exec)
│   └── app_server.ex           # NEW: App-server transport
├── app_server/
│   ├── connection.ex           # NEW: Connection GenServer
│   ├── supervisor.ex           # NEW: Connection supervisor
│   ├── protocol.ex             # NEW: JSON-RPC encoding/decoding
│   ├── notification_adapter.ex # NEW: Notification → Event mapping
│   └── item_adapter.ex         # NEW: ThreadItem → Items mapping
├── exec.ex                     # Existing (unchanged, but wrapped)
├── events.ex                   # Existing (extended with new event types)
├── items.ex                    # Existing (extended with new item types)
└── approvals/
    └── hook.ex                 # Existing (unchanged interface)
```

---

## Transport Behaviour

```elixir
defmodule Codex.Transport do
  @moduledoc """
  Behaviour for Codex transport implementations.

  Transports handle the communication protocol between the SDK and the Codex runtime.
  """

  @type thread :: Codex.Thread.t()
  @type input :: String.t()
  @type turn_opts :: map()
  @type turn_result :: Codex.Turn.Result.t()
  @type event_stream :: Enumerable.t()

  @doc """
  Executes a single turn and returns the accumulated result.
  """
  @callback run_turn(thread, input, turn_opts) :: {:ok, turn_result} | {:error, term()}

  @doc """
  Executes a turn and returns a stream of events.
  """
  @callback run_turn_streamed(thread, input, turn_opts) :: {:ok, event_stream} | {:error, term()}

  @doc """
  Interrupts a running turn. Optional for transports that don't support it.
  """
  @callback interrupt(thread, turn_id :: String.t()) :: :ok | {:error, term()}

  @optional_callbacks [interrupt: 2]
end
```

---

## Main Entry Point (Codex module)

### Existing API (Unchanged)

```elixir
# These continue to work exactly as before
Codex.start_thread(codex_opts, thread_opts)
Codex.resume_thread(codex_opts, thread_opts, thread_id)
```

### New Option: Transport Selection

```elixir
# Default (exec transport, backwards compatible)
{:ok, thread} = Codex.start_thread(opts, %{working_directory: "/project"})

# Explicit exec transport
{:ok, thread} = Codex.start_thread(opts, %{
  working_directory: "/project",
  transport: :exec
})

# App-server transport (requires connection)
{:ok, conn} = Codex.AppServer.connect(opts)
{:ok, thread} = Codex.start_thread(opts, %{
  working_directory: "/project",
  transport: {:app_server, conn}
})
```

---

## App-Server Connection API

```elixir
defmodule Codex.AppServer do
  @moduledoc """
  App-server transport for stateful, bidirectional communication with Codex.

  ## Usage

      # Connect to app-server
      {:ok, conn} = Codex.AppServer.connect(codex_opts)

      # Use connection for threads
      {:ok, thread} = Codex.start_thread(codex_opts, %{
        transport: {:app_server, conn}
      })

      # Or use app-server specific APIs
      {:ok, skills} = Codex.AppServer.skills_list(conn, cwds: ["/project"])
  """

  @type connection :: pid()
  @type connect_opts :: [
    timeout: pos_integer(),           # Init handshake timeout (default: 10_000)
    client_name: String.t(),          # Client identifier (default: "codex_sdk")
    client_version: String.t()        # Client version (default from mix.exs)
  ]

  @doc """
  Connects to a codex app-server process.

  Spawns the app-server subprocess and performs the initialization handshake.
  Returns a connection process that can be used for subsequent operations.

  ## Options

  - `:timeout` - Handshake timeout in milliseconds (default: 10,000)
  - `:client_name` - Name to identify this client (default: "codex_sdk")
  - `:client_version` - Client version string

  ## Examples

      {:ok, conn} = Codex.AppServer.connect(codex_opts)
      {:ok, conn} = Codex.AppServer.connect(codex_opts, timeout: 30_000)
  """
  @spec connect(Codex.Options.t(), connect_opts()) :: {:ok, connection()} | {:error, term()}
  def connect(codex_opts, opts \\ [])

  @doc """
  Disconnects from the app-server, terminating the subprocess.
  """
  @spec disconnect(connection()) :: :ok
  def disconnect(conn)

  @doc """
  Checks if the connection is alive and responsive.
  """
  @spec alive?(connection()) :: boolean()
  def alive?(conn)
end
```

---

## Thread Operations (App-Server Specific)

```elixir
defmodule Codex.AppServer do
  # Thread lifecycle (app-server only)

  @doc """
  Starts a new thread on the app-server.

  This is the app-server equivalent of `Codex.start_thread/2` but returns
  the thread directly from the server response.
  """
  @spec thread_start(connection(), map()) :: {:ok, map()} | {:error, term()}
  def thread_start(conn, params \\ %{})

  @doc """
  Resumes an existing thread by ID.
  """
  @spec thread_resume(connection(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def thread_resume(conn, thread_id, params \\ %{})

  @doc """
  Lists threads with optional pagination and filtering.

  ## Options

  - `:cursor` - Pagination cursor from previous response
  - `:limit` - Maximum threads to return
  - `:model_providers` - Filter by model provider(s)

  ## Examples

      {:ok, %{data: threads, next_cursor: cursor}} = Codex.AppServer.thread_list(conn)
      {:ok, %{data: more}} = Codex.AppServer.thread_list(conn, cursor: cursor)
  """
  @spec thread_list(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def thread_list(conn, opts \\ [])

  @doc """
  Archives a thread, removing it from the active list.
  """
  @spec thread_archive(connection(), String.t()) :: :ok | {:error, term()}
  def thread_archive(conn, thread_id)

  @doc """
  Compacts a thread's context to reduce token usage.
  """
  @spec thread_compact(connection(), String.t()) :: :ok | {:error, term()}
  def thread_compact(conn, thread_id)
end
```

---

## Turn Operations (App-Server Specific)

```elixir
defmodule Codex.AppServer do
  @doc """
  Starts a turn with the given input.

  Returns immediately with the initial turn state. Subscribe to notifications
  to receive streaming updates.

  ## Input Format

  Input can be a string (text only) or a list of input items:

      # Simple text
      Codex.AppServer.turn_start(conn, thread_id, "Hello")

      # Multiple inputs
      Codex.AppServer.turn_start(conn, thread_id, [
        %{type: :text, text: "Explain this image"},
        %{type: :local_image, path: "/tmp/screenshot.png"}
      ])

  ## Options

  - `:cwd` - Working directory override
  - `:model` - Model override
  - `:approval_policy` - Approval policy override
  - `:sandbox_policy` - Sandbox policy override
  """
  @spec turn_start(connection(), String.t(), String.t() | [map()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def turn_start(conn, thread_id, input, opts \\ [])

  @doc """
  Interrupts a running turn.

  The turn will complete with status "interrupted". Wait for the
  `turn/completed` notification to confirm interruption.
  """
  @spec turn_interrupt(connection(), String.t(), String.t()) :: :ok | {:error, term()}
  def turn_interrupt(conn, thread_id, turn_id)
end
```

---

## Skills API

```elixir
defmodule Codex.AppServer do
  @doc """
  Lists available skills for the given working directories.

  ## Options

  - `:cwds` - List of working directories to scan (default: session cwd)

  ## Returns

  A list of entries, each containing:
  - `:cwd` - The working directory
  - `:skills` - List of skill metadata (name, description, path, scope)
  - `:errors` - List of loading errors for this cwd

  ## Examples

      {:ok, %{data: entries}} = Codex.AppServer.skills_list(conn)
      {:ok, %{data: entries}} = Codex.AppServer.skills_list(conn, cwds: ["/project1", "/project2"])
  """
  @spec skills_list(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def skills_list(conn, opts \\ [])
end
```

---

## Notification Subscriptions

```elixir
defmodule Codex.AppServer do
  @doc """
  Subscribes to notifications from the app-server.

  Notifications are sent as messages to the subscribing process:

      {:codex_notification, method, params}

  ## Options

  - `:thread_id` - Only receive notifications for this thread
  - `:methods` - Only receive specific notification methods

  ## Examples

      # Subscribe to all notifications
      :ok = Codex.AppServer.subscribe(conn)

      # Subscribe to specific thread
      :ok = Codex.AppServer.subscribe(conn, thread_id: "thr_123")

      # Subscribe to specific methods
      :ok = Codex.AppServer.subscribe(conn, methods: ["turn/completed", "item/completed"])

      # Receive in process
      receive do
        {:codex_notification, "item/agentMessage/delta", params} ->
          IO.puts(params["delta"])
      end
  """
  @spec subscribe(connection(), keyword()) :: :ok | {:error, term()}
  def subscribe(conn, opts \\ [])

  @doc """
  Unsubscribes from notifications.
  """
  @spec unsubscribe(connection()) :: :ok
  def unsubscribe(conn)
end
```

---

## Config and Model APIs

```elixir
defmodule Codex.AppServer do
  @doc """
  Reads the effective configuration.
  """
  @spec config_read(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def config_read(conn, opts \\ [])

  @doc """
  Writes a single configuration value.
  """
  @spec config_write(connection(), String.t(), term()) :: :ok | {:error, term()}
  def config_write(conn, key, value)

  @doc """
  Lists available models.
  """
  @spec model_list(connection()) :: {:ok, [map()]} | {:error, term()}
  def model_list(conn)
end
```

---

## Review API

```elixir
defmodule Codex.AppServer do
  @type review_target ::
          {:uncommitted_changes}
          | {:base_branch, String.t()}
          | {:commit, sha :: String.t(), title :: String.t() | nil}
          | {:custom, instructions :: String.t()}

  @doc """
  Starts a code review.

  ## Parameters

  - `conn` - App-server connection
  - `thread_id` - Thread to run review on
  - `target` - What to review
  - `opts` - Additional options

  ## Options

  - `:delivery` - `:inline` (same thread) or `:detached` (new thread)

  ## Examples

      # Review uncommitted changes
      {:ok, result} = Codex.AppServer.review_start(conn, thread_id, {:uncommitted_changes})

      # Review against main branch
      {:ok, result} = Codex.AppServer.review_start(conn, thread_id, {:base_branch, "main"})

      # Review specific commit
      {:ok, result} = Codex.AppServer.review_start(conn, thread_id, {:commit, "abc123", "Fix bug"})
  """
  @spec review_start(connection(), String.t(), review_target(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def review_start(conn, thread_id, target, opts \\ [])
end
```

---

## One-Off Command Execution

```elixir
defmodule Codex.AppServer do
  @doc """
  Executes a command in the sandbox without a thread/turn context.

  Useful for utilities and validation.

  ## Options

  - `:cwd` - Working directory
  - `:sandbox_policy` - Sandbox configuration
  - `:timeout_ms` - Command timeout

  ## Examples

      {:ok, %{exit_code: 0, stdout: output}} =
        Codex.AppServer.command_exec(conn, ["ls", "-la"])

      {:ok, result} =
        Codex.AppServer.command_exec(conn, ["npm", "test"],
          cwd: "/project",
          timeout_ms: 60_000)
  """
  @spec command_exec(connection(), [String.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def command_exec(conn, command, opts \\ [])
end
```

---

## Backwards Compatibility

### Unchanged Behaviors

1. `Codex.start_thread/2` continues to use exec transport by default
2. `Codex.Thread.run/3` and `run_streamed/3` work unchanged
3. `Codex.Events` and `Codex.Items` parsing unchanged
4. `Codex.Approvals.Hook` callbacks unchanged

### Migration Path

**For users wanting app-server features**:

```elixir
# Before (exec only)
{:ok, thread} = Codex.start_thread(opts, %{working_directory: "/project"})
{:ok, result} = Codex.Thread.run(thread, "Hello")

# After (app-server, minimal change)
{:ok, conn} = Codex.AppServer.connect(opts)
{:ok, thread} = Codex.start_thread(opts, %{
  working_directory: "/project",
  transport: {:app_server, conn}
})
{:ok, result} = Codex.Thread.run(thread, "Hello")  # Same API!

# Plus new capabilities
{:ok, skills} = Codex.AppServer.skills_list(conn)
{:ok, threads} = Codex.AppServer.thread_list(conn)
```

### Breaking Changes

**None for existing users.** The refactor is additive.

### Deprecations

**None planned.** Exec transport remains fully supported.

---

## Error Types

```elixir
defmodule Codex.AppServer.Error do
  @moduledoc """
  Error returned from app-server operations.
  """

  defexception [:message, :info, :request_id]

  @type t :: %__MODULE__{
    message: String.t(),
    info: String.t() | nil,  # codexErrorInfo value
    request_id: integer() | nil
  }
end

defmodule Codex.AppServer.ConnectionError do
  @moduledoc """
  Error related to connection lifecycle.
  """

  defexception [:reason, :details]

  @type reason ::
    :not_found           # codex binary not found
    | :startup_failed    # process failed to start
    | :init_timeout      # handshake timed out
    | :init_rejected     # server rejected initialization
    | :connection_lost   # process crashed
    | :connection_closed # graceful shutdown
end
```

---

## Thread Struct Changes

```elixir
defmodule Codex.Thread do
  # Existing fields unchanged
  defstruct thread_id: nil,
            codex_opts: nil,
            thread_opts: nil,
            metadata: %{},
            labels: %{},
            continuation_token: nil,
            usage: %{},
            pending_tool_outputs: [],
            pending_tool_failures: [],
            # NEW: transport reference
            transport: :exec,           # :exec | {:app_server, pid()}
            transport_ref: nil          # monitor ref for app-server
end
```

---

## Configuration

```elixir
# Application config
config :codex_sdk,
  # Default transport (backwards compatible)
  default_transport: :exec,

  # App-server defaults
  app_server: [
    init_timeout_ms: 10_000,
    request_timeout_ms: 30_000,
    turn_timeout_ms: 300_000,
    approval_timeout_ms: 30_000,
    max_concurrent_requests: 100
  ]
```

---

## Type Specifications Summary

```elixir
@type transport :: :exec | {:app_server, pid()}

@type thread_opts :: %{
  optional(:transport) => transport(),
  optional(:working_directory) => String.t(),
  optional(:sandbox) => sandbox_mode(),
  # ... existing options
}

@type connect_result :: {:ok, pid()} | {:error, Codex.AppServer.ConnectionError.t()}
@type request_result :: {:ok, map()} | {:error, Codex.AppServer.Error.t() | term()}
```

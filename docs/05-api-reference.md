# API Reference

Complete API documentation for all modules in the Elixir Codex SDK.

## Module Overview

| Module | Purpose |
|--------|---------|
| `Codex` | Main entry point for starting and resuming threads |
| `Codex.Thread` | Manages conversation threads and turn execution |
| `Codex.Exec` | GenServer managing codex-rs process lifecycle |
| `Codex.Events` | Event type definitions |
| `Codex.Items` | Thread item type definitions |
| `Codex.Options` | Configuration structs |
| `Codex.OutputSchemaFile` | JSON schema file management |

---

## Codex

Main entry point for the Codex SDK. Use this module to create new threads or resume existing ones.

### Functions

#### `start_thread/2`

Creates a new conversation thread with the Codex agent.

**Signature**:
```elixir
@spec start_thread(Codex.Options.t(), Codex.Thread.Options.t()) ::
  {:ok, Codex.Thread.t()} | {:error, term()}
```

**Parameters**:
- `codex_opts` (optional): Global Codex options. Defaults to `%Codex.Options{}`
- `thread_opts` (optional): Thread-specific options. Defaults to `%Codex.Thread.Options{}`

**Returns**:
- `{:ok, thread}`: New thread struct ready for turn execution
- `{:error, reason}`: Configuration error

**Examples**:
```elixir
# Start with defaults
{:ok, thread} = Codex.start_thread()

# Start with custom API key
codex_opts = %Codex.Options{api_key: "sk-..."}
{:ok, thread} = Codex.start_thread(codex_opts)

# Start with thread options
thread_opts = %Codex.Thread.Options{
  model: "o1",
  sandbox_mode: :read_only,
  working_directory: "/path/to/project"
}
{:ok, thread} = Codex.start_thread(%Codex.Options{}, thread_opts)
```

---

#### `resume_thread/3`

Resumes an existing conversation thread from its persisted session.

**Signature**:
```elixir
@spec resume_thread(String.t(), Codex.Options.t(), Codex.Thread.Options.t()) ::
  {:ok, Codex.Thread.t()} | {:error, term()}
```

**Parameters**:
- `thread_id`: ID of the thread to resume (from `~/.codex/sessions`)
- `codex_opts` (optional): Global Codex options
- `thread_opts` (optional): Thread-specific options

**Returns**:
- `{:ok, thread}`: Thread struct with existing thread_id
- `{:error, reason}`: Thread not found or configuration error

**Examples**:
```elixir
# Resume with thread ID
{:ok, thread} = Codex.resume_thread("thread_abc123")

# Resume with custom options
codex_opts = %Codex.Options{base_url: "https://custom.api"}
{:ok, thread} = Codex.resume_thread("thread_abc123", codex_opts)
```

**Notes**:
- Threads are persisted in `~/.codex/sessions` by codex-rs
- Thread history and context are automatically restored
- The thread_id is available after the first turn completes

---

## Codex.Thread

Manages individual conversation threads and turn execution. Threads maintain state across multiple turns.

### Type: `t()`

```elixir
@type t() :: %Codex.Thread{
  thread_id: String.t() | nil,
  codex_opts: Codex.Options.t(),
  thread_opts: Codex.Thread.Options.t()
}
```

**Fields**:
- `thread_id`: Unique thread identifier (nil until first turn completes)
- `codex_opts`: Global Codex configuration
- `thread_opts`: Thread-specific configuration

### Functions

#### `run/3`

Executes a turn and returns the complete result (blocking mode).

**Signature**:
```elixir
@spec run(t(), String.t(), Codex.Turn.Options.t()) ::
  {:ok, Codex.Turn.Result.t()} | {:error, term()}
```

**Parameters**:
- `thread`: Thread struct from `Codex.start_thread/2` or `Codex.resume_thread/3`
- `input`: Prompt or instruction for the agent
- `turn_opts` (optional): Turn-specific options. Defaults to `%Codex.Turn.Options{}`

**Returns**:
- `{:ok, result}`: Complete turn result with items, response, and usage
- `{:error, {:turn_failed, error}}`: Agent encountered an error
- `{:error, reason}`: Other error (process, configuration, etc.)

**Examples**:
```elixir
# Basic usage
{:ok, thread} = Codex.start_thread()
{:ok, result} = Codex.Thread.run(thread, "Explain GenServers")

IO.puts(result.final_response)
# => "GenServers are..."

# With structured output
schema = %{
  "type" => "object",
  "properties" => %{
    "summary" => %{"type" => "string"},
    "key_points" => %{
      "type" => "array",
      "items" => %{"type" => "string"}
    }
  }
}

turn_opts = %Codex.Turn.Options{output_schema: schema}
{:ok, result} = Codex.Thread.run(thread, "Summarize GenServers", turn_opts)

{:ok, data} = Jason.decode(result.final_response)
IO.inspect(data["key_points"])

# Continue conversation
{:ok, result2} = Codex.Thread.run(thread, "Give me an example")
```

**Behavior**:
- Blocks until turn completes
- Accumulates all events internally
- Returns final result with all items
- Thread struct is updated with thread_id after first turn
- Subsequent calls use the same thread_id for context

---

#### `run_streamed/3`

Executes a turn and returns a stream of events (streaming mode).

**Signature**:
```elixir
@spec run_streamed(t(), String.t(), Codex.Turn.Options.t()) ::
  {:ok, Enumerable.t()} | {:error, term()}
```

**Parameters**:
- `thread`: Thread struct
- `input`: Prompt or instruction
- `turn_opts` (optional): Turn-specific options

**Returns**:
- `{:ok, stream}`: Enumerable stream of events
- `{:error, reason}`: Configuration or process error

**Examples**:
```elixir
# Basic streaming
{:ok, thread} = Codex.start_thread()
{:ok, stream} = Codex.Thread.run_streamed(thread, "Analyze this codebase")

for event <- stream do
  case event do
    %Codex.Events.ItemStarted{item: item} ->
      IO.puts("Started: #{item.type}")

    %Codex.Events.ItemCompleted{item: %{type: :agent_message, text: text}} ->
      IO.puts("Response: #{text}")

    %Codex.Events.ItemCompleted{item: %{type: :command_execution} = cmd} ->
      IO.puts("Command: #{cmd.command} (exit: #{cmd.exit_code})")

    %Codex.Events.TurnCompleted{usage: usage} ->
      IO.puts("Tokens: #{usage.input_tokens + usage.output_tokens}")

    _ ->
      :ok
  end
end

# Process first N events
{:ok, stream} = Codex.Thread.run_streamed(thread, "Generate 100 files")
first_10 = Enum.take(stream, 10)

# Filter specific events
{:ok, stream} = Codex.Thread.run_streamed(thread, "Fix bugs")
commands = stream
  |> Stream.filter(fn
    %Codex.Events.ItemCompleted{item: %{type: :command_execution}} -> true
    _ -> false
  end)
  |> Enum.to_list()
```

**Behavior**:
- Returns immediately with stream
- Events yielded as they arrive from codex-rs
- Stream is lazy (events fetched on demand)
- Automatic cleanup when stream completes or is halted
- Thread struct must be updated with thread_id from `ThreadStarted` event

---

#### `run_auto/3`

Executes an auto-run loop, retrying turn execution while the Codex engine exposes a continuation token.

**Signature**:
```elixir
@spec run_auto(t(), String.t(), keyword()) ::
  {:ok, Codex.Turn.Result.t()} | {:error, term()}
```

**Parameters**:
- `thread`: Thread struct from `Codex.start_thread/2`
- `input`: Prompt or instruction for the agent
- `opts` (keyword):
  - `:max_attempts` (default: `3`) — maximum auto-run attempts
  - `:backoff` (default: exponential backoff) — unary function invoked before each retry
  - `:turn_opts` (default: `%{}`) — forwarded to each `run/3` attempt

**Returns**:
- `{:ok, result}`: Completed turn with aggregated events, usage, and `attempts` count
- `{:error, {:max_attempts_reached, max, context}}`: Continuation persisted after exhausting attempts
- `{:error, reason}`: Underlying execution failure

**Examples**:
```elixir
{:ok, thread} = Codex.start_thread()

# Automatically resolve continuation tokens until completion
{:ok, result} = Codex.Thread.run_auto(thread, "Generate release notes")

result.attempts
# => 2

result.thread.usage
# => %{"input_tokens" => 42, "output_tokens" => 35, ...}

# Custom retry policy (no sleep) with explicit max attempts
opts = [max_attempts: 5, backoff: fn _ -> :ok end]
case Codex.Thread.run_auto(thread, "Execute plan", opts) do
  {:ok, result} -> IO.inspect(result.final_response)
  {:error, {:max_attempts_reached, _, %{continuation: token}}} ->
    Logger.warn("manual follow-up required: #{token}")
end
```

**Behavior**:
- Invokes `run/3` sequentially while continuation tokens are present
- Applies backoff between attempts; default uses exponential sleep
- Aggregates usage metrics and events across attempts
- Returns updated thread with continuation token cleared on success

---

## Codex.Exec

GenServer that manages the `codex-rs` process lifecycle. This module is typically used internally by `Codex.Thread`, but can be used directly for advanced use cases.

---

## Codex.Tools

The tool registry keeps parity with Python's decorator-based tooling API. Tools can be registered dynamically and invoked automatically during auto-run cycles when the agent requests an external capability.

### `register/2`

Registers a tool module that implements `Codex.Tool`.

```elixir
@spec register(module(), keyword()) :: {:ok, Codex.Tools.Handle.t()} | {:error, term()}
```

- `:name` — identifier used by Codex events (defaults to module metadata or underscored module name)
- `:description`, `:schema` — optional metadata merged with tool-provided metadata

### `invoke/3`

Invokes a registered tool with decoded arguments and contextual data.

```elixir
@spec invoke(String.t(), map(), map()) :: {:ok, map()} | {:error, term()}
```

Context includes the current thread struct, event metadata, and any custom entries stored under `Thread.Options.metadata` (mirroring Python's tool context).

### `deregister/1`

Removes a registered tool. Typically used in tests or when dynamically unloading capabilities.

### `metrics/0`

Returns an in-memory snapshot of invocation counters per tool.

```elixir
@spec metrics() :: %{optional(String.t()) => %{success: non_neg_integer(), failure: non_neg_integer(), last_latency_ms: non_neg_integer(), total_latency_ms: non_neg_integer(), last_error: term() | nil}}
```

Useful for integration tests or lightweight observability without relying on external telemetry backends.

### `reset_metrics/0`

Clears all accumulated metrics.

```elixir
@spec reset_metrics() :: :ok
```

Intended primarily for test setup/teardown routines.

### Telemetry

Every invocation emits `:telemetry` events using the following namespaces:

- `[:codex, :tool, :start]` — dispatched prior to executing a tool, with metadata including `:tool`, `:call_id`, `:attempt`, and `:retry?`
- `[:codex, :tool, :success]` — emitted on success with the same metadata plus the returned `:output`; measurements include `:duration` in native units
- `[:codex, :tool, :failure]` — emitted on failures with the same measurements and an `:error` entry describing the failure

---

## Codex.Files

Staging and attachment helpers that keep file workflows deterministic.

- `stage/2` — copies a source file into the staging directory, returning `%Codex.Files.Attachment{}` with checksum, size, and persistence metadata.
- `attach/2` — appends a staged attachment to `Codex.Thread.Options`, deduplicating by checksum.
- `list_staged/0` / `cleanup!/0` / `reset!/0` — inspect and manage staged files during tests.

Attachments are forwarded to the codex executable via CLI flags (`--attachment`, `--attachment-name`, `--attachment-checksum`), making the workflow match Python's file pipeline.

---

## Codex.Approvals.StaticPolicy

Provides a lightweight approval policy used to gate tool invocations or sandbox-sensitive operations.

- `allow/1` — always approves (`StaticPolicy.allow(reason: "optional")`).
- `deny/1` — always denies with a custom reason, used in tests to emulate blocked flows.
- `review_tool/3` — invoked by `Codex.Thread.run_auto/3` to determine whether a requested tool may execute.

---

## Codex.MCP.Client

Thin client for performing capability handshake with MCP-compatible servers.

- `handshake/2` — sends a handshake request (`{"type": "handshake"}`) and records advertised capabilities.
- `capabilities/1` — returns the negotiated capability list used to seed the tool registry.

---

## Codex.Telemetry

Helper module for emitting telemetry and wiring default logging.

- `emit/3` — dispatches telemetry events (`:telemetry.execute`).
- `attach_default_logger/1` — logs thread start/stop/exception events with configurable log level.

## Error Types

- `Codex.TransportError` — returned when the codex executable exits non-zero. Includes `exit_status` and optional `stderr` snippet.
- `Codex.ApprovalError` — returned when an approval policy denies a tool invocation, exposing `tool` and `reason` fields.

### Functions

#### `start_link/1`

Starts an Exec GenServer and spawns the codex-rs process.

**Signature**:
```elixir
@spec start_link(keyword()) :: GenServer.on_start()
```

**Options**:
- `:input` (required): Input prompt for the turn
- `:codex_path` (optional): Path to codex binary
- `:thread_id` (optional): Existing thread ID to resume
- `:base_url` (optional): OpenAI API base URL
- `:api_key` (optional): OpenAI API key
- `:model` (optional): Model name
- `:sandbox_mode` (optional): Sandbox mode (`:read_only`, `:workspace_write`, `:danger_full_access`)
- `:working_directory` (optional): Working directory for agent
- `:skip_git_repo_check` (optional): Skip Git repository check
- `:output_schema_file` (optional): Path to JSON schema file

**Returns**:
- `{:ok, pid}`: GenServer process ID
- `{:error, reason}`: Spawn or configuration error

**Examples**:
```elixir
# Basic usage
{:ok, pid} = Codex.Exec.start_link(
  input: "Hello, Codex",
  codex_path: "/usr/local/bin/codex"
)

# With all options
{:ok, pid} = Codex.Exec.start_link(
  input: "Analyze code",
  codex_path: "/usr/local/bin/codex",
  thread_id: "thread_abc123",
  api_key: "sk-...",
  model: "o1",
  sandbox_mode: :read_only,
  working_directory: "/path/to/project",
  output_schema_file: "/tmp/schema.json"
)
```

---

#### `run_turn/2`

Starts turn execution and returns a reference for event tracking.

**Signature**:
```elixir
@spec run_turn(pid()) :: reference()
```

**Parameters**:
- `pid`: Exec GenServer process ID

**Returns**:
- `reference()`: Unique reference for this turn

**Usage**:
```elixir
{:ok, pid} = Codex.Exec.start_link(input: "test")
ref = Codex.Exec.run_turn(pid)

# Receive events
receive do
  {:event, ^ref, event} ->
    IO.inspect(event)
  {:done, ^ref} ->
    IO.puts("Turn complete")
  {:error, ^ref, error} ->
    IO.puts("Error: #{inspect(error)}")
end
```

---

## Codex.Events

Event type definitions for all events emitted during turn execution.

### Event Types

#### `ThreadStarted`

Emitted when a new thread is started.

**Type**:
```elixir
@type t() :: %Codex.Events.ThreadStarted{
  type: :thread_started,
  thread_id: String.t()
}
```

**Fields**:
- `type`: Always `:thread_started`
- `thread_id`: Unique identifier for the thread (format: `"thread_*"`)

**Example**:
```elixir
%Codex.Events.ThreadStarted{
  type: :thread_started,
  thread_id: "thread_abc123xyz"
}
```

---

#### `TurnStarted`

Emitted when a turn begins processing.

**Type**:
```elixir
@type t() :: %Codex.Events.TurnStarted{
  type: :turn_started
}
```

---

#### `TurnCompleted`

Emitted when a turn completes successfully.

**Type**:
```elixir
@type t() :: %Codex.Events.TurnCompleted{
  type: :turn_completed,
  usage: Codex.Events.Usage.t()
}
```

**Fields**:
- `type`: Always `:turn_completed`
- `usage`: Token usage statistics

**Usage Type**:
```elixir
@type usage() :: %Codex.Events.Usage{
  input_tokens: non_neg_integer(),
  cached_input_tokens: non_neg_integer(),
  output_tokens: non_neg_integer()
}
```

**Example**:
```elixir
%Codex.Events.TurnCompleted{
  type: :turn_completed,
  usage: %Codex.Events.Usage{
    input_tokens: 1500,
    cached_input_tokens: 500,
    output_tokens: 800
  }
}
```

---

#### `TurnFailed`

Emitted when a turn fails with an error.

**Type**:
```elixir
@type t() :: %Codex.Events.TurnFailed{
  type: :turn_failed,
  error: Codex.Events.ThreadError.t()
}
```

**Error Type**:
```elixir
@type thread_error() :: %Codex.Events.ThreadError{
  message: String.t()
}
```

---

#### `ItemStarted`

Emitted when a new item is added to the thread.

**Type**:
```elixir
@type t() :: %Codex.Events.ItemStarted{
  type: :item_started,
  item: Codex.Items.t()
}
```

---

#### `ItemUpdated`

Emitted when an item's state changes.

**Type**:
```elixir
@type t() :: %Codex.Events.ItemUpdated{
  type: :item_updated,
  item: Codex.Items.t()
}
```

---

#### `ItemCompleted`

Emitted when an item reaches a terminal state.

**Type**:
```elixir
@type t() :: %Codex.Events.ItemCompleted{
  type: :item_completed,
  item: Codex.Items.t()
}
```

---

## Codex.Items

Thread item type definitions representing different actions and artifacts.

### Item Types

#### `AgentMessage`

Text or JSON response from the agent.

**Type**:
```elixir
@type t() :: %Codex.Items.AgentMessage{
  id: String.t(),
  type: :agent_message,
  text: String.t(),
  parsed: map() | list() | nil
}
```

**Fields**:
- `id`: Unique item identifier
- `type`: Always `:agent_message`
- `text`: Response text (natural language or JSON when using output schema)
- `parsed`: Decoded payload when an output schema is supplied (otherwise `nil`)

**Example**:
```elixir
%Codex.Items.AgentMessage{
  id: "msg_abc123",
  type: :agent_message,
  text: "GenServers are process abstractions in Elixir...",
  parsed: nil
}
```

---

#### `Reasoning`

Agent's reasoning summary.

**Type**:
```elixir
@type t() :: %Codex.Items.Reasoning{
  id: String.t(),
  type: :reasoning,
  text: String.t()
}
```

**Example**:
```elixir
%Codex.Items.Reasoning{
  id: "reasoning_1",
  type: :reasoning,
  text: "To fix this issue, I need to first understand the error, then locate the relevant code..."
}
```

---

#### `CommandExecution`

Shell command executed by the agent.

**Type**:
```elixir
@type t() :: %Codex.Items.CommandExecution{
  id: String.t(),
  type: :command_execution,
  command: String.t(),
  aggregated_output: String.t(),
  exit_code: integer() | nil,
  status: :in_progress | :completed | :failed
}
```

**Fields**:
- `command`: Command line that was executed
- `aggregated_output`: Combined stdout and stderr
- `exit_code`: Exit status (nil while running, integer when complete)
- `status`: Current status of execution

**Example**:
```elixir
%Codex.Items.CommandExecution{
  id: "cmd_1",
  type: :command_execution,
  command: "mix test",
  aggregated_output: "...\n42 tests, 0 failures\n",
  exit_code: 0,
  status: :completed
}
```

---

#### `FileChange`

File modifications made by the agent.

**Type**:
```elixir
@type t() :: %Codex.Items.FileChange{
  id: String.t(),
  type: :file_change,
  changes: [file_update_change()],
  status: :completed | :failed
}
```

**Change Type**:
```elixir
@type file_update_change() :: %{
  path: String.t(),
  kind: :add | :delete | :update
}
```

**Example**:
```elixir
%Codex.Items.FileChange{
  id: "patch_1",
  type: :file_change,
  changes: [
    %{path: "lib/my_app.ex", kind: :update},
    %{path: "lib/new_module.ex", kind: :add}
  ],
  status: :completed
}
```

---

#### `McpToolCall`

Model Context Protocol tool invocation.

**Type**:
```elixir
@type t() :: %Codex.Items.McpToolCall{
  id: String.t(),
  type: :mcp_tool_call,
  server: String.t(),
  tool: String.t(),
  status: :in_progress | :completed | :failed
}
```

**Example**:
```elixir
%Codex.Items.McpToolCall{
  id: "mcp_1",
  type: :mcp_tool_call,
  server: "database_server",
  tool: "query_records",
  status: :completed
}
```

---

#### `WebSearch`

Web search query and results.

**Type**:
```elixir
@type t() :: %Codex.Items.WebSearch{
  id: String.t(),
  type: :web_search,
  query: String.t()
}
```

---

#### `TodoList`

Agent's running task list.

**Type**:
```elixir
@type t() :: %Codex.Items.TodoList{
  id: String.t(),
  type: :todo_list,
  items: [todo_item()]
}
```

**Todo Item Type**:
```elixir
@type todo_item() :: %{
  text: String.t(),
  completed: boolean()
}
```

**Example**:
```elixir
%Codex.Items.TodoList{
  id: "todo_1",
  type: :todo_list,
  items: [
    %{text: "Analyze codebase", completed: true},
    %{text: "Identify issues", completed: true},
    %{text: "Propose fixes", completed: false}
  ]
}
```

---

#### `Error`

Non-fatal error item.

**Type**:
```elixir
@type t() :: %Codex.Items.Error{
  id: String.t(),
  type: :error,
  message: String.t()
}
```

---

## Codex.Options

Configuration structs for different levels of the SDK.

### `Codex.Options`

Global Codex configuration.

**Type**:
```elixir
@type t() :: %Codex.Options{
  codex_path_override: String.t() | nil,
  base_url: String.t() | nil,
  api_key: String.t() | nil
}
```

**Fields**:
- `codex_path_override`: Custom path to codex binary (defaults to system PATH)
- `base_url`: OpenAI API base URL (defaults to official URL)
- `api_key`: OpenAI API key (overrides environment variable)

**Example**:
```elixir
%Codex.Options{
  codex_path_override: "/custom/path/to/codex",
  base_url: "https://api.openai.com",
  api_key: System.get_env("OPENAI_API_KEY")
}
```

---

### `Codex.Thread.Options`

Thread-specific configuration.

**Type**:
```elixir
@type t() :: %Codex.Thread.Options{
  model: String.t() | nil,
  sandbox_mode: sandbox_mode() | nil,
  working_directory: String.t() | nil,
  skip_git_repo_check: boolean()
}
```

**Sandbox Modes**:
- `:read_only`: Agent can read files but not modify them
- `:workspace_write`: Agent can write within working directory
- `:danger_full_access`: Agent has unrestricted filesystem access

**Fields**:
- `model`: Model name (e.g., "o1", "gpt-4")
- `sandbox_mode`: File access restrictions
- `working_directory`: Working directory for agent operations
- `skip_git_repo_check`: Skip Git repository check (default: false)

**Example**:
```elixir
%Codex.Thread.Options{
  model: "o1",
  sandbox_mode: :read_only,
  working_directory: "/home/user/project",
  skip_git_repo_check: false
}
```

---

### `Codex.Turn.Options`

Turn-specific configuration.

**Type**:
```elixir
@type t() :: %Codex.Turn.Options{
  output_schema: map() | nil
}
```

**Fields**:
- `output_schema`: JSON schema for structured output (nil for natural language)

**Example**:
```elixir
%Codex.Turn.Options{
  output_schema: %{
    "type" => "object",
    "properties" => %{
      "summary" => %{"type" => "string"},
      "status" => %{"type" => "string", "enum" => ["ok", "error"]}
    },
    "required" => ["summary", "status"]
  }
}
```

---

## Codex.OutputSchemaFile

Utility for managing JSON schema temporary files.

### Functions

#### `create/1`

Creates a temporary file with the JSON schema.

**Signature**:
```elixir
@spec create(map() | nil) :: {:ok, {String.t() | nil, function()}} | {:error, term()}
```

**Parameters**:
- `schema`: JSON schema map or nil

**Returns**:
- `{:ok, {path, cleanup}}`: Path to temp file and cleanup function
- `{:error, reason}`: Error creating file

**Examples**:
```elixir
# With schema
schema = %{"type" => "object", "properties" => %{}}
{:ok, {path, cleanup}} = Codex.OutputSchemaFile.create(schema)

# Use path...

# Clean up
cleanup.()

# Without schema
{:ok, {nil, cleanup}} = Codex.OutputSchemaFile.create(nil)
cleanup.()  # No-op
```

**Notes**:
- Creates temp directory in system tmp folder
- Writes JSON to `schema.json` in that directory
- Cleanup function removes entire directory
- Cleanup is idempotent (safe to call multiple times)
- Used internally by `Codex.Thread`

---

## Type Aliases

### `Codex.Turn.Result`

Result of a completed turn (from `run/3`).

**Type**:
```elixir
@type t() :: %Codex.Turn.Result{
  thread: Codex.Thread.t(),
  events: [Codex.Events.t()],
  final_response: Codex.Items.AgentMessage.t() | map() | nil,
  usage: map() | nil,
  raw: map(),
  attempts: non_neg_integer()
}
```

**Fields**:
- `thread`: Updated thread struct containing continuation & metadata
- `events`: Events emitted during the turn
- `final_response`: Last agent message (typed struct with optional `parsed` payload)
- `usage`: Token usage statistics (nil if turn failed before completion)
- `raw`: Underlying exec metadata (`events`, CLI flags, etc.)
- `attempts`: Number of attempts performed (useful for auto-run)

**Helpers**:

- `Codex.Turn.Result.json/1` — returns `{:ok, map()}` when structured output was decoded, or an error tuple (`{:error, :not_structured}` / `{:error, {:invalid_json, reason}}`).

---

## Common Patterns

### Error Handling

```elixir
case Codex.Thread.run(thread, input) do
  {:ok, result} ->
    process_result(result)

  {:error, {:turn_failed, error}} ->
    Logger.error("Turn failed: #{error.message}")
    {:error, :turn_failed}

  {:error, {:process, reason}} ->
    Logger.error("Process error: #{inspect(reason)}")
    {:error, :process_error}

  {:error, reason} ->
    Logger.error("Unknown error: #{inspect(reason)}")
    {:error, :unknown}
end
```

### Streaming with Pattern Matching

```elixir
{:ok, stream} = Codex.Thread.run_streamed(thread, input)

Enum.reduce(stream, %{commands: [], files: []}, fn
  %ItemCompleted{item: %{type: :command_execution} = cmd}, acc ->
    %{acc | commands: [cmd | acc.commands]}

  %ItemCompleted{item: %{type: :file_change} = file}, acc ->
    %{acc | files: [file | acc.files]}

  _, acc ->
    acc
end)
```

### Structured Output with Validation

```elixir
schema = %{
  "type" => "object",
  "properties" => %{
    "status" => %{"type" => "string", "enum" => ["success", "failure"]},
    "data" => %{"type" => "object"}
  },
  "required" => ["status"]
}

turn_opts = %Codex.Turn.Options{output_schema: schema}
{:ok, result} = Codex.Thread.run(thread, "Check system status", turn_opts)

case Jason.decode(result.final_response) do
  {:ok, %{"status" => "success", "data" => data}} ->
    process_data(data)

  {:ok, %{"status" => "failure"}} ->
    handle_failure()

  {:error, _} ->
    {:error, :invalid_json}
end
```

---

## Migration from TypeScript SDK

For developers familiar with the TypeScript SDK:

| TypeScript | Elixir |
|------------|--------|
| `new Codex()` | `Codex` module (no instance needed) |
| `codex.startThread()` | `Codex.start_thread()` |
| `codex.resumeThread(id)` | `Codex.resume_thread(id)` |
| `await thread.run(input)` | `Codex.Thread.run(thread, input)` |
| `await thread.runStreamed(input)` | `Codex.Thread.run_streamed(thread, input)` |
| `for await (const event of events)` | `Enum.each(stream, fn event -> ... end)` |
| `CodexOptions` | `%Codex.Options{}` |
| `ThreadOptions` | `%Codex.Thread.Options{}` |
| `TurnOptions` | `%Codex.Turn.Options{}` |

---

## See Also

- [Architecture Guide](02-architecture.md)
- [Implementation Plan](03-implementation-plan.md)
- [Testing Strategy](04-testing-strategy.md)
- [Examples](06-examples.md)

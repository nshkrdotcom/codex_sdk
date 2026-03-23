# Architecture Guide

## System Overview

The Elixir Codex SDK is a layered architecture that wraps the `codex-rs` CLI executable and provides an idiomatic OTP-based interface. The system is designed around three core principles:

1. **Process Isolation**: Each turn execution runs in its own GenServer
2. **Clean Separation**: Clear boundaries between client API, process management, and IPC
3. **Robust Error Handling**: Failures are isolated and cleanly propagated

Separate from thread/turn execution, the SDK also exposes a thin command-surface
passthrough layer (`Codex.CLI` and `Codex.CLI.Session`) for CLI-only workflows
such as `codex completion`, `codex cloud`, `codex features`, `codex mcp-server`,
and the root interactive client. One-shot non-PTY passthrough goes through the
shared `CliSubprocessCore.Command` lane, while `Codex.CLI.Session` preserves the
historical mailbox-facing session API on top of `CliSubprocessCore.RawSession`.

## Transports

`codex_sdk` supports two upstream external transports:

- **Exec JSONL (default)**: spawns `codex exec --json` and parses JSONL events
- **App-server JSON-RPC (optional)**: maintains a stateful `codex app-server` subprocess and speaks newline-delimited JSON-RPC over stdio

The app-server path is the parity transport for upstream v2 features such as `fs/*`, `plugin/read`,
`thread/shellCommand`, structured `item/permissions/requestApproval` responses,
`mcpServer/startupStatus/updated`, guardian review notifications, and `serverRequest/resolved`.

Transport selection is per-thread via `Codex.Thread.Options.transport`:

```elixir
{:ok, conn} = Codex.AppServer.connect(codex_opts)
{:ok, thread_opts} = Codex.Thread.Options.new(%{transport: {:app_server, conn}})
```

`Codex.AppServer.connect/2` can also isolate the managed child with `cwd:` and
`process_env:` launch overrides when you need a temporary `CODEX_HOME`.

Native OAuth is a separate subsystem centered on `Codex.OAuth`. Persistent
OAuth writes upstream-compatible `auth.json` under the effective `CODEX_HOME`.
Memory-mode OAuth is used for external app-server auth: `connect/2` performs
`account/login/start` with `chatgptAuthTokens` and, when enabled, starts a
connection-owned refresh responder for `account/chatgptAuthTokens/refresh`
without pushing that ownership into the lower-level app-server transport layer.

Across both transports, TLS configuration is centralized in `Codex.Net.CA`: subprocess
environment injection, Req clients, `:httpc`, and realtime websocket SSL options all resolve
`CODEX_CA_CERTIFICATE` first, then `SSL_CERT_FILE`.

## Runtime Ownership Boundary

Shared core ownership:

- `Codex.Exec` on `CliSubprocessCore.Session`
- `Codex.CLI.run/2` and the synchronous CLI wrappers on `CliSubprocessCore.Command`
- `Codex.CLI.Session` on `CliSubprocessCore.RawSession`
- the subprocess lifecycle behind `Codex.AppServer.connect/2` and
  `Codex.MCP.Transport.Stdio` on `CliSubprocessCore.Transport`
- one-shot hosted shell execution and `Codex.Sessions.apply/2` on the shared command lane

Intentional SDK-local ownership above the core:

- `Codex.CLI.Session` as the public Codex session API for PTY and long-lived CLI sessions
- the app-server connection process used by `Codex.AppServer.connect/2` for the provider-native `codex app-server` control protocol
- the MCP stdio transport used by `codex mcp-server`
- realtime and voice clients, which call OpenAI APIs directly instead of using the CLI runtime

The publication boundary on that split is now:

- `cli_subprocess_core` owns every Codex subprocess-backed lifecycle and the
  only `erlexec` dependency in the stack
- `codex_sdk` remains the home of app-server, MCP, realtime, voice, and other
  Codex-native semantics
- optional ASM integration may exist only as an explicit bridge above the
  normalized kernel; it does not re-home these families or widen the core

## Component Architecture

### High-Level Component Diagram

```
┌───────────────────────────────────────────────────────────────┐
│                        Client Code                             │
│  (User application using Codex SDK)                           │
└────────────────┬──────────────────────────────────────────────┘
                 │
                 │ Public API
                 ▼
┌───────────────────────────────────────────────────────────────┐
│                      Codex Module                              │
│  - start_thread/2                                             │
│  - resume_thread/3                                            │
│  (Factory for Thread instances)                               │
└────────────────┬──────────────────────────────────────────────┘
                 │
                 │ Returns Thread struct or CLI session helpers
                 ▼
┌───────────────────────────────────────────────────────────────┐
│                   Codex.Thread Module                          │
│  - run/3 (blocking)                                           │
│  - run_streamed/3 (streaming)                                 │
│  (Manages turn execution lifecycle)                           │
└────────────────┬──────────────────────────────────────────────┘
                 │
                 │ Transport dispatch / raw CLI passthrough
                 ▼
┌───────────────────────────────────────────────────────────────┐
│                Codex.Transport (behaviour)                     │
│  - Exec JSONL: Codex.Exec                                     │
│  - App-server: Codex.AppServer.Connection                      │
│  - Raw CLI / PTY: Codex.CLI, Codex.CLI.Session                │
└────────────────┬──────────────────────────────────────────────┘
                 │
                 │ Port (stdin/stdout)
                 ▼
┌───────────────────────────────────────────────────────────────┐
│                      codex-rs Process                          │
│  - OpenAI API integration                                     │
│  - Command execution                                          │
│  - File operations                                            │
│  - Event emission                                             │
└───────────────────────────────────────────────────────────────┘
```

## Module Breakdown

### 1. Codex Module

**Purpose**: Main entry point and factory for thread instances.

**Responsibilities**:
- Validate global options (API key, base URL, codex path)
- Create new thread instances
- Resume existing threads from saved sessions

**State**: Stateless module (pure functions)

**Key Functions**:
```elixir
@spec start_thread(Codex.Options.t(), Codex.Thread.Options.t()) ::
  {:ok, Codex.Thread.t()} | {:error, term()}

@spec resume_thread(String.t(), Codex.Options.t(), Codex.Thread.Options.t()) ::
  {:ok, Codex.Thread.t()} | {:error, term()}
```

**Error Handling**:
- Validates codex binary exists and is executable
- Validates options format
- Returns descriptive errors for invalid configurations

---

### 2. Codex.Thread Module

**Purpose**: Manages individual conversation threads.

**Responsibilities**:
- Execute turns (blocking and streaming modes)
- Maintain thread ID and options
- Coordinate with the exec runtime kit
- Handle structured output schemas and rate limit snapshots

**State**: Encapsulated in `%Codex.Thread{}` struct (includes transport metadata)
```elixir
defstruct [
  :thread_id,          # String.t() | nil (populated after first turn)
  :codex_opts,         # %Codex.Options{}
  :thread_opts,        # %Codex.Thread.Options{}
  :rate_limits,        # latest rate limit snapshot (if provided)
  :transport           # :exec | {:app_server, pid()}
]
```

**Key Functions**:
```elixir
@spec run(t(), String.t() | [map()], Codex.Turn.Options.t()) ::
  {:ok, Codex.Turn.Result.t()} | {:error, term()}

@spec run_streamed(t(), String.t() | [map()], Codex.Turn.Options.t()) ::
  {:ok, Enumerable.t()} | {:error, term()}
```

App-server transport accepts `UserInput` block lists (`text`/`image`/`localImage`/`skill`/`mention`); exec JSONL accepts prompt strings plus the SDK's normalized JSONL user-input variants (`text`/`image`/`local_image`/`skill`/`mention`).

**Execution Flow** (Blocking Mode):
1. Create output schema file if needed
2. Start `Codex.Exec`, which boots `Codex.Runtime.Exec` on `CliSubprocessCore.Session`
3. Project core session events into `%Codex.Events{}` values and accumulate items
4. Extract final response from last `AgentMessage`
5. Return `TurnResult` when the core-backed session completes
6. Clean up schema file and the ephemeral session process

**Execution Flow** (Streaming Mode):
1. Create output schema file if needed
2. Start `Codex.Exec`, which boots `Codex.Runtime.Exec` on `CliSubprocessCore.Session`
3. Return Stream that yields projected `%Codex.Events{}` values as they arrive
4. Clean up when the underlying session completes or the stream is halted

---

### 3. Codex.Exec And Runtime Kit

**Purpose**: Preserve the public exec JSONL API while delegating common CLI
process ownership and parsing to `cli_subprocess_core`.

**Responsibilities**:
- Translate SDK thread/turn options into the common CLI session invocation
- Start a `CliSubprocessCore.Session` through `Codex.Runtime.Exec`
- Project core runtime events back into typed `%Codex.Events{}` structs
- Track stderr tails, timeouts, cancellation tokens, and non-zero exits
- Clean up the ephemeral session process on completion or crash

**State**:
```elixir
defstruct [
  :session,            # pid() for CliSubprocessCore.Session
  :session_ref,        # reference() for subscriber mailbox routing
  :projection_state,   # runtime-kit projection state
  :stderr,             # bounded stderr tail
  :timeout_ms,         # blocking idle timeout
  :idle_timeout_ms     # streaming idle timeout
]
```

**Lifecycle**:

1. Build session options and start `Codex.Runtime.Exec`
2. Subscribe to `CliSubprocessCore.Session` events with a tagged mailbox ref
3. Project core events into `%Codex.Events{}` values as they arrive
4. Convert terminal core exit events into `Codex.TransportError` when needed
5. Stop the session and flush any remaining tagged mailbox messages

**Error Scenarios**:
- **Spawn failure**: Return error immediately
- **Parse failure**: Log and continue; the core remains the only JSONL parser
- **Non-zero exit**: Surface `Codex.TransportError` with bounded stderr
- **Unexpected session shutdown**: Treat as an exec transport failure

---

### 4. Type Modules

#### Codex.Events

Defines all event types emitted during turn execution.

**TypedStruct Definitions**:
```elixir
defmodule Codex.Events.ThreadStarted do
  use TypedStruct
  typedstruct do
    field :type, :thread_started, enforce: true
    field :thread_id, String.t(), enforce: true
  end
end

# Similar for:
# - TurnStarted
# - TurnCompleted (with Usage)
# - TurnFailed (with ThreadError)
# - ItemStarted (with ThreadItem)
# - ItemUpdated (with ThreadItem)
# - ItemCompleted (with ThreadItem)
```

#### Codex.Items

Defines all item types and their variants.

**Item Types**:
- `AgentMessage`: Text or JSON response
- `Reasoning`: Agent's thinking summary
- `CommandExecution`: Command with output and exit code
- `FileChange`: File modifications with changes array
- `McpToolCall`: MCP tool invocation
- `WebSearch`: Search query
- `TodoList`: Agent's task list
- `Error`: Non-fatal error

**Example**:
```elixir
defmodule Codex.Items.CommandExecution do
  use TypedStruct
  typedstruct do
    field :id, String.t(), enforce: true
    field :type, :command_execution, default: :command_execution
    field :command, String.t(), enforce: true
    field :aggregated_output, String.t(), default: ""
    field :exit_code, integer()
    field :status, atom(), enforce: true
  end
end
```

#### Codex.Options

Configuration structs for each level.

```elixir
defmodule Codex.Options do
  use TypedStruct
  typedstruct do
    field :codex_path_override, String.t()
    field :base_url, String.t()
    field :api_key, String.t()
  end
end

defmodule Codex.Thread.Options do
  use TypedStruct
  typedstruct do
    field :model, String.t()
    field :sandbox_mode, atom()  # :read_only | :workspace_write | :danger_full_access
    field :working_directory, String.t()
    field :skip_git_repo_check, boolean(), default: false
  end
end

defmodule Codex.Turn.Options do
  use TypedStruct
  typedstruct do
    field :output_schema, map()
  end
end
```

---

### 5. Utility Modules

#### Codex.OutputSchemaFile

Manages temporary JSON schema files.

**Functions**:
```elixir
@spec create(map() | nil) :: {:ok, {String.t() | nil, function()}} | {:error, term()}
```

**Implementation**:
- Creates temp directory in system tmp
- Writes schema JSON to file
- Returns path and cleanup function
- Cleanup function removes directory recursively
- Handles nil schema (no file created)

## Data Flow Diagrams

### Blocking Turn Execution

```
Client                  Thread              Exec Runtime         Core Session
  |                       |                       |                     |
  |-- run(input) -------->|                       |                     |
  |                       |-- run_turn ---------->|                     |
  |                       |                       |-- start ----------->|
  |                       |                       |                     |-- codex-rs starts
  |                       |                       |<------ event -------|
  |                       |<------- event --------|                     |
  |                       |                       |<------ event -------|
  |                       |<------- event --------|                     |
  |                       |                       |                     |-- codex-rs exits
  |                       |                       |<------ exit --------|
  |<-- {:ok, result} -----|                       |                     |
```

### Streaming Turn Execution

```
Client                  Thread              Exec Runtime         Core Session
  |                       |                       |                     |
  |-- run_streamed() ---->|                       |                     |
  |                       |-- run_turn ---------->|                     |
  |                       |                       |-- start ----------->|
  |<-- {:ok, stream} -----|                       |                     |
  |                       |                       |                     |-- codex-rs starts
  |                       |                       |                     |
  |-- next event -------->|-- fetch event ------->|                     |
  |<-- ItemStarted -------|<----------------------|<------ event -------|
  |                       |                       |                     |
  |-- next event -------->|-- fetch event ------->|                     |
  |<-- ItemCompleted -----|<----------------------|<------ event -------|
  |                       |                       |                     |
  |-- next event -------->|-- fetch event ------->|                     |
  |<-- TurnCompleted -----|<----------------------|<------ event -------|
  |                       |                       |                     |-- codex-rs exits
  |                       |                       |<------ exit --------|
  |-- stream done ------->|                       |                     |
```

## Process Model

### Process Hierarchy

```
Application Supervisor
    │
    └─── Client Process (caller)
            │
            └─── CliSubprocessCore.Session (per turn)
                    │
                    └─── CliSubprocessCore.Transport
                            │
                            └─── codex-rs
```

**Key Points**:
- The core session process is ephemeral (one per turn)
- No persistent supervision tree needed
- Client monitors the session process through `Codex.Exec`
- `Codex.Runtime.Exec` preserves the public event surface by projection
- Clean shutdown cascades down hierarchy

### Message Passing

**Client → Thread** (synchronous):
```elixir
{:run, input, options}
{:run_streamed, input, options}
```

**Thread → Exec** (GenServer call):
```elixir
{:run_turn, input, codex_args}
```

**Port → Exec** (Port messages):
```elixir
{port, {:data, binary}}
{port, {:exit_status, integer}}
{:EXIT, port, reason}
```

**Exec → Client** (via reference):
```elixir
{:event, ref, event_struct}
{:error, ref, error_term}
{:done, ref}
```

## Error Handling Strategy

### Error Categories

1. **Configuration Errors** (fail fast)
   - Invalid options
   - Missing codex binary
   - Bad API credentials
   - Return: `{:error, {:config, reason}}`

2. **Process Errors** (recoverable)
   - Spawn failure
   - Port crash
   - Return: `{:error, {:process, reason}}`

3. **Communication Errors** (retryable)
   - JSON parse error
   - Protocol mismatch
   - Return: `{:error, {:communication, reason}}`

4. **Turn Errors** (expected)
   - Agent failure
   - API rate limit
   - Model error
   - Return: `{:error, {:turn_failed, error_struct}}`

### Error Propagation

```
codex-rs exit code ≠ 0
    ↓
CliSubprocessCore.Session emits terminal error event
    ↓
Codex.Runtime.Exec captures stderr + exit details
    ↓
Codex.Exec returns/raises Codex.TransportError
    ↓
Thread receives error
    ↓
Client gets {:error, {:turn_failed, details}}
```

### Cleanup Guarantees

All cleanup happens when the ephemeral session process stops:
- Close the core session
- Let the shared transport close the subprocess
- Remove temporary schema file
- Send telemetry event

Cleanup is guaranteed even on:
- Normal completion
- Client crash
- Runtime/session crash
- VM shutdown

## Streaming Implementation

### Stream Creation

```elixir
def run_streamed(thread, input, opts) do
  {schema_path, cleanup_fn} = OutputSchemaFile.create(opts.output_schema)

  stream = Stream.resource(
    fn ->
      {:ok, stream} = Codex.Exec.run_stream(input, ...)
      {stream, cleanup_fn}
    end,

    fn {stream, cleanup_fn} = acc ->
      next_stream_chunk_from_runtime(stream, acc)
    end,

    fn {_stream, cleanup_fn} ->
      cleanup_fn.()
    end
  )

  {:ok, stream}
end
```

**Key Properties**:
- Lazy evaluation (events fetched on demand)
- Backpressure support (caller controls rate)
- Automatic cleanup (even if stream halted early)
- Timeout protection via the exec runtime kit

### Event Buffering

**In `CliSubprocessCore.Session`**:
- Shared parser + transport sequencing
- Tagged subscriber delivery into `Codex.Exec`

**In Thread/Client**:
- No buffering (events consumed immediately)
- Client controls pace via Stream consumption

## Performance Considerations

### Memory

**Per Turn Overhead**:
- GenServer state: ~1 KB
- Event buffers: ~10 KB
- Port buffers: ~4 KB
- Total: ~15 KB per concurrent turn

**Streaming Benefits**:
- Constant memory (O(1) per turn)
- Events processed and discarded
- No accumulation of full turn history

### Latency

**Event Propagation**:
- codex-rs → stdout: < 1 ms
- Port → Exec: < 1 ms
- Exec → Client: < 1 ms
- Total: < 5 ms end-to-end

**Optimization Opportunities**:
- Batch small events
- Binary protocol (vs JSON)
- NIF for JSON parsing

### Throughput

**Bottlenecks**:
1. OpenAI API rate limits (primary)
2. JSON parsing (secondary)
3. Process scheduling (minimal)

**Scalability**:
- 100s of concurrent turns easily
- 1000s possible with tuning
- Limited by API, not SDK

## Telemetry Integration

### Events

```elixir
[:codex, :turn, :start]
  Measurements: %{system_time: integer()}
  Metadata: %{thread_id: string(), input_length: integer()}

[:codex, :turn, :stop]
  Measurements: %{duration: integer()}
  Metadata: %{thread_id: string(), usage: Usage.t()}

[:codex, :turn, :exception]
  Measurements: %{duration: integer()}
  Metadata: %{thread_id: string(), error: term()}

[:codex, :item, :completed]
  Measurements: %{system_time: integer()}
  Metadata: %{thread_id: string(), item_type: atom(), item_id: string()}
```

### Usage

```elixir
:telemetry.attach_many(
  "codex-handler",
  [
    [:codex, :turn, :start],
    [:codex, :turn, :stop],
    [:codex, :turn, :exception]
  ],
  &MyApp.TelemetryHandler.handle_event/4,
  nil
)
```

## Security Considerations

### Sandbox Modes

- `:read_only`: Codex can read files but not write
- `:workspace_write`: Codex can write within working directory
- `:danger_full_access`: Codex has unrestricted access

**Recommendations**:
- Use `:read_only` for analysis tasks
- Use `:workspace_write` for development
- Avoid `:danger_full_access` unless necessary

### Input Validation

- Sanitize file paths
- Validate schema JSON
- Escape shell arguments (handled by codex-rs)

### Secrets Management

- Never log API keys
- Use environment variables
- Rotate keys regularly
- Use per-project API keys

## Extension Points

### Custom Event Handlers

```elixir
defmodule MyApp.CodexHandler do
  def handle_event(%ItemCompleted{item: %CommandExecution{} = cmd}) do
    Logger.info("Command: #{cmd.command}, exit: #{cmd.exit_code}")
  end

  def handle_event(_), do: :ok
end

# Use with streaming
{:ok, stream} = Thread.run_streamed(thread, input)
Enum.each(stream, &MyApp.CodexHandler.handle_event/1)
```

### Custom Telemetry

```elixir
defmodule MyApp.Metrics do
  def track_usage(%Usage{} = usage) do
    :telemetry.execute(
      [:my_app, :codex, :tokens],
      %{total: usage.input_tokens + usage.output_tokens},
      %{source: :codex}
    )
  end
end
```

### Supervision

```elixir
defmodule MyApp.CodexSupervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      {Task.Supervisor, name: MyApp.CodexTaskSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

# Use supervised tasks for concurrent turns
Task.Supervisor.async(MyApp.CodexTaskSupervisor, fn ->
  Thread.run(thread, input)
end)
```

## Shared Runtime Modules

Extracted from duplicated patterns across the codebase, these modules centralize cross-cutting concerns:

- **`Codex.IO.Transport.Erlexec`**: Codex-branded transport surface backed by `CliSubprocessCore.Transport`; preserves the historical Codex event contract for app-server and MCP while leaving subprocess ownership in the core
- **`Codex.Runtime.Env`**: Subprocess environment construction shared between Exec and AppServer.Connection; sets `CODEX_INTERNAL_ORIGINATOR_OVERRIDE=codex_sdk_elixir` by default
- **`Codex.Runtime.KeyringWarning`**: Deduplicated warn-once logic from Auth and MCP.OAuth
- **`Codex.Config.BaseURL`**: `OPENAI_BASE_URL` env fallback with explicit option precedence (option → env → default)
- **`Codex.Config.OptionNormalizers`**: Shared validation for reasoning summary, verbosity, and history persistence across Options and Thread.Options
- **`Codex.Config.Overrides`**: Config override serialization, nested map auto-flattening (`flatten_config_map/1`), TOML value validation, and deduplicated `normalize_config_overrides/1`

## Realtime and Voice Modules

The SDK includes two subsystems for voice interactions that make **direct API calls** to OpenAI rather than wrapping the `codex` CLI.

### Realtime API (`Codex.Realtime.*`)

Full integration with OpenAI's Realtime API for bidirectional voice streaming:

- `Codex.Realtime.Session`: WebSocket-based GenServer using WebSockex; traps linked socket exits and runs tool calls outside the callback path so the session stays responsive
- `Codex.Realtime.Runner`: High-level orchestrator for agent sessions with automatic tool call handling, handoff execution, and guardrail integration
- `Codex.Realtime.Agent`: Agent configuration with instructions, tools, and handoffs
- PubSub-based event broadcasting with idempotent subscribe/unsubscribe
- Semantic VAD turn detection with eagerness, silence duration, and prefix padding

### Voice Pipeline (`Codex.Voice.*`)

Non-realtime STT -> Workflow -> TTS processing:

- `Codex.Voice.Pipeline`: Orchestrates speech-to-text, workflow processing, and text-to-speech with `async_nolink` via ephemeral `TaskSupervisor`
- `Codex.Voice.Workflow`: Behaviour for custom workflow implementations (`SimpleWorkflow`, `AgentWorkflow`)
- `Codex.Voice.Model.*`: Behaviours and implementations for STT/TTS models (OpenAI `gpt-4o-transcribe` and `gpt-4o-mini-tts`)
- `StreamQueue`-backed audio queues replacing Agent-backed queues for backpressure and close semantics

Auth precedence for both: `CODEX_API_KEY` → `auth.json OPENAI_API_KEY` → `OPENAI_API_KEY`.

## Future Enhancements

### Potential Improvements

1. **Native JSON Parsing**: NIF for faster event parsing
2. **Binary Protocol**: Reduce overhead vs JSONL
3. **WebSocket Streaming**: Alternative to Port for long-running sessions
4. **Event Persistence**: Store events for replay/debugging
5. **Distributed Turns**: Run turns on remote nodes
6. **Rate Limiting**: Built-in API rate limiting
7. **Caching**: Cache common responses
8. **Metrics Dashboard**: Real-time monitoring UI

### API Stability

**Stable** (v1.0+):
- Core module interfaces
- Event/item struct shapes
- Option struct fields

**Unstable** (may change):
- Telemetry event names
- Internal GenServer implementation
- Error tuple formats

**Experimental**:
- Custom event handlers
- Advanced streaming modes
- Performance optimizations

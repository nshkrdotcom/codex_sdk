# Architecture Guide

## System Overview

The Elixir Codex SDK is a layered architecture that wraps the `codex-rs` CLI executable and provides an idiomatic OTP-based interface. The system is designed around three core principles:

1. **Process Isolation**: Each turn execution runs in its own GenServer
2. **Clean Separation**: Clear boundaries between client API, process management, and IPC
3. **Robust Error Handling**: Failures are isolated and cleanly propagated

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
                 │ Returns Thread struct
                 ▼
┌───────────────────────────────────────────────────────────────┐
│                   Codex.Thread Module                          │
│  - run/3 (blocking)                                           │
│  - run_streamed/3 (streaming)                                 │
│  (Manages turn execution lifecycle)                           │
└────────────────┬──────────────────────────────────────────────┘
                 │
                 │ Starts GenServer
                 ▼
┌───────────────────────────────────────────────────────────────┐
│                   Codex.Exec GenServer                         │
│  - Spawns codex-rs process                                    │
│  - Manages Port communication                                 │
│  - Parses JSONL events                                        │
│  - Handles process lifecycle                                  │
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
- Coordinate with Exec GenServer
- Handle structured output schemas

**State**: Encapsulated in `%Codex.Thread{}` struct
```elixir
defstruct [
  :thread_id,          # String.t() | nil (populated after first turn)
  :codex_opts,         # %Codex.Options{}
  :thread_opts         # %Codex.Thread.Options{}
]
```

**Key Functions**:
```elixir
@spec run(t(), String.t(), Codex.Turn.Options.t()) ::
  {:ok, Codex.Turn.Result.t()} | {:error, term()}

@spec run_streamed(t(), String.t(), Codex.Turn.Options.t()) ::
  {:ok, Enumerable.t()} | {:error, term()}
```

**Execution Flow** (Blocking Mode):
1. Create output schema file if needed
2. Start `Codex.Exec` GenServer with options
3. Wait for events, accumulating items
4. Extract final response from last `AgentMessage`
5. Return `TurnResult` when `TurnCompleted` received
6. Clean up schema file and Exec process

**Execution Flow** (Streaming Mode):
1. Create output schema file if needed
2. Start `Codex.Exec` GenServer with options
3. Return Stream that yields events as they arrive
4. Clean up when stream completes or is halted

---

### 3. Codex.Exec GenServer

**Purpose**: Manages the lifecycle of a single `codex-rs` process execution.

**Responsibilities**:
- Spawn codex-rs process via Port
- Send input prompt via stdin
- Receive and parse JSONL events from stdout
- Monitor process health and exit status
- Clean up resources on completion or crash

**State**:
```elixir
defstruct [
  :port,               # Port.t()
  :caller,             # pid() of requesting process
  :ref,                # reference() for synchronization
  :buffer,             # String.t() for incomplete lines
  :exit_status,        # integer() | nil
  :stderr_buffer       # String.t() for error messages
]
```

**Lifecycle**:

1. **init/1**:
   - Build command args from options
   - Set environment variables
   - Spawn Port with codex-rs process
   - Send telemetry event (turn started)

2. **Message Handling**:
   - `{port, {:data, data}}`: Parse JSONL lines, send events to caller
   - `{port, {:exit_status, status}}`: Handle process exit
   - `{:EXIT, port, reason}`: Handle unexpected crashes

3. **terminate/2**:
   - Close port if still open
   - Send telemetry event (turn completed/failed)
   - Clean up any remaining resources

**Error Scenarios**:
- **Spawn failure**: Return error immediately
- **JSON parse error**: Emit error event, continue processing
- **Non-zero exit**: Emit `TurnFailed` with stderr contents
- **Process crash**: Emit `TurnFailed` with crash reason

**GenServer API**:
```elixir
@spec start_link(keyword()) :: GenServer.on_start()
@spec run_turn(pid(), String.t(), map()) :: {:ok, reference()}
```

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
Client                  Thread              Exec GenServer         Port/Process
  |                       |                       |                     |
  |-- run(input) -------->|                       |                     |
  |                       |-- start_link() ------>|                     |
  |                       |                       |-- spawn() --------->|
  |                       |                       |                     |-- codex-rs starts
  |                       |-- call: run_turn ---->|                     |
  |                       |                       |-- write stdin ----->|
  |                       |                       |                     |
  |                       |<------- event --------|<-- stdout line -----|
  |                       |<------- event --------|<-- stdout line -----|
  |                       |<------- event --------|<-- stdout line -----|
  |                       |                       |                     |
  |                       |<-- TurnCompleted -----|<-- stdout line -----|
  |                       |                       |                     |-- codex-rs exits
  |                       |                       |<-- exit_status -----|
  |                       |-- stop() ------------>|                     |
  |                       |                       |-- cleanup --------->|
  |<-- {:ok, result} -----|                       |                     |
```

### Streaming Turn Execution

```
Client                  Thread              Exec GenServer         Port/Process
  |                       |                       |                     |
  |-- run_streamed() ---->|                       |                     |
  |                       |-- start_link() ------>|                     |
  |                       |                       |-- spawn() --------->|
  |<-- {:ok, stream} -----|                       |                     |
  |                       |                       |                     |-- codex-rs starts
  |                       |-- call: run_turn ---->|                     |
  |                       |                       |-- write stdin ----->|
  |                       |                       |                     |
  |-- next event -------->|-- fetch event ------->|                     |
  |<-- ItemStarted -------|<----------------------|<-- stdout line -----|
  |                       |                       |                     |
  |-- next event -------->|-- fetch event ------->|                     |
  |<-- ItemCompleted -----|<----------------------|<-- stdout line -----|
  |                       |                       |                     |
  |-- next event -------->|-- fetch event ------->|                     |
  |<-- TurnCompleted -----|<----------------------|<-- stdout line -----|
  |                       |                       |                     |-- codex-rs exits
  |-- stream done ------->|-- stop() ------------>|                     |
  |                       |                       |-- cleanup --------->|
```

## Process Model

### Process Hierarchy

```
Application Supervisor
    │
    └─── Client Process (caller)
            │
            └─── Codex.Exec GenServer (per turn)
                    │
                    └─── Port (OS process)
                            │
                            └─── codex-rs
```

**Key Points**:
- Exec GenServer is ephemeral (one per turn)
- No persistent supervision tree needed
- Client monitors Exec GenServer
- Exec GenServer monitors Port
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
Port sends {:exit_status, code}
    ↓
Exec GenServer receives exit
    ↓
Exec parses stderr buffer
    ↓
Exec sends {:error, ref, {:turn_failed, details}}
    ↓
Thread receives error
    ↓
Client gets {:error, {:turn_failed, details}}
```

### Cleanup Guarantees

All cleanup happens in GenServer `terminate/2`:
- Close Port
- Kill OS process if still running
- Remove temporary schema file
- Send telemetry event

Cleanup is guaranteed even on:
- Normal completion
- Client crash
- GenServer crash
- VM shutdown

## Streaming Implementation

### Stream Creation

```elixir
def run_streamed(thread, input, opts) do
  {schema_path, cleanup_fn} = OutputSchemaFile.create(opts.output_schema)

  stream = Stream.resource(
    # Start function
    fn ->
      {:ok, pid} = Exec.start_link(...)
      ref = Exec.run_turn(pid, input, ...)
      {pid, ref, cleanup_fn}
    end,

    # Next function
    fn {pid, ref, cleanup_fn} = acc ->
      receive do
        {:event, ^ref, event} -> {[event], acc}
        {:done, ^ref} -> {:halt, acc}
        {:error, ^ref, error} -> raise error
      after
        30_000 -> raise TimeoutError
      end
    end,

    # After function
    fn {pid, _ref, cleanup_fn} ->
      GenServer.stop(pid)
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
- Timeout protection (30s default)

### Event Buffering

**In Exec GenServer**:
- Small buffer (100 events) to handle bursts
- Blocks Port reading if buffer full (backpressure)
- Flush buffer on process exit

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

## Testing Strategy

### Unit Tests

**Codex Module**:
- Option validation
- Thread creation
- Error cases

**Thread Module**:
- Turn execution (mocked Exec)
- Option passing
- Schema handling

**Exec GenServer**:
- Process spawning
- Event parsing
- Error handling
- Cleanup

### Integration Tests

**With Mock codex-rs**:
- Script that emits test events
- No real API calls
- Fast and deterministic

**With Real codex-rs**:
- Tagged `:integration`
- Requires API key
- Slow but comprehensive

### Property Tests

**Event Parsing**:
- Generate random valid events
- Verify round-trip JSON encoding
- Ensure no crashes

**Stream Properties**:
- Events in order
- No duplicates
- Complete consumption

### Chaos Tests

**Process Crashes**:
- Kill Exec during turn
- Kill Port during turn
- Verify cleanup happens

**Resource Exhaustion**:
- Many concurrent turns
- Large event payloads
- Verify no leaks

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

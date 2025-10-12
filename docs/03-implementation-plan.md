# Implementation Plan - TDD Approach

## Overview

This document outlines a test-driven development (TDD) approach to implementing the Elixir Codex SDK. The plan is organized into four one-week sprints, with each sprint building on the previous one. All tests are written before implementation, using Supertester for deterministic OTP testing.

## Guiding Principles

1. **Test First**: Write tests before implementation
2. **Red-Green-Refactor**: Fail → Pass → Clean
3. **Small Steps**: Incremental progress with frequent validation
4. **Async Tests**: All tests run with `async: true`
5. **No Process.sleep**: Use Supertester for proper synchronization
6. **Integration Last**: Unit tests → integration tests → live tests

## Sprint 0: Project Setup (Pre-development)

### Goals
- [x] Initialize Mix project
- [x] Configure dependencies
- [x] Set up CI/CD pipeline
- [x] Create documentation structure
- [x] Define project standards

### Tasks Completed
- [x] Run `mix new codex_sdk`
- [x] Add dependencies to `mix.exs`
  - [x] jason (JSON parsing)
  - [x] typed_struct (type definitions)
  - [x] telemetry (observability)
  - [x] supertester (testing)
  - [x] mox (mocking)
  - [x] ex_doc (documentation)
  - [x] credo (linting)
  - [x] dialyxir (type checking)
  - [x] excoveralls (coverage)
- [x] Configure ExDoc with documentation structure
- [x] Set up GitHub Actions workflow
- [x] Create initial README
- [x] Write project documentation (01.md, 02-architecture.md, etc.)

### Deliverables
- [x] Working Mix project
- [x] Passing `mix deps.get`
- [x] Passing `mix compile`
- [x] Green CI build
- [x] Complete documentation structure

---

## Sprint 1: Type Definitions and Module Stubs

**Duration**: Week 1
**Focus**: Define all types, create module structure, establish test infrastructure

### Phase 1.1: Event Types (Day 1)

#### Tests to Write

**`test/codex/events_test.exs`**:
```elixir
defmodule Codex.EventsTest do
  use ExUnit.Case, async: true

  describe "ThreadStarted" do
    test "creates struct with required fields" do
      event = %Codex.Events.ThreadStarted{
        type: :thread_started,
        thread_id: "thread_abc123"
      }

      assert event.type == :thread_started
      assert event.thread_id == "thread_abc123"
    end

    test "enforces required fields" do
      assert_raise ArgumentError, fn ->
        %Codex.Events.ThreadStarted{}
      end
    end

    test "encodes to JSON correctly" do
      event = %Codex.Events.ThreadStarted{
        type: :thread_started,
        thread_id: "thread_abc123"
      }

      json = Jason.encode!(event)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "thread_started"
      assert decoded["thread_id"] == "thread_abc123"
    end
  end

  # Similar tests for:
  # - TurnStarted
  # - TurnCompleted (with Usage)
  # - TurnFailed
  # - ItemStarted, ItemUpdated, ItemCompleted
  # - ThreadError
end
```

#### Implementation

**`lib/codex/events.ex`**:
```elixir
defmodule Codex.Events do
  @moduledoc "Event types emitted during turn execution"
end

defmodule Codex.Events.ThreadStarted do
  use TypedStruct

  typedstruct do
    field :type, :thread_started, enforce: true
    field :thread_id, String.t(), enforce: true
  end

  @derive Jason.Encoder
end

# Implement remaining event types...
```

#### Acceptance Criteria
- [ ] All event types defined with TypedStruct
- [ ] All fields documented
- [ ] JSON encoding/decoding working
- [ ] Tests passing (async: true)
- [ ] Dialyzer clean
- [ ] ExDoc generated

---

### Phase 1.2: Item Types (Day 2)

#### Tests to Write

**`test/codex/items_test.exs`**:
```elixir
defmodule Codex.ItemsTest do
  use ExUnit.Case, async: true

  describe "AgentMessage" do
    test "creates message item" do
      item = %Codex.Items.AgentMessage{
        id: "msg_1",
        type: :agent_message,
        text: "Hello, world!"
      }

      assert item.id == "msg_1"
      assert item.type == :agent_message
      assert item.text == "Hello, world!"
    end

    test "encodes to JSON" do
      item = %Codex.Items.AgentMessage{
        id: "msg_1",
        type: :agent_message,
        text: "Hello"
      }

      json = Jason.encode!(item)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "agent_message"
    end
  end

  describe "CommandExecution" do
    test "creates command with status" do
      item = %Codex.Items.CommandExecution{
        id: "cmd_1",
        type: :command_execution,
        command: "ls -la",
        aggregated_output: "",
        status: :in_progress
      }

      assert item.command == "ls -la"
      assert item.status == :in_progress
    end

    test "accepts completed status with exit code" do
      item = %Codex.Items.CommandExecution{
        id: "cmd_1",
        type: :command_execution,
        command: "ls -la",
        aggregated_output: "total 0",
        exit_code: 0,
        status: :completed
      }

      assert item.exit_code == 0
      assert item.status == :completed
    end
  end

  # Similar tests for all item types
end
```

#### Implementation

**`lib/codex/items.ex`**:
```elixir
defmodule Codex.Items do
  @moduledoc "Thread item types and their variants"
end

defmodule Codex.Items.AgentMessage do
  use TypedStruct

  typedstruct do
    field :id, String.t(), enforce: true
    field :type, :agent_message, default: :agent_message
    field :text, String.t(), enforce: true
  end

  @derive Jason.Encoder
end

# Implement all item types...
```

#### Acceptance Criteria
- [ ] All item types defined
- [ ] Status enums documented
- [ ] JSON encoding working
- [ ] Tests passing
- [ ] Dialyzer clean

---

### Phase 1.3: Option Structs (Day 3)

#### Tests to Write

**`test/codex/options_test.exs`**:
```elixir
defmodule Codex.OptionsTest do
  use ExUnit.Case, async: true

  describe "Codex.Options" do
    test "creates with default values" do
      opts = %Codex.Options{}

      assert opts.codex_path_override == nil
      assert opts.base_url == nil
      assert opts.api_key == nil
    end

    test "creates with custom values" do
      opts = %Codex.Options{
        codex_path_override: "/usr/bin/codex",
        api_key: "sk-test"
      }

      assert opts.codex_path_override == "/usr/bin/codex"
      assert opts.api_key == "sk-test"
    end
  end

  describe "Codex.Thread.Options" do
    test "creates with defaults" do
      opts = %Codex.Thread.Options{}

      assert opts.sandbox_mode == nil
      assert opts.skip_git_repo_check == false
    end

    test "validates sandbox mode" do
      opts = %Codex.Thread.Options{
        sandbox_mode: :read_only
      }

      assert opts.sandbox_mode == :read_only
    end
  end

  # Tests for Turn.Options
end
```

#### Implementation

**`lib/codex/options.ex`**:
```elixir
defmodule Codex.Options do
  use TypedStruct

  typedstruct do
    field :codex_path_override, String.t()
    field :base_url, String.t()
    field :api_key, String.t()
  end
end

# Implement Thread.Options and Turn.Options...
```

#### Acceptance Criteria
- [ ] All option structs defined
- [ ] Defaults documented
- [ ] Validation helpers implemented
- [ ] Tests passing

---

### Phase 1.4: Module Stubs (Day 4)

#### Tests to Write

**`test/codex_test.exs`**:
```elixir
defmodule CodexTest do
  use ExUnit.Case, async: true

  describe "start_thread/2" do
    test "returns thread struct" do
      assert {:ok, thread} = Codex.start_thread()
      assert %Codex.Thread{} = thread
      assert thread.thread_id == nil
    end

    test "accepts options" do
      codex_opts = %Codex.Options{api_key: "sk-test"}
      thread_opts = %Codex.Thread.Options{model: "o1"}

      assert {:ok, thread} = Codex.start_thread(codex_opts, thread_opts)
      assert thread.codex_opts.api_key == "sk-test"
      assert thread.thread_opts.model == "o1"
    end
  end

  describe "resume_thread/3" do
    test "returns thread with ID" do
      assert {:ok, thread} = Codex.resume_thread("thread_123")
      assert thread.thread_id == "thread_123"
    end
  end
end
```

**`test/codex/thread_test.exs`**:
```elixir
defmodule Codex.ThreadTest do
  use ExUnit.Case, async: true

  describe "run/3" do
    test "defined but not implemented" do
      thread = %Codex.Thread{
        thread_id: nil,
        codex_opts: %Codex.Options{},
        thread_opts: %Codex.Thread.Options{}
      }

      # Should compile but not work yet
      assert function_exported?(Codex.Thread, :run, 3)
    end
  end
end
```

#### Implementation

**`lib/codex.ex`**:
```elixir
defmodule Codex do
  @moduledoc "Main entry point for Codex SDK"

  alias Codex.Thread

  @spec start_thread(Codex.Options.t(), Codex.Thread.Options.t()) ::
    {:ok, Thread.t()}
  def start_thread(codex_opts \\ %Codex.Options{}, thread_opts \\ %Codex.Thread.Options{}) do
    thread = %Thread{
      thread_id: nil,
      codex_opts: codex_opts,
      thread_opts: thread_opts
    }

    {:ok, thread}
  end

  @spec resume_thread(String.t(), Codex.Options.t(), Codex.Thread.Options.t()) ::
    {:ok, Thread.t()}
  def resume_thread(thread_id, codex_opts \\ %Codex.Options{}, thread_opts \\ %Codex.Thread.Options{}) do
    thread = %Thread{
      thread_id: thread_id,
      codex_opts: codex_opts,
      thread_opts: thread_opts
    }

    {:ok, thread}
  end
end
```

**`lib/codex/thread.ex`**:
```elixir
defmodule Codex.Thread do
  @moduledoc "Manages conversation threads"

  defstruct [:thread_id, :codex_opts, :thread_opts]

  @type t :: %__MODULE__{
    thread_id: String.t() | nil,
    codex_opts: Codex.Options.t(),
    thread_opts: Codex.Thread.Options.t()
  }

  @spec run(t(), String.t(), Codex.Turn.Options.t()) ::
    {:ok, Codex.Turn.Result.t()} | {:error, term()}
  def run(_thread, _input, _opts \\ %Codex.Turn.Options{}) do
    raise "Not implemented"
  end

  @spec run_streamed(t(), String.t(), Codex.Turn.Options.t()) ::
    {:ok, Enumerable.t()} | {:error, term()}
  def run_streamed(_thread, _input, _opts \\ %Codex.Turn.Options{}) do
    raise "Not implemented"
  end
end
```

#### Acceptance Criteria
- [ ] All modules compile
- [ ] Stubs defined with typespecs
- [ ] Documentation stubs present
- [ ] Basic tests passing
- [ ] Dialyzer clean

---

### Phase 1.5: OutputSchemaFile Utility (Day 5)

#### Tests to Write

**`test/codex/output_schema_file_test.exs`**:
```elixir
defmodule Codex.OutputSchemaFileTest do
  use ExUnit.Case, async: true

  describe "create/1" do
    test "returns nil path for nil schema" do
      assert {:ok, {nil, cleanup}} = Codex.OutputSchemaFile.create(nil)
      assert is_function(cleanup, 0)
      cleanup.()
    end

    test "creates temp file with schema" do
      schema = %{"type" => "object", "properties" => %{}}

      assert {:ok, {path, cleanup}} = Codex.OutputSchemaFile.create(schema)
      assert is_binary(path)
      assert File.exists?(path)

      # Verify content
      {:ok, content} = File.read(path)
      assert Jason.decode!(content) == schema

      # Cleanup removes file
      cleanup.()
      refute File.exists?(path)
    end

    test "cleanup is idempotent" do
      schema = %{"type" => "object"}

      assert {:ok, {_path, cleanup}} = Codex.OutputSchemaFile.create(schema)

      cleanup.()
      cleanup.()  # Should not crash
    end

    test "returns error for invalid schema" do
      assert {:error, _} = Codex.OutputSchemaFile.create("not a map")
    end
  end
end
```

#### Implementation

**`lib/codex/output_schema_file.ex`**:
```elixir
defmodule Codex.OutputSchemaFile do
  @moduledoc "Helper for managing JSON schema temporary files"

  @spec create(map() | nil) :: {:ok, {String.t() | nil, function()}} | {:error, term()}
  def create(nil) do
    cleanup = fn -> :ok end
    {:ok, {nil, cleanup}}
  end

  def create(schema) when is_map(schema) do
    # Implementation...
  end

  def create(_), do: {:error, :invalid_schema}
end
```

#### Acceptance Criteria
- [ ] Handles nil schema
- [ ] Creates temp file
- [ ] Writes JSON correctly
- [ ] Cleanup removes file
- [ ] Tests passing

---

## Sprint 2: Exec GenServer Implementation

**Duration**: Week 2
**Focus**: Process management, Port communication, event parsing

### Phase 2.1: GenServer Skeleton (Day 6)

#### Tests to Write

**`test/codex/exec_test.exs`**:
```elixir
defmodule Codex.ExecTest do
  use ExUnit.Case, async: true
  use Supertester

  describe "start_link/1" do
    test "starts GenServer successfully" do
      opts = [
        input: "Hello",
        codex_path: "/bin/true"  # Use /bin/true for testing
      ]

      assert {:ok, pid} = Codex.Exec.start_link(opts)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "returns error for missing codex binary" do
      opts = [
        input: "Hello",
        codex_path: "/nonexistent/codex"
      ]

      assert {:error, _} = Codex.Exec.start_link(opts)
    end
  end

  describe "init/1" do
    test "spawns port with correct arguments" do
      # Test with mock that logs spawn args
      # Verify Port.open called with correct args
    end
  end
end
```

#### Implementation

**`lib/codex/exec.ex`**:
```elixir
defmodule Codex.Exec do
  use GenServer
  require Logger

  defstruct [
    :port,
    :caller,
    :ref,
    buffer: "",
    exit_status: nil,
    stderr_buffer: ""
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    # Validate codex path exists
    # Build command args
    # Spawn port
    # Send telemetry
    {:ok, %__MODULE__{}}
  end

  @impl true
  def terminate(reason, state) do
    # Close port
    # Send telemetry
    :ok
  end
end
```

#### Acceptance Criteria
- [ ] GenServer starts successfully
- [ ] Port spawned
- [ ] Validation works
- [ ] Tests passing with Supertester

---

### Phase 2.2: Port Communication (Day 7-8)

#### Tests to Write

```elixir
defmodule Codex.Exec.PortTest do
  use ExUnit.Case, async: true
  use Supertester

  describe "stdin writing" do
    test "writes input to port" do
      # Use echo command to test stdin
      opts = [
        input: "test input",
        codex_path: "/bin/cat"
      ]

      {:ok, pid} = Codex.Exec.start_link(opts)

      # Assert output received
      assert_receive {:stdout, "test input"}

      GenServer.stop(pid)
    end
  end

  describe "stdout reading" do
    test "receives data from port" do
      # Use script that outputs known data
    end

    test "handles incomplete lines" do
      # Test buffer accumulation
    end
  end

  describe "stderr handling" do
    test "accumulates stderr" do
      # Test stderr capture
    end
  end

  describe "exit status" do
    test "receives exit status 0" do
      # Test successful exit
    end

    test "receives non-zero exit status" do
      # Test failure exit
    end
  end
end
```

#### Implementation

```elixir
@impl true
def handle_info({port, {:data, data}}, %{port: port} = state) do
  # Append to buffer
  # Split on newlines
  # Process complete lines
  # Keep incomplete line in buffer
  {:noreply, state}
end

@impl true
def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
  # Handle exit
  # Send final events
  {:stop, :normal, state}
end
```

#### Acceptance Criteria
- [ ] Stdin writing works
- [ ] Stdout reading works
- [ ] Line buffering correct
- [ ] Exit status captured
- [ ] Tests passing

---

### Phase 2.3: Event Parsing (Day 9)

#### Tests to Write

```elixir
defmodule Codex.Exec.ParserTest do
  use ExUnit.Case, async: true

  describe "parse_event/1" do
    test "parses ThreadStarted event" do
      json = ~s({"type":"thread.started","thread_id":"thread_123"})

      assert {:ok, event} = Codex.Exec.Parser.parse_event(json)
      assert %Codex.Events.ThreadStarted{} = event
      assert event.thread_id == "thread_123"
    end

    test "parses ItemCompleted with AgentMessage" do
      json = ~s({"type":"item.completed","item":{"id":"msg_1","type":"agent_message","text":"Hello"}})

      assert {:ok, event} = Codex.Exec.Parser.parse_event(json)
      assert %Codex.Events.ItemCompleted{} = event
      assert %Codex.Items.AgentMessage{} = event.item
    end

    test "returns error for invalid JSON" do
      assert {:error, _} = Codex.Exec.Parser.parse_event("invalid")
    end

    test "returns error for unknown event type" do
      json = ~s({"type":"unknown.event"})
      assert {:error, _} = Codex.Exec.Parser.parse_event(json)
    end
  end
end
```

#### Implementation

**`lib/codex/exec/parser.ex`**:
```elixir
defmodule Codex.Exec.Parser do
  @moduledoc "Parses JSONL events from codex-rs"

  def parse_event(line) do
    with {:ok, json} <- Jason.decode(line),
         {:ok, event} <- build_event(json) do
      {:ok, event}
    end
  end

  defp build_event(%{"type" => "thread.started"} = json) do
    # Build ThreadStarted struct
  end

  # More event builders...
end
```

#### Acceptance Criteria
- [ ] All event types parsed
- [ ] All item types parsed
- [ ] Error handling works
- [ ] Tests passing

---

### Phase 2.4: Integration (Day 10)

#### Tests to Write

```elixir
defmodule Codex.Exec.IntegrationTest do
  use ExUnit.Case, async: true
  use Supertester

  @moduletag :integration

  test "full turn execution with mock script" do
    # Create mock script that emits test events
    script_path = create_mock_script()

    opts = [
      input: "test",
      codex_path: script_path
    ]

    {:ok, pid} = Codex.Exec.start_link(opts)
    ref = Codex.Exec.run_turn(pid)

    # Assert events received in order
    assert_receive {:event, ^ref, %Codex.Events.ThreadStarted{}}
    assert_receive {:event, ^ref, %Codex.Events.TurnStarted{}}
    assert_receive {:event, ^ref, %Codex.Events.ItemStarted{}}
    assert_receive {:event, ^ref, %Codex.Events.ItemCompleted{}}
    assert_receive {:event, ^ref, %Codex.Events.TurnCompleted{}}
    assert_receive {:done, ^ref}

    GenServer.stop(pid)
  end

  defp create_mock_script do
    # Write shell script that outputs test events
  end
end
```

#### Acceptance Criteria
- [ ] Full turn execution works
- [ ] Events in correct order
- [ ] Cleanup works
- [ ] Tests passing

---

## Sprint 3: Thread Management

**Duration**: Week 3
**Focus**: Turn execution, streaming, option handling

### Phase 3.1: Blocking Turn Execution (Day 11-12)

#### Tests to Write

```elixir
defmodule Codex.Thread.RunTest do
  use ExUnit.Case, async: true
  use Supertester

  describe "run/3" do
    test "executes turn and returns result" do
      thread = %Codex.Thread{
        thread_id: nil,
        codex_opts: %Codex.Options{},
        thread_opts: %Codex.Thread.Options{}
      }

      # Mock Exec to return test events
      with_mock_exec(fn ->
        assert {:ok, result} = Codex.Thread.run(thread, "Hello")

        assert %Codex.Turn.Result{} = result
        assert result.final_response == "Hello, world!"
        assert length(result.items) > 0
        assert result.usage.input_tokens > 0
      end)
    end

    test "populates thread_id after first turn" do
      thread = %Codex.Thread{thread_id: nil, ...}

      with_mock_exec(fn ->
        {:ok, updated_thread, _result} = Codex.Thread.run(thread, "Hello")

        assert updated_thread.thread_id == "thread_123"
      end)
    end

    test "handles turn failure" do
      thread = %Codex.Thread{...}

      with_mock_exec(fn ->
        assert {:error, {:turn_failed, error}} = Codex.Thread.run(thread, "Bad input")
        assert error.message =~ "error"
      end)
    end
  end
end
```

#### Implementation

```elixir
def run(%Thread{} = thread, input, opts \\ %Codex.Turn.Options{}) do
  {schema_path, cleanup} = OutputSchemaFile.create(opts.output_schema)

  try do
    {:ok, pid} = Exec.start_link(build_exec_opts(thread, input, schema_path))
    ref = Exec.run_turn(pid)

    result = collect_events(pid, ref)

    {:ok, result}
  after
    cleanup.()
  end
end

defp collect_events(pid, ref) do
  # Accumulate events until done
  # Build TurnResult
end
```

#### Acceptance Criteria
- [ ] Turn execution works
- [ ] Result accumulated correctly
- [ ] Thread ID updated
- [ ] Errors handled
- [ ] Tests passing

---

### Phase 3.2: Streaming Turn Execution (Day 13-14)

#### Tests to Write

```elixir
defmodule Codex.Thread.StreamedTest do
  use ExUnit.Case, async: true
  use Supertester

  describe "run_streamed/3" do
    test "returns stream of events" do
      thread = %Codex.Thread{...}

      with_mock_exec(fn ->
        assert {:ok, stream} = Codex.Thread.run_streamed(thread, "Hello")

        events = Enum.to_list(stream)

        assert length(events) > 0
        assert %Codex.Events.ThreadStarted{} = hd(events)
        assert %Codex.Events.TurnCompleted{} = List.last(events)
      end)
    end

    test "stream is lazy" do
      # Verify events not processed until consumed
    end

    test "stream cleanup on halt" do
      # Verify resources cleaned up if stream halted early
    end
  end
end
```

#### Implementation

```elixir
def run_streamed(%Thread{} = thread, input, opts \\ %Codex.Turn.Options{}) do
  {schema_path, cleanup} = OutputSchemaFile.create(opts.output_schema)

  stream = Stream.resource(
    fn -> start_turn(thread, input, schema_path, cleanup) end,
    fn state -> fetch_next_event(state) end,
    fn state -> cleanup_turn(state) end
  )

  {:ok, stream}
end
```

#### Acceptance Criteria
- [ ] Stream returns events
- [ ] Lazy evaluation
- [ ] Cleanup works
- [ ] Tests passing

---

### Phase 3.3: Option Handling (Day 15)

#### Tests to Write

```elixir
describe "option passing" do
  test "passes codex options to exec" do
    # Test API key, base URL passed
  end

  test "passes thread options to exec" do
    # Test model, sandbox, working directory
  end

  test "passes turn options to exec" do
    # Test output schema
  end
end
```

#### Acceptance Criteria
- [ ] All options passed correctly
- [ ] Environment variables set
- [ ] Command args correct
- [ ] Tests passing

---

## Sprint 4: Integration and Polish

**Duration**: Week 4
**Focus**: End-to-end tests, examples, documentation, CI/CD

### Phase 4.1: Integration Tests (Day 16-17)

#### Tests to Write

```elixir
defmodule Codex.IntegrationTest do
  use ExUnit.Case
  use Supertester

  @moduletag :integration

  describe "complete workflow" do
    test "start thread, run turn, get result" do
      {:ok, thread} = Codex.start_thread()

      {:ok, result} = Codex.Thread.run(thread, "Say hello")

      assert result.final_response =~ "hello"
    end

    test "multiple turns in same thread" do
      {:ok, thread} = Codex.start_thread()

      {:ok, result1} = Codex.Thread.run(thread, "Say hello")
      {:ok, result2} = Codex.Thread.run(thread, "Say goodbye")

      assert result2.items |> length() > 0
    end

    test "resume thread" do
      {:ok, thread1} = Codex.start_thread()
      {:ok, _result} = Codex.Thread.run(thread1, "Remember: banana")

      # Resume with same ID
      {:ok, thread2} = Codex.resume_thread(thread1.thread_id)
      {:ok, result} = Codex.Thread.run(thread2, "What should I remember?")

      assert result.final_response =~ "banana"
    end

    test "structured output" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "message" => %{"type" => "string"}
        }
      }

      {:ok, thread} = Codex.start_thread()

      {:ok, result} = Codex.Thread.run(
        thread,
        "Say hello in JSON",
        %Codex.Turn.Options{output_schema: schema}
      )

      assert {:ok, json} = Jason.decode(result.final_response)
      assert json["message"]
    end
  end
end
```

#### Acceptance Criteria
- [ ] All integration tests passing
- [ ] Real codex-rs tested (when available)
- [ ] Mock tests passing
- [ ] Coverage > 95%

---

### Phase 4.2: Examples (Day 18)

Create example scripts:

1. **`examples/basic.exs`**: Simple conversation
2. **`examples/streaming.exs`**: Real-time event processing
3. **`examples/structured_output.exs`**: JSON schema usage
4. **`examples/multi_turn.exs`**: Extended conversation
5. **`examples/file_operations.exs`**: File change tracking

Each example should:
- [ ] Be runnable with `mix run examples/X.exs`
- [ ] Include comments explaining each step
- [ ] Demonstrate best practices
- [ ] Handle errors gracefully

---

### Phase 4.3: Documentation Polish (Day 19)

Tasks:
- [ ] Complete all @doc and @moduledoc
- [ ] Add @spec for all public functions
- [ ] Generate ExDoc HTML
- [ ] Review and update all guides
- [ ] Add diagrams where helpful
- [ ] Create CHANGELOG.md
- [ ] Update README with current status

---

### Phase 4.4: CI/CD and Release (Day 20)

Tasks:
- [ ] Ensure CI passing
- [ ] Run Dialyzer (zero warnings)
- [ ] Run Credo (zero issues)
- [ ] Check test coverage (>95%)
- [ ] Review security (no hardcoded secrets)
- [ ] Tag v0.1.0
- [ ] Publish to Hex.pm
- [ ] Generate and publish docs to HexDocs

---

## Testing Strategy Summary

### Test Categories

1. **Unit Tests**: Test individual functions in isolation
   - All async: true
   - Use Supertester for OTP testing
   - Mock external dependencies
   - Fast (< 1ms per test)

2. **Integration Tests**: Test component interactions
   - Tagged `:integration`
   - Use mock codex-rs script
   - Test full workflows
   - Medium speed (< 100ms per test)

3. **Live Tests**: Test with real codex-rs
   - Tagged `:live`
   - Require API key via env var
   - Optional (skip in CI)
   - Slow (seconds per test)

### Coverage Goals

- **Overall**: 95%+
- **Core modules**: 100% (Codex, Thread, Exec)
- **Types**: 100% (Events, Items, Options)
- **Utilities**: 90%+

### Test Infrastructure

**Supertester Setup**:
```elixir
# test/support/supertester_helpers.ex
defmodule CodexSdk.SupertesterHelpers do
  use Supertester

  def with_mock_exec(fun) do
    # Helper to mock Exec GenServer
  end

  def mock_events(events) do
    # Helper to emit mock events
  end
end
```

**Mox Setup**:
```elixir
# test/support/mocks.ex
Mox.defmock(CodexSdk.ExecMock, for: CodexSdk.ExecBehaviour)
```

---

## Milestones

### M1: Types Complete (End of Sprint 1)
- [x] All TypedStructs defined
- [x] JSON encoding working
- [x] Module stubs created
- [x] Tests passing

### M2: Exec Working (End of Sprint 2)
- [ ] Exec GenServer functional
- [ ] Port communication working
- [ ] Event parsing complete
- [ ] Integration tests passing

### M3: API Complete (End of Sprint 3)
- [ ] Blocking turns working
- [ ] Streaming turns working
- [ ] All options supported
- [ ] Full test coverage

### M4: Production Ready (End of Sprint 4)
- [ ] All tests passing
- [ ] Documentation complete
- [ ] Examples working
- [ ] Published to Hex.pm

---

## Risk Management

### Known Risks

1. **codex-rs changes**: TypeScript SDK may change
   - Mitigation: Pin to specific version, test with multiple versions

2. **Port communication complexity**: Edge cases in JSONL parsing
   - Mitigation: Comprehensive parser tests, fuzzing

3. **Process cleanup**: Resource leaks on crashes
   - Mitigation: Chaos tests, supervision review

4. **Test determinism**: Flaky tests with OTP
   - Mitigation: Supertester, no Process.sleep, proper sync

### Contingency Plans

- **Behind schedule**: Cut streaming mode to v1.1
- **Critical bugs**: Focus on blocking mode first
- **API changes**: Document breaking changes, version clearly

---

## Definition of Done

A feature is complete when:
- [ ] Tests written first (TDD)
- [ ] Tests passing (async: true)
- [ ] Code documented (@doc, @moduledoc, @spec)
- [ ] Dialyzer clean
- [ ] Credo clean
- [ ] Coverage maintained (>95%)
- [ ] Reviewed by team
- [ ] Examples updated
- [ ] Changelog updated

---

## Success Metrics

### Quantitative
- 95%+ test coverage
- 100% Dialyzer clean
- 100% Credo compliant
- < 5 minute full test suite
- < 50ms average test time
- Zero flaky tests

### Qualitative
- Clear, readable code
- Comprehensive documentation
- Helpful error messages
- Easy to use API
- Well-commented examples
- Positive community feedback

---

## Next Steps After MVP

### v0.2.0 Features
- [ ] Telemetry documentation
- [ ] Supervision tree examples
- [ ] Performance benchmarks
- [ ] Phoenix LiveView integration

### v0.3.0 Features
- [ ] Persistent event logging
- [ ] Custom event handlers API
- [ ] Advanced streaming modes
- [ ] WebSocket support (if codex-rs adds it)

### v1.0.0 Criteria
- [ ] 6+ months in production
- [ ] Stable API (no breaking changes)
- [ ] Comprehensive docs
- [ ] Active maintenance
- [ ] Community adoption

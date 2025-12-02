# Testing Strategy

## Overview

The Elixir Codex SDK follows a comprehensive test-driven development (TDD) approach using Supertester for deterministic OTP testing. This document outlines our testing philosophy, strategies, tools, and best practices.

## Testing Philosophy

### Core Principles

1. **Test First**: Write tests before implementation
2. **Deterministic**: Zero flaky tests, zero `Process.sleep`
3. **Fast**: Full suite < 5 minutes, average test < 50ms
4. **Comprehensive**: 95%+ coverage, all edge cases
5. **Maintainable**: Clear, readable, well-organized tests
6. **Async**: All tests run with `async: true` where possible

### Red-Green-Refactor Cycle

1. **Red**: Write a failing test that defines desired behavior
2. **Green**: Write minimal code to make test pass
3. **Refactor**: Improve code quality while keeping tests green
4. **Repeat**: Continue with next feature

## Test Categories

### 1. Unit Tests

**Purpose**: Test individual functions and modules in isolation.

**Characteristics**:
- Run with `async: true`
- Mock all external dependencies
- Focus on single responsibility
- Fast (< 1ms per test)
- High coverage of edge cases

**Example**:
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
  end
end
```

### 2. Integration Tests

**Purpose**: Test interactions between components.

**Characteristics**:
- Tagged `:integration`
- Use mock codex-rs script
- Test full workflows
- Medium speed (< 100ms per test)
- May run synchronously

**Example**:
```elixir
defmodule Codex.Thread.IntegrationTest do
  use ExUnit.Case
  use Supertester

  @moduletag :integration

  test "full turn execution with mock codex" do
    mock_script = create_mock_codex_script([
      ~s({"type":"thread.started","thread_id":"thread_123"}),
      ~s({"type":"turn.started"}),
      ~s({"type":"item.completed","item":{"id":"1","type":"agent_message","text":"Hello"}}),
      ~s({"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5}})
    ])

    codex_opts = %Codex.Options{codex_path_override: mock_script}
    {:ok, thread} = Codex.start_thread(codex_opts)

    {:ok, result} = Codex.Thread.run(thread, "test input")

    assert result.final_response == "Hello"
    assert result.usage.input_tokens == 10
    assert thread.thread_id == "thread_123"

    File.rm!(mock_script)
  end

  defp create_mock_codex_script(events) do
    script = """
    #!/bin/bash
    #{Enum.map_join(events, "\n", &"echo '#{&1}'")}
    """

    path = Path.join(System.tmp_dir!(), "mock_codex_#{:rand.uniform(10000)}")
    File.write!(path, script)
    File.chmod!(path, 0o755)
    path
  end
end
```

### 3. Live Tests

**Purpose**: Test against real codex-rs binary and OpenAI API.

**Characteristics**:
- Tagged `:live`
- Require API key via environment variable
- Optional (skip in CI by default)
- Slow (seconds per test)
- Useful for validation and debugging

**Example**:
```elixir
defmodule Codex.LiveTest do
  use ExUnit.Case

  @moduletag :live
  @moduletag timeout: 60_000

  setup do
    unless System.get_env("CODEX_API_KEY") do
      ExUnit.configure(exclude: [:live])
    end

    :ok
  end

  test "real turn execution" do
    {:ok, thread} = Codex.start_thread()

    {:ok, result} = Codex.Thread.run(thread, "Say 'test successful' and nothing else")

    assert result.final_response =~ "test successful"
    assert result.usage.input_tokens > 0
  end
end
```

### 4. Property Tests

**Purpose**: Test properties that should hold for all inputs.

**Characteristics**:
- Use StreamData for generation
- Test invariants and laws
- Discover edge cases automatically
- Run many iterations

**Example**:
```elixir
defmodule Codex.Events.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  property "all events encode and decode correctly" do
    check all event <- event_generator() do
      json = Jason.encode!(event)
      {:ok, decoded} = Jason.decode(json)

      assert decoded["type"] in [
        "thread.started", "turn.started", "turn.completed",
        "turn.failed", "item.started", "item.updated",
        "item.completed", "error"
      ]
    end
  end

  defp event_generator do
    gen all type <- member_of([:thread_started, :turn_started, :turn_completed]),
            thread_id <- string(:alphanumeric, min_length: 1, max_length: 50) do
      case type do
        :thread_started ->
          %Codex.Events.ThreadStarted{
            type: :thread_started,
            thread_id: thread_id
          }

        :turn_started ->
          %Codex.Events.TurnStarted{type: :turn_started}

        :turn_completed ->
          %Codex.Events.TurnCompleted{
            type: :turn_completed,
            usage: %Codex.Events.Usage{
              input_tokens: 10,
              cached_input_tokens: 0,
              output_tokens: 5
            }
          }
      end
    end
  end
end
```

### 5. Chaos Tests

**Purpose**: Test system resilience under adverse conditions.

**Characteristics**:
- Simulate process crashes
- Test resource cleanup
- Verify supervision behavior
- Test under high load

**Example**:
```elixir
defmodule Codex.ChaosTest do
  use ExUnit.Case
  use Supertester

  describe "resilience" do
    test "handles Exec GenServer crash during turn" do
      {:ok, thread} = Codex.start_thread()

      # Start turn in separate process
      task = Task.async(fn ->
        Codex.Thread.run(thread, "test")
      end)

      # Give it time to start
      Process.sleep(50)

      # Find and kill the Exec GenServer
      [{exec_pid, _}] = Registry.lookup(CodexSdk.ExecRegistry, thread.thread_id)
      Process.exit(exec_pid, :kill)

      # Should return error, not crash
      assert {:error, _} = Task.await(task)
    end

    test "cleans up resources on early stream halt" do
      {:ok, thread} = Codex.start_thread()
      {:ok, result} = Codex.Thread.run_streamed(thread, "test")

      # Track temp files before
      temp_files_before = count_temp_files()

      # Take only first event, halting stream early
      [_first_event | _] = result |> Codex.RunResultStreaming.raw_events() |> Enum.take(1)

      # Give cleanup time
      Process.sleep(100)

      # Verify no temp files leaked
      temp_files_after = count_temp_files()
      assert temp_files_after <= temp_files_before
    end

    defp count_temp_files do
      Path.wildcard(Path.join(System.tmp_dir!(), "codex-output-schema-*"))
      |> length()
    end
  end
end
```

## Supertester Integration

### Why Supertester?

[Supertester](https://hex.pm/packages/supertester) provides deterministic OTP testing without `Process.sleep`. It enables:

1. **Proper Synchronization**: Wait for actual conditions, not arbitrary timeouts
2. **Async Safety**: All tests can run `async: true`
3. **Clear Assertions**: Readable test code with helpful error messages
4. **Zero Flakes**: Deterministic behavior eliminates timing issues

### Basic Usage

```elixir
defmodule Codex.Exec.SupertesterTest do
  use ExUnit.Case, async: true
  use Supertester

  test "GenServer receives message" do
    {:ok, pid} = Codex.Exec.start_link(...)

    # Send message
    send(pid, {:test, self()})

    # Wait for response (not Process.sleep!)
    assert_receive {:response, value}
    assert value == :expected
  end

  test "GenServer state changes" do
    {:ok, pid} = Codex.Exec.start_link(...)

    # Trigger state change
    GenServer.call(pid, :change_state)

    # Assert state changed
    assert :sys.get_state(pid).changed == true
  end
end
```

### Advanced Patterns

**Testing Async Workflows**:
```elixir
test "async event processing" do
  {:ok, pid} = Codex.Exec.start_link(...)

  ref = make_ref()
  GenServer.cast(pid, {:process, ref, self()})

  # Wait for specific message pattern
  assert_receive {:processed, ^ref, result}, 1000
  assert result.success
end
```

**Testing Supervision**:
```elixir
test "supervised restart" do
  {:ok, sup} = Codex.Supervisor.start_link()

  # Get child pid
  [{:undefined, pid, :worker, _}] = Supervisor.which_children(sup)

  # Kill child
  Process.exit(pid, :kill)

  # Wait for restart
  eventually(fn ->
    [{:undefined, new_pid, :worker, _}] = Supervisor.which_children(sup)
    assert new_pid != pid
    assert Process.alive?(new_pid)
  end)
end
```

## Mock Strategies

### 1. Mox for Protocols

**When**: Testing modules that depend on behaviors.

**Example**:
```elixir
# Define behavior
defmodule Codex.ExecBehaviour do
  @callback run_turn(pid(), String.t(), map()) :: reference()
  @callback get_events(pid(), reference()) :: [Codex.Events.t()]
end

# Define mock in test_helper.exs
Mox.defmock(Codex.ExecMock, for: Codex.ExecBehaviour)

# Use in tests
test "thread uses exec" do
  Mox.expect(Codex.ExecMock, :run_turn, fn _pid, input, _opts ->
    assert input == "test"
    make_ref()
  end)

  Mox.expect(Codex.ExecMock, :get_events, fn _pid, _ref ->
    [
      %Codex.Events.ThreadStarted{...},
      %Codex.Events.TurnCompleted{...}
    ]
  end)

  # Test with mock
  thread = %Codex.Thread{exec: Codex.ExecMock, ...}
  {:ok, result} = Codex.Thread.run(thread, "test")
end
```

### 2. Mock Scripts for Exec

**When**: Testing Exec GenServer with controlled output.

**Example**:
```elixir
defmodule MockCodexScript do
  def create(events) when is_list(events) do
    script_content = """
    #!/bin/bash
    # Read stdin (ignore for mock)
    cat > /dev/null

    # Output events
    #{Enum.map_join(events, "\n", &"echo '#{&1}'")}

    exit 0
    """

    path = Path.join(System.tmp_dir!(), "mock_codex_#{System.unique_integer([:positive])}.sh")
    File.write!(path, script_content)
    File.chmod!(path, 0o755)

    path
  end

  def cleanup(path) do
    File.rm(path)
  end
end

# Usage in tests
test "exec processes events" do
  events = [
    Jason.encode!(%{type: "thread.started", thread_id: "t1"}),
    Jason.encode!(%{type: "turn.completed", usage: %{input_tokens: 5}})
  ]

  script = MockCodexScript.create(events)

  try do
    {:ok, pid} = Codex.Exec.start_link(codex_path: script, input: "test")
    # ... test assertions
  after
    MockCodexScript.cleanup(script)
  end
end
```

### 3. Test Doubles for Data

**When**: Testing with known data structures.

**Example**:
```elixir
defmodule Codex.Fixtures do
  def thread_started_event(thread_id \\ "thread_test123") do
    %Codex.Events.ThreadStarted{
      type: :thread_started,
      thread_id: thread_id
    }
  end

  def agent_message_item(text \\ "Hello") do
    %Codex.Items.AgentMessage{
      id: "msg_#{System.unique_integer([:positive])}",
      type: :agent_message,
      text: text
    }
  end

  def complete_turn_result do
    %Codex.Turn.Result{
      items: [agent_message_item()],
      final_response: "Hello",
      usage: %Codex.Events.Usage{
        input_tokens: 10,
        cached_input_tokens: 0,
        output_tokens: 5
      }
    }
  end
end
```

## Coverage Goals

### Overall Coverage: 95%+

**Per Module**:
- Core modules (Codex, Thread, Exec): **100%**
- Type modules (Events, Items, Options): **100%**
- Utility modules (OutputSchemaFile): **95%**
- Test support modules: **80%**

### Coverage Tool: ExCoveralls

**Configuration** in `mix.exs`:
```elixir
def project do
  [
    test_coverage: [tool: ExCoveralls],
    preferred_cli_env: [
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test
    ]
  ]
end
```

**Commands**:
```bash
# Run tests with coverage
mix coveralls

# Detailed coverage report
mix coveralls.detail

# HTML coverage report
mix coveralls.html

# CI coverage (upload to Coveralls.io)
mix coveralls.github
```

### Coverage Exceptions

Some code is deliberately excluded:
```elixir
# coveralls-ignore-start
def debug_helper do
  # Only used in development
end
# coveralls-ignore-stop
```

## Test Organization

### Directory Structure

```
test/
├── codex_test.exs                    # Codex module tests
├── codex/
│   ├── thread_test.exs              # Thread module tests
│   ├── exec_test.exs                # Exec GenServer tests
│   ├── exec/
│   │   ├── parser_test.exs          # Event parser tests
│   │   └── integration_test.exs     # Exec integration tests
│   ├── events_test.exs              # Event type tests
│   ├── items_test.exs               # Item type tests
│   ├── options_test.exs             # Option struct tests
│   └── output_schema_file_test.exs  # Schema file helper tests
├── integration/
│   ├── basic_workflow_test.exs      # End-to-end workflows
│   ├── streaming_test.exs           # Streaming workflows
│   └── error_scenarios_test.exs     # Error handling
├── live/
│   └── real_codex_test.exs          # Tests with real API
├── property/
│   ├── events_property_test.exs     # Event properties
│   └── parsing_property_test.exs    # Parser properties
├── chaos/
│   └── resilience_test.exs          # Chaos engineering
├── support/
│   ├── fixtures.ex                  # Test data fixtures
│   ├── mock_codex_script.ex         # Mock script helper
│   └── supertester_helpers.ex       # Supertester utilities
└── test_helper.exs                  # Test configuration
```

### File Naming

- `*_test.exs`: Standard tests
- `*_integration_test.exs`: Integration tests
- `*_property_test.exs`: Property-based tests

### Test Naming

**Descriptive Names**:
```elixir
# Good
test "returns error when codex binary not found"
test "accumulates events until turn completes"
test "cleans up temp files on early stream halt"

# Bad
test "it works"
test "error case"
test "cleanup"
```

**Describe Blocks**:
```elixir
describe "run/3" do
  test "executes turn successfully" do
    # ...
  end

  test "handles API errors gracefully" do
    # ...
  end
end

describe "run/3 with output schema" do
  test "creates temporary schema file" do
    # ...
  end

  test "cleans up schema file after turn" do
    # ...
  end
end
```

## Assertions and Matchers

### Standard Assertions

```elixir
# Equality
assert result == expected
refute result == unexpected

# Pattern matching
assert %Codex.Events.ThreadStarted{thread_id: id} = event
assert id =~ ~r/thread_\w+/

# Boolean
assert Process.alive?(pid)
assert File.exists?(path)

# Membership
assert value in list
assert Map.has_key?(map, :key)

# Exceptions
assert_raise ArgumentError, fn ->
  %Codex.Events.ThreadStarted{}
end

# Messages
assert_receive {:event, ^ref, event}, 1000
refute_received {:error, _}
```

### Custom Assertions

```elixir
defmodule CodexSdk.Assertions do
  import ExUnit.Assertions

  def assert_valid_thread_id(thread_id) do
    assert is_binary(thread_id), "thread_id must be a string"
    assert String.starts_with?(thread_id, "thread_"), "thread_id must start with 'thread_'"
    assert String.length(thread_id) > 7, "thread_id must have content after prefix"
  end

  def assert_complete_turn_result(result) do
    assert %Codex.Turn.Result{} = result
    assert is_list(result.items)
    assert is_binary(result.final_response)
    assert %Codex.Events.Usage{} = result.usage
    assert result.usage.input_tokens > 0
  end

  def assert_events_in_order(events, expected_types) do
    actual_types = Enum.map(events, & &1.type)
    assert actual_types == expected_types,
      "Events out of order.\nExpected: #{inspect(expected_types)}\nActual: #{inspect(actual_types)}"
  end
end
```

## Error Testing

### Expected Errors

```elixir
test "returns error for invalid schema" do
  thread = %Codex.Thread{...}

  result = Codex.Thread.run(
    thread,
    "test",
    %Codex.Turn.Options{output_schema: "invalid"}
  )

  assert {:error, {:invalid_schema, _}} = result
end
```

### Error Propagation

```elixir
test "propagates turn failure from codex" do
  mock_script = create_failing_mock([
    ~s({"type":"thread.started","thread_id":"t1"}),
    ~s({"type":"turn.failed","error":{"message":"API error"}})
  ])

  codex_opts = %Codex.Options{codex_path_override: mock_script}
  {:ok, thread} = Codex.start_thread(codex_opts)

  result = Codex.Thread.run(thread, "test")

  assert {:error, {:turn_failed, error}} = result
  assert error.message == "API error"
end
```

### Error Recovery

```elixir
test "recovers from transient errors" do
  # Test retry logic, fallbacks, etc.
end
```

## Performance Testing

### Timing Assertions

```elixir
test "parses event in under 1ms" do
  event_json = ~s({"type":"thread.started","thread_id":"t1"})

  {time_us, result} = :timer.tc(fn ->
    Codex.Exec.Parser.parse_event(event_json)
  end)

  assert {:ok, _event} = result
  assert time_us < 1000, "Parsing took #{time_us}µs, expected < 1000µs"
end
```

### Load Testing

```elixir
test "handles 100 concurrent turns" do
  threads = for _ <- 1..100 do
    {:ok, thread} = Codex.start_thread()
    thread
  end

  tasks = for thread <- threads do
    Task.async(fn ->
      Codex.Thread.run(thread, "test")
    end)
  end

  results = Task.await_many(tasks, 30_000)

  assert Enum.all?(results, fn
    {:ok, _} -> true
    _ -> false
  end)
end
```

### Memory Testing

```elixir
test "streaming does not accumulate memory" do
  {:ok, thread} = Codex.start_thread()
  {:ok, result} = Codex.Thread.run_streamed(thread, "generate 1000 items")

  memory_before = :erlang.memory(:total)

  # Consume stream
  result
  |> Codex.RunResultStreaming.raw_events()
  |> Enum.each(fn _ -> :ok end)

  memory_after = :erlang.memory(:total)
  memory_delta = memory_after - memory_before

  # Should be roughly constant (< 1MB growth)
  assert memory_delta < 1_000_000,
    "Memory grew by #{memory_delta} bytes, expected < 1MB"
end
```

## CI/CD Integration

### GitHub Actions Workflow

```yaml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        elixir: ['1.14', '1.15', '1.16']
        otp: ['25', '26', '27']

    steps:
      - uses: actions/checkout@v3

      - name: Setup Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: ${{ matrix.elixir }}
          otp-version: ${{ matrix.otp }}

      - name: Restore dependencies cache
        uses: actions/cache@v3
        with:
          path: deps
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
          restore-keys: ${{ runner.os }}-mix-

      - name: Install dependencies
        run: mix deps.get

      - name: Run tests
        run: mix test --exclude live

      - name: Run integration tests
        run: mix test --only integration

      - name: Check coverage
        run: mix coveralls.github
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Run Dialyzer
        run: mix dialyzer

      - name: Run Credo
        run: mix credo --strict
```

### Local Pre-commit Checks

```bash
#!/bin/bash
# .git/hooks/pre-commit

echo "Running tests..."
mix test || exit 1

echo "Running Dialyzer..."
mix dialyzer || exit 1

echo "Running Credo..."
mix credo --strict || exit 1

echo "Checking coverage..."
mix coveralls || exit 1

echo "All checks passed!"
```

## Best Practices

### DO

1. **Write tests first** - TDD approach
2. **Use descriptive names** - Clearly state what's being tested
3. **Test one thing** - Single responsibility per test
4. **Use Supertester** - No `Process.sleep`
5. **Mock external deps** - Fast, deterministic tests
6. **Test edge cases** - Null, empty, invalid inputs
7. **Test errors** - Both expected and unexpected
8. **Keep tests simple** - Easy to understand and maintain
9. **Use fixtures** - DRY test data
10. **Run tests often** - Continuous feedback

### DON'T

1. **Don't use `Process.sleep`** - Use proper synchronization
2. **Don't test implementation** - Test behavior, not internals
3. **Don't share state** - Each test should be independent
4. **Don't skip failing tests** - Fix or remove them
5. **Don't write flaky tests** - Always reproducible
6. **Don't mock everything** - Test real integrations when possible
7. **Don't ignore warnings** - Keep Dialyzer clean
8. **Don't hardcode values** - Use variables and constants
9. **Don't write long tests** - Break into smaller tests
10. **Don't test external APIs** - Mock or tag as :live

## Troubleshooting

### Flaky Tests

**Symptoms**: Test sometimes passes, sometimes fails.

**Common Causes**:
- Using `Process.sleep` for synchronization
- Shared state between tests
- Race conditions
- Timing assumptions

**Solutions**:
- Use Supertester for proper sync
- Ensure `async: true` is safe
- Use `assert_receive` with timeout
- Check for shared resources

### Slow Tests

**Symptoms**: Tests take too long to run.

**Common Causes**:
- Real API calls
- Large data generation
- Inefficient algorithms
- Too much setup

**Solutions**:
- Mock external calls
- Use smaller test data
- Optimize code under test
- Cache expensive setup

### Low Coverage

**Symptoms**: Coverage below target.

**Common Causes**:
- Missing edge case tests
- Untested error paths
- Dead code

**Solutions**:
- Review coverage report
- Add missing tests
- Remove dead code
- Test all branches

## Conclusion

A comprehensive testing strategy is essential for building reliable, maintainable software. By following TDD principles, using Supertester for deterministic OTP testing, maintaining high coverage, and organizing tests clearly, we ensure the Elixir Codex SDK is production-ready and trustworthy.

Key takeaways:
- **Test first** - Write tests before implementation
- **No flakes** - Use proper synchronization, not sleeps
- **High coverage** - 95%+ with focus on critical paths
- **Fast feedback** - Quick test runs enable rapid iteration
- **Clear organization** - Well-structured tests are maintainable tests

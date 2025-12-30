# Prompt 05: Retry Logic and Backoff Implementation

**Target Version:** 0.4.5
**Date:** 2025-12-30
**Depends On:** None (standalone utility)

## Objective

Implement comprehensive retry logic with exponential backoff for the Codex SDK, applicable to transport, tool invocation, and MCP calls.

## Required Reading

1. **Canonical Implementation:**
   - `codex/codex-rs/codex-api/src/provider.rs` - Retry configuration
   - `codex/codex-rs/core/src/codex.rs` - Stream retry logic

2. **Elixir SDK:**
   - `lib/codex/thread/backoff.ex` - Existing backoff utilities
   - `lib/codex/transport.ex` - Transport behavior

## Implementation Tasks

### 1. Create `Codex.Retry` Module

Create `lib/codex/retry.ex`:

```elixir
defmodule Codex.Retry do
  @moduledoc """
  Retry logic with configurable backoff strategies.

  ## Strategies
    * `:exponential` - Exponential backoff (default)
    * `:linear` - Linear backoff
    * `:constant` - Fixed delay
    * `fun/1` - Custom backoff function

  ## Options
    * `:max_attempts` - Maximum retry attempts (default: 4)
    * `:base_delay_ms` - Base delay for backoff (default: 200)
    * `:max_delay_ms` - Maximum delay cap (default: 10_000)
    * `:jitter` - Add random jitter (default: true)
    * `:retry_if` - Predicate to determine if error is retryable

  ## Example

      Codex.Retry.with_retry(fn ->
        make_api_call()
      end, max_attempts: 3, strategy: :exponential)
  """

  @type strategy :: :exponential | :linear | :constant | (attempt :: pos_integer() -> non_neg_integer())
  @type opts :: [
    max_attempts: pos_integer(),
    base_delay_ms: non_neg_integer(),
    max_delay_ms: non_neg_integer(),
    jitter: boolean(),
    strategy: strategy(),
    retry_if: (term() -> boolean()),
    on_retry: (attempt :: pos_integer(), error :: term() -> :ok)
  ]

  @default_opts [
    max_attempts: 4,
    base_delay_ms: 200,
    max_delay_ms: 10_000,
    jitter: true,
    strategy: :exponential,
    retry_if: &retryable?/1,
    on_retry: fn _attempt, _error -> :ok end
  ]

  @doc """
  Executes function with retry logic.

  Returns `{:ok, result}` on success or `{:error, reason}` after all attempts exhausted.
  """
  @spec with_retry((() -> {:ok, term()} | {:error, term()}), opts()) ::
          {:ok, term()} | {:error, term()}
  def with_retry(fun, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)
    max_attempts = Keyword.fetch!(opts, :max_attempts)

    do_retry(fun, 1, max_attempts, opts, nil)
  end

  defp do_retry(fun, attempt, max_attempts, opts, _last_error) when attempt <= max_attempts do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} = error ->
        retry_if = Keyword.fetch!(opts, :retry_if)

        if attempt < max_attempts and retry_if.(reason) do
          on_retry = Keyword.fetch!(opts, :on_retry)
          on_retry.(attempt, reason)

          delay = calculate_delay(attempt, opts)
          Process.sleep(delay)
          do_retry(fun, attempt + 1, max_attempts, opts, error)
        else
          error
        end
    end
  end

  defp do_retry(_fun, _attempt, _max_attempts, _opts, last_error) do
    last_error
  end

  @doc """
  Calculates delay for given attempt using configured strategy.
  """
  @spec calculate_delay(pos_integer(), opts()) :: non_neg_integer()
  def calculate_delay(attempt, opts) do
    base = Keyword.fetch!(opts, :base_delay_ms)
    max = Keyword.fetch!(opts, :max_delay_ms)
    strategy = Keyword.fetch!(opts, :strategy)
    jitter? = Keyword.fetch!(opts, :jitter)

    delay = case strategy do
      :exponential -> exponential_delay(attempt, base)
      :linear -> linear_delay(attempt, base)
      :constant -> base
      fun when is_function(fun, 1) -> fun.(attempt)
    end

    delay = min(delay, max)

    if jitter? do
      add_jitter(delay)
    else
      delay
    end
  end

  defp exponential_delay(attempt, base) do
    round(base * :math.pow(2, attempt - 1))
  end

  defp linear_delay(attempt, base) do
    base * attempt
  end

  defp add_jitter(delay) do
    # Add up to 25% random jitter
    jitter = :rand.uniform(round(delay * 0.25))
    delay + jitter
  end

  @doc """
  Default predicate for retryable errors.

  Retries on:
  - Timeout errors
  - Connection errors
  - 5xx HTTP errors
  - Rate limit errors (429)

  Does NOT retry on:
  - Authentication errors
  - Invalid request errors
  - Context window exceeded
  """
  @spec retryable?(term()) :: boolean()
  def retryable?(:timeout), do: true
  def retryable?(:econnrefused), do: true
  def retryable?(:econnreset), do: true
  def retryable?({:http_error, status}) when status >= 500, do: true
  def retryable?({:http_error, 429}), do: true
  def retryable?(:stream_reset), do: true
  def retryable?(:stream_timeout), do: true
  def retryable?(%{__struct__: Codex.TransportError, retryable?: true}), do: true
  def retryable?(_), do: false

  @doc """
  Wraps an async stream with retry logic.

  For streaming operations, retries the entire stream from the beginning.
  """
  @spec with_stream_retry((() -> Enumerable.t()), opts()) :: Enumerable.t()
  def with_stream_retry(stream_fun, opts \\ []) do
    Stream.resource(
      fn ->
        opts = Keyword.merge(@default_opts, opts)
        {:starting, stream_fun, 1, opts}
      end,
      fn
        {:starting, fun, attempt, opts} ->
          try do
            stream = fun.()
            {[], {:streaming, stream, attempt, opts}}
          rescue
            e ->
              handle_stream_error(e, fun, attempt, opts)
          end

        {:streaming, stream, attempt, opts} ->
          case Enum.take(stream, 1) do
            [] -> {:halt, :done}
            [item] -> {[item], {:streaming, stream, attempt, opts}}
          end

        :done -> {:halt, :done}
      end,
      fn _ -> :ok end
    )
  end

  defp handle_stream_error(error, fun, attempt, opts) do
    max_attempts = Keyword.fetch!(opts, :max_attempts)
    retry_if = Keyword.fetch!(opts, :retry_if)

    if attempt < max_attempts and retry_if.(error) do
      on_retry = Keyword.fetch!(opts, :on_retry)
      on_retry.(attempt, error)

      delay = calculate_delay(attempt, opts)
      Process.sleep(delay)
      {[], {:starting, fun, attempt + 1, opts}}
    else
      raise error
    end
  end
end
```

### 2. Integrate with Transport Layer

Update `lib/codex/transport/exec_jsonl.ex` to use retry:

```elixir
defp run_with_retry(input, opts) do
  retry_opts = Keyword.get(opts, :retry, [])

  Codex.Retry.with_retry(fn ->
    do_run(input, opts)
  end, retry_opts)
end
```

### 3. Add Retry Configuration to Options

Update `lib/codex/options.ex`:

```elixir
defstruct [
  # ... existing fields
  retry_max_attempts: 4,
  retry_base_delay_ms: 200,
  retry_strategy: :exponential
]
```

## Test Requirements (TDD)

### Unit Tests (`test/codex/retry_test.exs`)

```elixir
defmodule Codex.RetryTest do
  use ExUnit.Case, async: true

  describe "with_retry/2" do
    test "returns success on first attempt" do
      assert {:ok, :success} = Codex.Retry.with_retry(fn -> {:ok, :success} end)
    end

    test "retries on transient error" do
      counter = :counters.new(1, [])

      result = Codex.Retry.with_retry(fn ->
        count = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)

        if count < 2 do
          {:error, :timeout}
        else
          {:ok, :success}
        end
      end, max_attempts: 3)

      assert {:ok, :success} = result
      assert :counters.get(counter, 1) == 2
    end

    test "respects max_attempts" do
      counter = :counters.new(1, [])

      result = Codex.Retry.with_retry(fn ->
        :counters.add(counter, 1, 1)
        {:error, :timeout}
      end, max_attempts: 3)

      assert {:error, :timeout} = result
      assert :counters.get(counter, 1) == 3
    end

    test "does not retry non-retryable errors" do
      counter = :counters.new(1, [])

      result = Codex.Retry.with_retry(fn ->
        :counters.add(counter, 1, 1)
        {:error, :auth_failed}
      end, max_attempts: 3)

      assert {:error, :auth_failed} = result
      assert :counters.get(counter, 1) == 1
    end

    test "calls on_retry callback" do
      callback_counter = :counters.new(1, [])

      Codex.Retry.with_retry(
        fn -> {:error, :timeout} end,
        max_attempts: 3,
        on_retry: fn _attempt, _error ->
          :counters.add(callback_counter, 1, 1)
        end
      )

      assert :counters.get(callback_counter, 1) == 2
    end
  end

  describe "calculate_delay/2" do
    test "exponential backoff doubles each attempt" do
      opts = [base_delay_ms: 100, max_delay_ms: 10_000, strategy: :exponential, jitter: false]

      assert Codex.Retry.calculate_delay(1, opts) == 100
      assert Codex.Retry.calculate_delay(2, opts) == 200
      assert Codex.Retry.calculate_delay(3, opts) == 400
    end

    test "respects max_delay_ms" do
      opts = [base_delay_ms: 100, max_delay_ms: 500, strategy: :exponential, jitter: false]

      assert Codex.Retry.calculate_delay(10, opts) == 500
    end

    test "adds jitter when enabled" do
      opts = [base_delay_ms: 100, max_delay_ms: 10_000, strategy: :exponential, jitter: true]

      delays = for _ <- 1..10, do: Codex.Retry.calculate_delay(1, opts)
      # With jitter, not all delays should be the same
      assert length(Enum.uniq(delays)) > 1
    end
  end

  describe "retryable?/1" do
    test "timeout is retryable" do
      assert Codex.Retry.retryable?(:timeout)
    end

    test "connection refused is retryable" do
      assert Codex.Retry.retryable?(:econnrefused)
    end

    test "5xx errors are retryable" do
      assert Codex.Retry.retryable?({:http_error, 500})
      assert Codex.Retry.retryable?({:http_error, 503})
    end

    test "429 rate limit is retryable" do
      assert Codex.Retry.retryable?({:http_error, 429})
    end

    test "auth errors are not retryable" do
      refute Codex.Retry.retryable?(:auth_failed)
      refute Codex.Retry.retryable?({:http_error, 401})
    end
  end
end
```

## Verification Criteria

1. [ ] All tests pass
2. [ ] No warnings
3. [ ] No dialyzer errors
4. [ ] No credo issues
5. [ ] Integration with existing transport

## Update Requirements

### CHANGELOG.md

Add to the existing `## [0.4.5] - 2025-12-30` section:
```markdown
- Comprehensive retry logic with `Codex.Retry`
- Exponential, linear, and constant backoff strategies
- Jitter support for retry delays
- Customizable retry predicates
- on_retry callbacks for logging/metrics
- Stream retry support for streaming operations
```

### README.md

Add retry configuration section.

### Examples

Create `examples/retry_example.exs` demonstrating retry usage.

# Codex.Retry Usage Examples
#
# Run with: mix run examples/retry_example.exs
#
# This script demonstrates the various retry strategies and configurations
# available in Codex.Retry for handling transient failures.

alias Codex.Retry

IO.puts("""
=== Codex.Retry Examples ===

This example demonstrates retry logic with different backoff strategies.
""")

# -----------------------------------------------------------------------------
# Example 1: Basic retry with defaults
# -----------------------------------------------------------------------------
IO.puts("\n1. Basic retry with defaults")
IO.puts("   (4 max attempts, 200ms base delay, exponential backoff)")

counter = :counters.new(1, [])

result =
  Retry.with_retry(
    fn ->
      attempt = :counters.get(counter, 1) + 1
      :counters.add(counter, 1, 1)
      IO.puts("   Attempt #{attempt}...")

      if attempt < 3 do
        {:error, :timeout}
      else
        {:ok, "success!"}
      end
    end,
    # Using shorter delays for demo
    base_delay_ms: 50
  )

case result do
  {:ok, value} -> IO.puts("   Result: #{value}")
  {:error, reason} -> IO.puts("   Failed: #{inspect(reason)}")
end

# -----------------------------------------------------------------------------
# Example 2: Linear backoff strategy
# -----------------------------------------------------------------------------
IO.puts("\n2. Linear backoff strategy")
IO.puts("   (delays: 100ms, 200ms, 300ms, ...)")

counter = :counters.new(1, [])
start_time = System.monotonic_time(:millisecond)

Retry.with_retry(
  fn ->
    attempt = :counters.get(counter, 1) + 1
    :counters.add(counter, 1, 1)
    elapsed = System.monotonic_time(:millisecond) - start_time
    IO.puts("   Attempt #{attempt} at #{elapsed}ms")

    if attempt < 4 do
      {:error, :timeout}
    else
      {:ok, :done}
    end
  end,
  max_attempts: 5,
  base_delay_ms: 100,
  strategy: :linear,
  jitter: false
)

# -----------------------------------------------------------------------------
# Example 3: Constant delay strategy
# -----------------------------------------------------------------------------
IO.puts("\n3. Constant delay strategy")
IO.puts("   (fixed 50ms delay between attempts)")

counter = :counters.new(1, [])
start_time = System.monotonic_time(:millisecond)

Retry.with_retry(
  fn ->
    attempt = :counters.get(counter, 1) + 1
    :counters.add(counter, 1, 1)
    elapsed = System.monotonic_time(:millisecond) - start_time
    IO.puts("   Attempt #{attempt} at #{elapsed}ms")

    if attempt < 3 do
      {:error, :econnrefused}
    else
      {:ok, :connected}
    end
  end,
  max_attempts: 4,
  base_delay_ms: 50,
  strategy: :constant,
  jitter: false
)

# -----------------------------------------------------------------------------
# Example 4: Custom backoff function
# -----------------------------------------------------------------------------
IO.puts("\n4. Custom backoff function (Fibonacci-like)")

# Custom strategy: Fibonacci-like delays
fibonacci_delay = fn attempt ->
  fib = fn fib, n ->
    case n do
      1 -> 50
      2 -> 50
      n -> fib.(fib, n - 1) + fib.(fib, n - 2)
    end
  end

  fib.(fib, attempt)
end

counter = :counters.new(1, [])
start_time = System.monotonic_time(:millisecond)

Retry.with_retry(
  fn ->
    attempt = :counters.get(counter, 1) + 1
    :counters.add(counter, 1, 1)
    elapsed = System.monotonic_time(:millisecond) - start_time
    IO.puts("   Attempt #{attempt} at #{elapsed}ms")

    if attempt < 5 do
      {:error, :timeout}
    else
      {:ok, :done}
    end
  end,
  max_attempts: 6,
  strategy: fibonacci_delay,
  jitter: false
)

# -----------------------------------------------------------------------------
# Example 5: on_retry callback for logging
# -----------------------------------------------------------------------------
IO.puts("\n5. Using on_retry callback for logging")

counter = :counters.new(1, [])

Retry.with_retry(
  fn ->
    attempt = :counters.get(counter, 1) + 1
    :counters.add(counter, 1, 1)

    if attempt < 3 do
      {:error, {:http_error, 503}}
    else
      {:ok, :service_available}
    end
  end,
  max_attempts: 4,
  base_delay_ms: 30,
  jitter: false,
  on_retry: fn attempt, error ->
    IO.puts("   [WARN] Retry #{attempt + 1} after error: #{inspect(error)}")
  end
)

# -----------------------------------------------------------------------------
# Example 6: Custom retry_if predicate
# -----------------------------------------------------------------------------
IO.puts("\n6. Custom retry_if predicate")
IO.puts("   (only retry on :retriable_error)")

counter = :counters.new(1, [])

# Custom predicate that only retries specific errors
custom_retry_if = fn
  :retriable_error -> true
  _ -> false
end

result =
  Retry.with_retry(
    fn ->
      attempt = :counters.get(counter, 1) + 1
      :counters.add(counter, 1, 1)
      IO.puts("   Attempt #{attempt}...")

      case attempt do
        1 -> {:error, :retriable_error}
        2 -> {:error, :retriable_error}
        _ -> {:ok, "recovered"}
      end
    end,
    max_attempts: 5,
    base_delay_ms: 20,
    jitter: false,
    retry_if: custom_retry_if
  )

IO.puts("   Result: #{inspect(result)}")

# Non-retriable error demonstration
IO.puts("\n   Now with non-retriable error:")
counter = :counters.new(1, [])

result =
  Retry.with_retry(
    fn ->
      attempt = :counters.get(counter, 1) + 1
      :counters.add(counter, 1, 1)
      IO.puts("   Attempt #{attempt}...")
      {:error, :permanent_error}
    end,
    max_attempts: 5,
    base_delay_ms: 20,
    retry_if: custom_retry_if
  )

IO.puts("   Result: #{inspect(result)} (no retries for permanent errors)")

# -----------------------------------------------------------------------------
# Example 7: Inspecting default retryable errors
# -----------------------------------------------------------------------------
IO.puts("\n7. Default retryable error types")

errors = [
  :timeout,
  :econnrefused,
  :econnreset,
  :closed,
  :nxdomain,
  {:http_error, 500},
  {:http_error, 502},
  {:http_error, 503},
  {:http_error, 429},
  {:http_error, 400},
  {:http_error, 401},
  :stream_reset,
  :auth_failed,
  :unknown_error
]

for error <- errors do
  status = if Retry.retryable?(error), do: "✓ retryable", else: "✗ not retryable"
  IO.puts("   #{inspect(error)} -> #{status}")
end

# -----------------------------------------------------------------------------
# Example 8: Calculate delay for different strategies
# -----------------------------------------------------------------------------
IO.puts("\n8. Delay calculations for different strategies")

strategies = [:exponential, :linear, :constant]

for strategy <- strategies do
  IO.puts("\n   #{strategy}:")
  opts = [base_delay_ms: 100, max_delay_ms: 10_000, strategy: strategy, jitter: false]

  for attempt <- 1..5 do
    delay = Retry.calculate_delay(attempt, opts)
    IO.puts("     Attempt #{attempt}: #{delay}ms")
  end
end

# -----------------------------------------------------------------------------
# Example 9: Stream retry
# -----------------------------------------------------------------------------
IO.puts("\n9. Stream retry example")

counter = :counters.new(1, [])

stream =
  Retry.with_stream_retry(
    fn ->
      attempt = :counters.get(counter, 1) + 1
      :counters.add(counter, 1, 1)
      IO.puts("   Creating stream (attempt #{attempt})...")

      if attempt < 2 do
        raise "Stream creation failed!"
      else
        Stream.map(1..3, fn x ->
          IO.puts("   Yielding item: #{x}")
          x * 10
        end)
      end
    end,
    max_attempts: 3,
    base_delay_ms: 50,
    jitter: false,
    retry_if: fn _ -> true end
  )

IO.puts("   Consuming stream...")
result = Enum.to_list(stream)
IO.puts("   Stream result: #{inspect(result)}")

# -----------------------------------------------------------------------------
# Example 10: Max delay cap demonstration
# -----------------------------------------------------------------------------
IO.puts("\n10. Max delay cap demonstration")
IO.puts("    (exponential with 500ms cap)")

opts = [base_delay_ms: 100, max_delay_ms: 500, strategy: :exponential, jitter: false]

for attempt <- 1..10 do
  delay = Retry.calculate_delay(attempt, opts)
  uncapped = round(100 * :math.pow(2, attempt - 1))
  IO.puts("    Attempt #{attempt}: #{delay}ms (uncapped would be #{uncapped}ms)")
end

IO.puts("""

=== Examples Complete ===

Key takeaways:
- Use exponential backoff for most network/API calls (default)
- Use linear backoff when you want predictable delay growth
- Use constant backoff for simple fixed-interval retries
- Use custom strategies for specialized requirements
- Always set appropriate max_delay_ms caps
- Use jitter (enabled by default) to prevent thundering herd
- Use on_retry callbacks for observability/logging
""")

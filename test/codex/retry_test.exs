defmodule Codex.RetryTest do
  use ExUnit.Case, async: true

  alias Codex.Retry
  alias Codex.TransportError

  describe "with_retry/2" do
    test "returns success on first attempt" do
      assert {:ok, :success} = Retry.with_retry(fn -> {:ok, :success} end)
    end

    test "retries on transient error and eventually succeeds" do
      counter = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            count = :counters.get(counter, 1)
            :counters.add(counter, 1, 1)

            if count < 2 do
              {:error, :timeout}
            else
              {:ok, :success}
            end
          end,
          max_attempts: 3,
          base_delay_ms: 1,
          jitter: false
        )

      assert {:ok, :success} = result
      assert :counters.get(counter, 1) == 3
    end

    test "respects max_attempts" do
      counter = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(counter, 1, 1)
            {:error, :timeout}
          end,
          max_attempts: 3,
          base_delay_ms: 1,
          jitter: false
        )

      assert {:error, :timeout} = result
      assert :counters.get(counter, 1) == 3
    end

    test "does not retry non-retryable errors" do
      counter = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(counter, 1, 1)
            {:error, :auth_failed}
          end,
          max_attempts: 3,
          base_delay_ms: 1,
          jitter: false
        )

      assert {:error, :auth_failed} = result
      assert :counters.get(counter, 1) == 1
    end

    test "calls on_retry callback before each retry" do
      callback_log = :ets.new(:callback_log, [:ordered_set, :public])

      Retry.with_retry(
        fn -> {:error, :timeout} end,
        max_attempts: 3,
        base_delay_ms: 1,
        jitter: false,
        on_retry: fn attempt, error ->
          :ets.insert(callback_log, {attempt, error})
        end
      )

      # Should have been called twice (before retry 2 and before retry 3)
      assert :ets.tab2list(callback_log) == [{1, :timeout}, {2, :timeout}]
      :ets.delete(callback_log)
    end

    test "uses custom retry_if predicate" do
      counter = :counters.new(1, [])

      # Custom predicate that retries on :custom_error
      custom_retry_if = fn
        :custom_error -> true
        _ -> false
      end

      result =
        Retry.with_retry(
          fn ->
            count = :counters.get(counter, 1)
            :counters.add(counter, 1, 1)

            if count < 2, do: {:error, :custom_error}, else: {:ok, :done}
          end,
          max_attempts: 5,
          base_delay_ms: 1,
          jitter: false,
          retry_if: custom_retry_if
        )

      assert {:ok, :done} = result
      assert :counters.get(counter, 1) == 3
    end

    test "with max_attempts of 1 never retries" do
      counter = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(counter, 1, 1)
            {:error, :timeout}
          end,
          max_attempts: 1,
          base_delay_ms: 1,
          jitter: false
        )

      assert {:error, :timeout} = result
      assert :counters.get(counter, 1) == 1
    end
  end

  describe "calculate_delay/2" do
    test "exponential backoff doubles each attempt" do
      opts = [base_delay_ms: 100, max_delay_ms: 10_000, strategy: :exponential, jitter: false]

      assert Retry.calculate_delay(1, opts) == 100
      assert Retry.calculate_delay(2, opts) == 200
      assert Retry.calculate_delay(3, opts) == 400
      assert Retry.calculate_delay(4, opts) == 800
      assert Retry.calculate_delay(5, opts) == 1600
    end

    test "linear backoff increases linearly" do
      opts = [base_delay_ms: 100, max_delay_ms: 10_000, strategy: :linear, jitter: false]

      assert Retry.calculate_delay(1, opts) == 100
      assert Retry.calculate_delay(2, opts) == 200
      assert Retry.calculate_delay(3, opts) == 300
      assert Retry.calculate_delay(4, opts) == 400
    end

    test "constant backoff returns same value" do
      opts = [base_delay_ms: 100, max_delay_ms: 10_000, strategy: :constant, jitter: false]

      assert Retry.calculate_delay(1, opts) == 100
      assert Retry.calculate_delay(2, opts) == 100
      assert Retry.calculate_delay(5, opts) == 100
    end

    test "custom strategy function" do
      custom_fn = fn attempt -> attempt * 50 end
      opts = [base_delay_ms: 100, max_delay_ms: 10_000, strategy: custom_fn, jitter: false]

      assert Retry.calculate_delay(1, opts) == 50
      assert Retry.calculate_delay(2, opts) == 100
      assert Retry.calculate_delay(3, opts) == 150
    end

    test "respects max_delay_ms" do
      opts = [base_delay_ms: 100, max_delay_ms: 500, strategy: :exponential, jitter: false]

      assert Retry.calculate_delay(10, opts) == 500
    end

    test "adds jitter when enabled" do
      opts = [base_delay_ms: 100, max_delay_ms: 10_000, strategy: :exponential, jitter: true]

      # Run multiple times to verify jitter adds randomness
      delays = for _ <- 1..20, do: Retry.calculate_delay(1, opts)

      # Base is 100, jitter adds up to 25% (0-25), so range is 100-125
      assert Enum.all?(delays, &(&1 >= 100 and &1 <= 125))
      # With jitter, not all delays should be exactly the same
      assert length(Enum.uniq(delays)) > 1
    end

    test "handles zero base_delay_ms" do
      opts = [base_delay_ms: 0, max_delay_ms: 10_000, strategy: :exponential, jitter: false]

      assert Retry.calculate_delay(1, opts) == 0
      assert Retry.calculate_delay(5, opts) == 0
    end

    test "jitter handles zero delay gracefully" do
      opts = [base_delay_ms: 0, max_delay_ms: 10_000, strategy: :constant, jitter: true]

      assert Retry.calculate_delay(1, opts) == 0
    end
  end

  describe "retryable?/1" do
    test "timeout is retryable" do
      assert Retry.retryable?(:timeout)
    end

    test "connection refused is retryable" do
      assert Retry.retryable?(:econnrefused)
    end

    test "connection reset is retryable" do
      assert Retry.retryable?(:econnreset)
    end

    test "closed connection is retryable" do
      assert Retry.retryable?(:closed)
    end

    test "nxdomain is retryable" do
      assert Retry.retryable?(:nxdomain)
    end

    test "5xx HTTP errors are retryable" do
      assert Retry.retryable?({:http_error, 500})
      assert Retry.retryable?({:http_error, 502})
      assert Retry.retryable?({:http_error, 503})
      assert Retry.retryable?({:http_error, 504})
      assert Retry.retryable?({:http_error, 599})
    end

    test "429 rate limit is retryable" do
      assert Retry.retryable?({:http_error, 429})
    end

    test "stream errors are retryable" do
      assert Retry.retryable?(:stream_reset)
      assert Retry.retryable?(:stream_timeout)
    end

    test "TransportError with retryable? true is retryable" do
      error = TransportError.new(143, retryable?: true)
      assert Retry.retryable?(error)
    end

    test "TransportError with retryable? false is not retryable" do
      error = TransportError.new(1, retryable?: false)
      refute Retry.retryable?(error)
    end

    test "4xx client errors are not retryable (except 429)" do
      refute Retry.retryable?({:http_error, 400})
      refute Retry.retryable?({:http_error, 401})
      refute Retry.retryable?({:http_error, 403})
      refute Retry.retryable?({:http_error, 404})
    end

    test "auth errors are not retryable" do
      refute Retry.retryable?(:auth_failed)
      refute Retry.retryable?(:invalid_api_key)
    end

    test "unknown errors are not retryable" do
      refute Retry.retryable?(:unknown_error)
      refute Retry.retryable?("some string error")
      refute Retry.retryable?(%{some: "map"})
    end
  end

  describe "with_stream_retry/2" do
    test "returns stream that produces items on success" do
      stream =
        Retry.with_stream_retry(
          fn -> [1, 2, 3] end,
          max_attempts: 3,
          base_delay_ms: 1,
          jitter: false
        )

      assert Enum.to_list(stream) == [1, 2, 3]
    end

    test "retries stream creation on transient error" do
      counter = :counters.new(1, [])

      stream =
        Retry.with_stream_retry(
          fn ->
            count = :counters.get(counter, 1)
            :counters.add(counter, 1, 1)

            if count < 2 do
              raise "timeout"
            else
              [1, 2, 3]
            end
          end,
          max_attempts: 3,
          base_delay_ms: 1,
          jitter: false,
          retry_if: fn _ -> true end
        )

      assert Enum.to_list(stream) == [1, 2, 3]
      assert :counters.get(counter, 1) == 3
    end

    test "raises after max attempts exhausted" do
      stream =
        Retry.with_stream_retry(
          fn -> raise "persistent error" end,
          max_attempts: 2,
          base_delay_ms: 1,
          jitter: false,
          retry_if: fn _ -> true end
        )

      assert_raise RuntimeError, "persistent error", fn ->
        Enum.to_list(stream)
      end
    end
  end

  describe "default_opts/0" do
    test "returns expected defaults" do
      opts = Retry.default_opts()

      assert opts[:max_attempts] == 4
      assert opts[:base_delay_ms] == 200
      assert opts[:max_delay_ms] == 10_000
      assert opts[:jitter] == true
      assert opts[:strategy] == :exponential
      assert is_function(opts[:retry_if], 1)
      assert is_function(opts[:on_retry], 2)
    end
  end

  describe "TransportError retryable? inference" do
    test "SIGTERM exit is retryable" do
      error = TransportError.new(128 + 15)
      assert error.retryable?
    end

    test "SIGKILL exit is retryable" do
      error = TransportError.new(128 + 9)
      assert error.retryable?
    end

    test "SIGPIPE exit is retryable" do
      error = TransportError.new(128 + 13)
      assert error.retryable?
    end

    test "EX_TEMPFAIL (75) is retryable" do
      error = TransportError.new(75)
      assert error.retryable?
    end

    test "EX_UNAVAILABLE (69) is retryable" do
      error = TransportError.new(69)
      assert error.retryable?
    end

    test "normal exit (0) is not retryable" do
      error = TransportError.new(0)
      refute error.retryable?
    end

    test "generic error (1) is not retryable" do
      error = TransportError.new(1)
      refute error.retryable?
    end

    test "explicit retryable? overrides inference" do
      error = TransportError.new(1, retryable?: true)
      assert error.retryable?

      error = TransportError.new(143, retryable?: false)
      refute error.retryable?
    end
  end

  describe "integration scenarios" do
    test "retries with exponential backoff and succeeds on third attempt" do
      attempt_times = :ets.new(:attempt_times, [:ordered_set, :public])

      result =
        Retry.with_retry(
          fn ->
            now = System.monotonic_time(:millisecond)
            count = :ets.info(attempt_times, :size)
            :ets.insert(attempt_times, {count, now})

            if count < 2, do: {:error, :timeout}, else: {:ok, :success}
          end,
          max_attempts: 4,
          base_delay_ms: 10,
          jitter: false,
          strategy: :exponential
        )

      assert {:ok, :success} = result

      times = :ets.tab2list(attempt_times)
      assert length(times) == 3

      # Verify delays between attempts
      [{_, t1}, {_, t2}, {_, t3}] = times

      # First delay should be ~10ms (base)
      assert_in_delta t2 - t1, 10, 10

      # Second delay should be ~20ms (base * 2)
      assert_in_delta t3 - t2, 20, 10

      :ets.delete(attempt_times)
    end

    test "different strategies produce different delay patterns" do
      exponential_delay_sum =
        Enum.reduce(1..3, 0, fn attempt, acc ->
          opts = [base_delay_ms: 100, max_delay_ms: 10_000, strategy: :exponential, jitter: false]
          acc + Retry.calculate_delay(attempt, opts)
        end)

      linear_delay_sum =
        Enum.reduce(1..3, 0, fn attempt, acc ->
          opts = [base_delay_ms: 100, max_delay_ms: 10_000, strategy: :linear, jitter: false]
          acc + Retry.calculate_delay(attempt, opts)
        end)

      constant_delay_sum =
        Enum.reduce(1..3, 0, fn attempt, acc ->
          opts = [base_delay_ms: 100, max_delay_ms: 10_000, strategy: :constant, jitter: false]
          acc + Retry.calculate_delay(attempt, opts)
        end)

      # Exponential: 100 + 200 + 400 = 700
      assert exponential_delay_sum == 700

      # Linear: 100 + 200 + 300 = 600
      assert linear_delay_sum == 600

      # Constant: 100 + 100 + 100 = 300
      assert constant_delay_sum == 300
    end
  end
end

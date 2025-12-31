defmodule Codex.RateLimitTest do
  use ExUnit.Case, async: true

  alias Codex.{Error, RateLimit}

  describe "detect/1" do
    test "detects rate limit error from Codex.Error" do
      error = Error.rate_limit("Rate limited", retry_after_ms: 30_000)
      assert {:rate_limited, info} = RateLimit.detect({:error, error})
      assert info.retry_after_ms == 30_000
      assert info.message == "Rate limited"
      assert info.source == :codex_error
    end

    test "detects rate limit error without retry_after" do
      error = Error.rate_limit("Rate limited")
      assert {:rate_limited, info} = RateLimit.detect({:error, error})
      assert info.retry_after_ms == nil
    end

    test "detects HTTP 429 with Retry-After header" do
      response = %{status: 429, headers: %{"retry-after" => "60"}}
      assert {:rate_limited, info} = RateLimit.detect({:error, response})
      assert info.retry_after_ms == 60_000
      assert info.source == :http_429
    end

    test "detects HTTP 429 with Retry-After header (capitalized)" do
      response = %{status: 429, headers: %{"Retry-After" => "120"}}
      assert {:rate_limited, info} = RateLimit.detect({:error, response})
      assert info.retry_after_ms == 120_000
    end

    test "detects HTTP 429 with x-ratelimit-reset-after header" do
      response = %{status: 429, headers: %{"x-ratelimit-reset-after" => "30"}}
      assert {:rate_limited, info} = RateLimit.detect({:error, response})
      assert info.retry_after_ms == 30_000
    end

    test "detects HTTP 429 with headers as list" do
      response = %{status: 429, headers: [{"Retry-After", "45"}]}
      assert {:rate_limited, info} = RateLimit.detect({:error, response})
      assert info.retry_after_ms == 45_000
    end

    test "detects HTTP 429 without headers" do
      response = %{status: 429}
      assert {:rate_limited, info} = RateLimit.detect({:error, response})
      assert info.retry_after_ms == nil
      assert info.source == :http_429
    end

    test "detects API rate_limit_exceeded error" do
      body = %{"error" => %{"code" => "rate_limit_exceeded"}}
      assert {:rate_limited, info} = RateLimit.detect({:error, body})
      assert info.source == :api_error
      assert info.body == body
    end

    test "detects API rate_limit error" do
      body = %{"error" => %{"code" => "rate_limit"}}
      assert {:rate_limited, _info} = RateLimit.detect({:error, body})
    end

    test "detects API rate_limit_error code" do
      body = %{"error" => %{"code" => "rate_limit_error"}}
      assert {:rate_limited, _info} = RateLimit.detect({:error, body})
    end

    test "detects http_error tuple with 429" do
      assert {:rate_limited, info} = RateLimit.detect({:error, {:http_error, 429}})
      assert info.source == :http_error_tuple
    end

    test "returns :ok for non-rate-limit errors" do
      assert :ok = RateLimit.detect({:error, :timeout})
      assert :ok = RateLimit.detect({:error, :econnrefused})
      assert :ok = RateLimit.detect({:error, {:http_error, 500}})
      assert :ok = RateLimit.detect({:error, %{status: 500}})
    end

    test "returns :ok for success responses" do
      assert :ok = RateLimit.detect({:ok, :success})
      assert :ok = RateLimit.detect({:ok, %{data: "result"}})
    end

    test "returns :ok for other error codes" do
      body = %{"error" => %{"code" => "invalid_request"}}
      assert :ok = RateLimit.detect({:error, body})
    end
  end

  describe "calculate_delay/2" do
    test "uses explicit retry_after when present" do
      info = %{retry_after_ms: 45_000}
      assert RateLimit.calculate_delay(info) == 45_000
    end

    test "uses explicit retry_after on subsequent attempts" do
      info = %{retry_after_ms: 30_000}
      assert RateLimit.calculate_delay(info, 1) == 30_000
      assert RateLimit.calculate_delay(info, 2) == 30_000
      assert RateLimit.calculate_delay(info, 3) == 30_000
    end

    test "ignores zero retry_after and uses default" do
      info = %{retry_after_ms: 0}
      delay = RateLimit.calculate_delay(info, 1)
      assert delay > 0
    end

    test "ignores nil retry_after and uses default" do
      info = %{retry_after_ms: nil}
      delay = RateLimit.calculate_delay(info, 1)
      assert delay > 0
    end

    test "uses default with exponential backoff when no hint" do
      info = %{}
      delay1 = RateLimit.calculate_delay(info, 1)
      delay2 = RateLimit.calculate_delay(info, 2)
      delay3 = RateLimit.calculate_delay(info, 3)

      assert delay1 > 0
      assert delay2 > delay1
      assert delay3 > delay2
    end

    test "respects max delay cap" do
      info = %{}
      # With default multiplier of 2.0 and base of 60_000,
      # after many attempts it should cap at max_delay
      delay = RateLimit.calculate_delay(info, 100)
      max_delay = Application.get_env(:codex_sdk, :rate_limit_max_delay_ms, 300_000)
      assert delay <= max_delay
    end
  end

  describe "parse_retry_after/1" do
    test "parses integer seconds from map headers" do
      assert RateLimit.parse_retry_after(%{headers: %{"retry-after" => "60"}}) == 60_000
    end

    test "parses from Retry-After (capitalized)" do
      assert RateLimit.parse_retry_after(%{headers: %{"Retry-After" => "30"}}) == 30_000
    end

    test "parses from x-ratelimit-reset-after" do
      assert RateLimit.parse_retry_after(%{headers: %{"x-ratelimit-reset-after" => "45"}}) ==
               45_000
    end

    test "parses integer value directly" do
      assert RateLimit.parse_retry_after(%{headers: %{"retry-after" => 90}}) == 90_000
    end

    test "parses from list headers" do
      assert RateLimit.parse_retry_after(%{headers: [{"retry-after", "120"}]}) == 120_000
      assert RateLimit.parse_retry_after(%{headers: [{"Retry-After", "60"}]}) == 60_000
    end

    test "returns nil for missing headers" do
      assert RateLimit.parse_retry_after(%{}) == nil
      assert RateLimit.parse_retry_after(%{headers: %{}}) == nil
      assert RateLimit.parse_retry_after(%{headers: []}) == nil
    end

    test "returns nil for invalid values" do
      assert RateLimit.parse_retry_after(%{headers: %{"retry-after" => "invalid"}}) == nil
    end
  end

  describe "handle/2" do
    test "sleeps for calculated delay" do
      info = %{retry_after_ms: 10}
      start = System.monotonic_time(:millisecond)
      RateLimit.handle(info, attempt: 1)
      elapsed = System.monotonic_time(:millisecond) - start
      assert elapsed >= 10
    end

    test "emits telemetry event" do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:codex, :rate_limit, :rate_limited]
        ])

      info = %{retry_after_ms: 1}
      RateLimit.handle(info, attempt: 2)

      assert_receive {[:codex, :rate_limit, :rate_limited], ^ref, %{system_time: _},
                      %{delay_ms: 1, attempt: 2, info: ^info}}
    end
  end

  describe "with_rate_limit_handling/2" do
    test "returns success immediately on non-rate-limited response" do
      result =
        RateLimit.with_rate_limit_handling(fn ->
          {:ok, :success}
        end)

      assert result == {:ok, :success}
    end

    test "returns error immediately on non-rate-limited error" do
      result =
        RateLimit.with_rate_limit_handling(fn ->
          {:error, :some_error}
        end)

      assert result == {:error, :some_error}
    end

    test "retries on rate limit and succeeds" do
      counter = :counters.new(1, [])

      result =
        RateLimit.with_rate_limit_handling(
          fn ->
            count = :counters.get(counter, 1)
            :counters.add(counter, 1, 1)

            if count < 2 do
              # Use Error struct with small retry_after_ms for fast test
              error = Error.rate_limit("Rate limited", retry_after_ms: 10)
              {:error, error}
            else
              {:ok, :success}
            end
          end,
          max_attempts: 3
        )

      assert {:ok, :success} = result
      assert :counters.get(counter, 1) == 3
    end

    test "gives up after max_attempts" do
      counter = :counters.new(1, [])

      result =
        RateLimit.with_rate_limit_handling(
          fn ->
            :counters.add(counter, 1, 1)
            # Use Error struct with small retry_after_ms for fast test
            error = Error.rate_limit("Rate limited", retry_after_ms: 10)
            {:error, error}
          end,
          max_attempts: 2
        )

      assert {:error, %Error{kind: :rate_limit}} = result
      # Should have attempted exactly 2 times
      assert :counters.get(counter, 1) == 2
    end

    test "respects retry_after_ms from API" do
      counter = :counters.new(1, [])
      start = System.monotonic_time(:millisecond)

      result =
        RateLimit.with_rate_limit_handling(
          fn ->
            count = :counters.get(counter, 1)
            :counters.add(counter, 1, 1)

            if count < 1 do
              error = Error.rate_limit("Rate limited", retry_after_ms: 50)
              {:error, error}
            else
              {:ok, :success}
            end
          end,
          max_attempts: 3
        )

      elapsed = System.monotonic_time(:millisecond) - start

      assert {:ok, :success} = result
      # Should have waited at least 50ms
      assert elapsed >= 50
    end
  end
end

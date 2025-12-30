# Prompt 06: Rate Limit Handling Implementation

**Target Version:** 0.4.5
**Date:** 2025-12-30
**Depends On:** Prompt 05 (Retry and Backoff)

## Objective

Implement rate limit detection and handling with backoff strategies specific to API rate limiting.

## Required Reading

1. **Canonical Implementation:**
   - `codex/codex-rs/codex-api/src/error.rs` - Rate limit error types
   - `codex/codex-rs/codex-api/src/provider.rs` - retry_429 handling

2. **Elixir SDK:**
   - `lib/codex/error.ex` - Error types
   - `lib/codex/retry.ex` - After Prompt 05

## Implementation Tasks

### 1. Add Rate Limit Error Type

Update `lib/codex/error.ex`:

```elixir
defmodule Codex.Error do
  @moduledoc """
  Error types for the Codex SDK.
  """

  defexception [:kind, :message, :details, :retry_after_ms]

  @type kind ::
    :authentication_error
    | :authorization_error
    | :rate_limit_error
    | :context_window_exceeded
    | :quota_exceeded
    | :server_error
    | :client_error
    | :transport_error
    | :unknown_error

  @type t :: %__MODULE__{
    kind: kind(),
    message: String.t(),
    details: map(),
    retry_after_ms: non_neg_integer() | nil
  }

  @doc """
  Creates a rate limit error with optional retry-after hint.
  """
  def rate_limit(message, opts \\ []) do
    retry_after = Keyword.get(opts, :retry_after_ms)
    details = Keyword.get(opts, :details, %{})

    %__MODULE__{
      kind: :rate_limit_error,
      message: message,
      details: details,
      retry_after_ms: retry_after
    }
  end

  @doc """
  Checks if error is a rate limit error.
  """
  def rate_limit?(%__MODULE__{kind: :rate_limit_error}), do: true
  def rate_limit?(_), do: false

  @doc """
  Extracts retry-after hint from error if present.
  """
  def retry_after_ms(%__MODULE__{retry_after_ms: ms}) when is_integer(ms), do: ms
  def retry_after_ms(_), do: nil
end
```

### 2. Create Rate Limit Handler

Create `lib/codex/rate_limit.ex`:

```elixir
defmodule Codex.RateLimit do
  @moduledoc """
  Rate limit detection and handling utilities.

  ## Detection

  Rate limits are detected from:
  - HTTP 429 status codes
  - Error messages containing "rate_limit"
  - Retry-After headers in responses

  ## Handling

  When rate limited, the SDK:
  1. Extracts retry-after hint if available
  2. Backs off for the specified duration (or default)
  3. Emits telemetry event
  4. Retries the request

  ## Configuration

      config :codex_sdk,
        rate_limit_default_delay_ms: 60_000,
        rate_limit_max_delay_ms: 300_000,
        rate_limit_multiplier: 2.0
  """

  require Logger

  alias Codex.Error

  @default_delay_ms 60_000
  @max_delay_ms 300_000
  @multiplier 2.0

  @doc """
  Detects rate limit error from response or error.
  """
  @spec detect(term()) :: {:rate_limited, map()} | :ok
  def detect({:error, %Error{kind: :rate_limit_error} = error}) do
    {:rate_limited, %{
      retry_after_ms: error.retry_after_ms,
      message: error.message,
      details: error.details
    }}
  end

  def detect({:error, %{status: 429} = response}) do
    retry_after = parse_retry_after(response)
    {:rate_limited, %{retry_after_ms: retry_after, source: :http_429}}
  end

  def detect({:error, %{"error" => %{"code" => "rate_limit_exceeded"}} = body}) do
    {:rate_limited, %{retry_after_ms: nil, source: :api_error, body: body}}
  end

  def detect(_), do: :ok

  @doc """
  Calculates delay for rate limit backoff.
  """
  @spec calculate_delay(map(), pos_integer()) :: non_neg_integer()
  def calculate_delay(rate_limit_info, attempt \\ 1) do
    explicit = rate_limit_info[:retry_after_ms]

    if explicit && explicit > 0 do
      explicit
    else
      base = Application.get_env(:codex_sdk, :rate_limit_default_delay_ms, @default_delay_ms)
      max = Application.get_env(:codex_sdk, :rate_limit_max_delay_ms, @max_delay_ms)
      multiplier = Application.get_env(:codex_sdk, :rate_limit_multiplier, @multiplier)

      delay = round(base * :math.pow(multiplier, attempt - 1))
      min(delay, max)
    end
  end

  @doc """
  Handles rate limit by waiting and emitting telemetry.
  """
  @spec handle(map(), keyword()) :: :ok
  def handle(rate_limit_info, opts \\ []) do
    attempt = Keyword.get(opts, :attempt, 1)
    delay = calculate_delay(rate_limit_info, attempt)

    emit_telemetry(:rate_limited, %{
      delay_ms: delay,
      attempt: attempt,
      info: rate_limit_info
    })

    Logger.warning("Rate limited, waiting #{delay}ms before retry (attempt #{attempt})")

    Process.sleep(delay)
    :ok
  end

  @doc """
  Wraps function with rate limit handling.
  """
  @spec with_rate_limit_handling((() -> term()), keyword()) :: term()
  def with_rate_limit_handling(fun, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    do_with_rate_limit(fun, 1, max_attempts, opts)
  end

  defp do_with_rate_limit(fun, attempt, max_attempts, opts) when attempt <= max_attempts do
    result = fun.()

    case detect(result) do
      {:rate_limited, info} when attempt < max_attempts ->
        handle(info, Keyword.put(opts, :attempt, attempt))
        do_with_rate_limit(fun, attempt + 1, max_attempts, opts)

      {:rate_limited, _info} ->
        result

      :ok ->
        result
    end
  end

  defp do_with_rate_limit(_fun, _attempt, _max_attempts, _opts) do
    {:error, :rate_limit_attempts_exhausted}
  end

  defp parse_retry_after(%{headers: headers}) when is_map(headers) do
    case Map.get(headers, "retry-after") || Map.get(headers, "Retry-After") do
      nil -> nil
      seconds when is_binary(seconds) -> String.to_integer(seconds) * 1000
      seconds when is_integer(seconds) -> seconds * 1000
    end
  end
  defp parse_retry_after(_), do: nil

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:codex, :rate_limit, event],
      %{system_time: System.system_time()},
      metadata
    )
  end
end
```

### 3. Integrate with Retry Module

Update `lib/codex/retry.ex` to handle rate limits specially:

```elixir
@spec retryable?(term()) :: boolean()
def retryable?({:error, %Codex.Error{kind: :rate_limit_error}}), do: true
# ... other patterns
```

### 4. Add Rate Limit Event

Update `lib/codex/events.ex`:

```elixir
defmodule AccountRateLimitsUpdated do
  use TypedStruct

  typedstruct do
    field :limits, map(), enforce: true
    field :thread_id, String.t()
    field :turn_id, String.t()
  end
end
```

## Test Requirements (TDD)

### Unit Tests (`test/codex/rate_limit_test.exs`)

```elixir
defmodule Codex.RateLimitTest do
  use ExUnit.Case, async: true

  alias Codex.{RateLimit, Error}

  describe "detect/1" do
    test "detects rate limit error" do
      error = Error.rate_limit("Rate limited", retry_after_ms: 30_000)
      assert {:rate_limited, info} = RateLimit.detect({:error, error})
      assert info.retry_after_ms == 30_000
    end

    test "detects HTTP 429" do
      response = %{status: 429, headers: %{"retry-after" => "60"}}
      assert {:rate_limited, info} = RateLimit.detect({:error, response})
      assert info.retry_after_ms == 60_000
    end

    test "detects API rate_limit_exceeded error" do
      body = %{"error" => %{"code" => "rate_limit_exceeded"}}
      assert {:rate_limited, _info} = RateLimit.detect({:error, body})
    end

    test "returns :ok for non-rate-limit errors" do
      assert :ok = RateLimit.detect({:error, :timeout})
      assert :ok = RateLimit.detect({:ok, :success})
    end
  end

  describe "calculate_delay/2" do
    test "uses explicit retry_after when present" do
      info = %{retry_after_ms: 45_000}
      assert RateLimit.calculate_delay(info) == 45_000
    end

    test "uses default with exponential backoff when no hint" do
      info = %{}
      delay1 = RateLimit.calculate_delay(info, 1)
      delay2 = RateLimit.calculate_delay(info, 2)
      assert delay2 > delay1
    end
  end

  describe "with_rate_limit_handling/2" do
    test "retries on rate limit" do
      counter = :counters.new(1, [])

      result = RateLimit.with_rate_limit_handling(fn ->
        count = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)

        if count < 2 do
          {:error, %{status: 429, headers: %{"retry-after" => "0"}}}
        else
          {:ok, :success}
        end
      end, max_attempts: 3)

      assert {:ok, :success} = result
    end

    test "gives up after max_attempts" do
      result = RateLimit.with_rate_limit_handling(fn ->
        {:error, %{status: 429, headers: %{}}}
      end, max_attempts: 2)

      assert {:error, %{status: 429}} = result
    end
  end
end
```

## Verification Criteria

1. [ ] All tests pass
2. [ ] No warnings
3. [ ] No dialyzer errors
4. [ ] No credo issues
5. [ ] Telemetry events emit correctly

## Update Requirements

### CHANGELOG.md

Add to the existing `## [0.4.5] - 2025-12-30` section:
```markdown
- Rate limit detection with `Codex.RateLimit.detect/1`
- Rate limit handling with backoff
- Retry-After header parsing
- Rate limit telemetry events
- Configurable rate limit delays
```

### config/config.exs

Add rate limit defaults:
```elixir
config :codex_sdk,
  rate_limit_default_delay_ms: 60_000,
  rate_limit_max_delay_ms: 300_000,
  rate_limit_multiplier: 2.0
```

### README.md

Add rate limit handling section.

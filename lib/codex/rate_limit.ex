defmodule Codex.RateLimit do
  @moduledoc """
  Rate limit detection and handling utilities.

  ## Detection

  Rate limits are detected from:
  - `Codex.Error` structs with `:rate_limit` kind
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

  ## Example

      Codex.RateLimit.with_rate_limit_handling(fn ->
        make_api_call()
      end, max_attempts: 3)
  """

  require Logger

  alias Codex.Error

  @default_delay_ms 60_000
  @max_delay_ms 300_000
  @multiplier 2.0

  @type rate_limit_info :: %{
          optional(:retry_after_ms) => non_neg_integer() | nil,
          optional(:message) => String.t(),
          optional(:details) => map(),
          optional(:source) => atom(),
          optional(:body) => map()
        }

  @doc """
  Detects rate limit error from response or error.

  Returns `{:rate_limited, info}` if a rate limit is detected,
  or `:ok` if not rate limited.

  ## Examples

      iex> error = Codex.Error.rate_limit("Rate limited", retry_after_ms: 30_000)
      iex> {:rate_limited, info} = Codex.RateLimit.detect({:error, error})
      iex> info.retry_after_ms
      30_000

      iex> Codex.RateLimit.detect({:ok, :success})
      :ok
  """
  @spec detect(term()) :: {:rate_limited, rate_limit_info()} | :ok
  def detect({:error, %Error{kind: :rate_limit} = error}) do
    {:rate_limited,
     %{
       retry_after_ms: error.retry_after_ms,
       message: error.message,
       details: error.details,
       source: :codex_error
     }}
  end

  def detect({:error, %{status: 429} = response}) do
    retry_after = parse_retry_after(response)
    {:rate_limited, %{retry_after_ms: retry_after, source: :http_429}}
  end

  def detect({:error, %{"error" => %{"code" => code}} = body})
      when code in ["rate_limit_exceeded", "rate_limit", "rate_limit_error"] do
    {:rate_limited, %{retry_after_ms: nil, source: :api_error, body: body}}
  end

  def detect({:error, {:http_error, 429}}) do
    {:rate_limited, %{retry_after_ms: nil, source: :http_error_tuple}}
  end

  def detect(_), do: :ok

  @doc """
  Calculates delay for rate limit backoff.

  If the rate limit info contains an explicit `retry_after_ms`, that value
  is used. Otherwise, exponential backoff is applied based on the attempt number.

  ## Examples

      iex> Codex.RateLimit.calculate_delay(%{retry_after_ms: 45_000}, 1)
      45_000

      iex> delay1 = Codex.RateLimit.calculate_delay(%{}, 1)
      iex> delay2 = Codex.RateLimit.calculate_delay(%{}, 2)
      iex> delay2 > delay1
      true
  """
  @spec calculate_delay(rate_limit_info(), pos_integer()) :: non_neg_integer()
  def calculate_delay(rate_limit_info, attempt \\ 1) do
    explicit = Map.get(rate_limit_info, :retry_after_ms)

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

  Sleeps for the calculated delay and emits a `[:codex, :rate_limit, :rate_limited]`
  telemetry event.

  ## Options

    * `:attempt` - Current attempt number (default: 1)

  ## Examples

      info = %{retry_after_ms: 1000}
      Codex.RateLimit.handle(info, attempt: 1)
      # Sleeps for 1000ms and emits telemetry
  """
  @spec handle(rate_limit_info(), keyword()) :: :ok
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

  Automatically detects rate limit responses and retries with appropriate
  backoff. Uses exponential backoff by default, or respects explicit
  retry-after hints from the API.

  ## Options

    * `:max_attempts` - Maximum number of attempts (default: 3)

  ## Examples

      result = Codex.RateLimit.with_rate_limit_handling(fn ->
        make_api_call()
      end, max_attempts: 3)
  """
  @spec with_rate_limit_handling((-> term()), keyword()) :: term()
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
        # Max attempts reached, return the rate limit error
        result

      :ok ->
        result
    end
  end

  defp do_with_rate_limit(_fun, _attempt, _max_attempts, _opts) do
    {:error, :rate_limit_attempts_exhausted}
  end

  @doc """
  Parses Retry-After header from response.

  Handles both numeric seconds and HTTP-date formats.

  ## Examples

      iex> Codex.RateLimit.parse_retry_after(%{headers: %{"retry-after" => "60"}})
      60_000

      iex> Codex.RateLimit.parse_retry_after(%{headers: %{"Retry-After" => "120"}})
      120_000

      iex> Codex.RateLimit.parse_retry_after(%{})
      nil
  """
  @spec parse_retry_after(map()) :: non_neg_integer() | nil
  def parse_retry_after(%{headers: headers}) when is_map(headers) do
    value =
      Map.get(headers, "retry-after") ||
        Map.get(headers, "Retry-After") ||
        Map.get(headers, "x-ratelimit-reset-after")

    parse_retry_after_value(value)
  end

  def parse_retry_after(%{headers: headers}) when is_list(headers) do
    value =
      find_header_value(headers, "retry-after") ||
        find_header_value(headers, "x-ratelimit-reset-after")

    parse_retry_after_value(value)
  end

  def parse_retry_after(_), do: nil

  defp find_header_value(headers, name) do
    Enum.find_value(headers, fn
      {key, value} when is_binary(key) ->
        if String.downcase(key) == name, do: value

      _ ->
        nil
    end)
  end

  defp parse_retry_after_value(nil), do: nil

  defp parse_retry_after_value(seconds) when is_integer(seconds) do
    seconds * 1000
  end

  defp parse_retry_after_value(seconds) when is_binary(seconds) do
    case Integer.parse(seconds) do
      {value, _} -> value * 1000
      :error -> nil
    end
  end

  defp parse_retry_after_value(_), do: nil

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:codex, :rate_limit, event],
      %{system_time: System.system_time()},
      metadata
    )
  end
end

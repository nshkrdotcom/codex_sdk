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
    * `:on_retry` - Callback invoked on each retry

  ## Example

      Codex.Retry.with_retry(fn ->
        make_api_call()
      end, max_attempts: 3, strategy: :exponential)
  """

  @type strategy ::
          :exponential | :linear | :constant | (attempt :: pos_integer() -> non_neg_integer())

  @type opts :: [
          max_attempts: pos_integer(),
          base_delay_ms: non_neg_integer(),
          max_delay_ms: non_neg_integer(),
          jitter: boolean(),
          strategy: strategy(),
          retry_if: (term() -> boolean()),
          on_retry: (attempt :: pos_integer(), error :: term() -> :ok)
        ]

  alias Codex.Config.Defaults

  # Default options - note that retry_if and on_retry are added dynamically
  # because anonymous functions cannot be escaped into module attributes
  @default_opts_base [
    max_attempts: Defaults.retry_max_attempts(),
    base_delay_ms: Defaults.retry_base_delay_ms(),
    max_delay_ms: Defaults.retry_max_delay_ms(),
    jitter: true,
    strategy: :exponential
  ]

  defp default_opts_with_fns do
    @default_opts_base
    |> Keyword.put(:retry_if, &retryable?/1)
    |> Keyword.put(:on_retry, fn _attempt, _error -> :ok end)
  end

  @doc """
  Executes function with retry logic.

  Returns `{:ok, result}` on success or `{:error, reason}` after all attempts exhausted.

  ## Options

    * `:max_attempts` - Maximum number of attempts (default: 4)
    * `:base_delay_ms` - Base delay in milliseconds (default: 200)
    * `:max_delay_ms` - Maximum delay cap in milliseconds (default: 10_000)
    * `:jitter` - Add random jitter to delays (default: true)
    * `:strategy` - Backoff strategy (default: `:exponential`)
    * `:retry_if` - Predicate function to determine if error is retryable
    * `:on_retry` - Callback invoked before each retry with attempt number and error

  ## Examples

      # Basic usage with defaults
      Codex.Retry.with_retry(fn -> make_api_call() end)

      # Custom configuration
      Codex.Retry.with_retry(
        fn -> risky_operation() end,
        max_attempts: 5,
        base_delay_ms: 100,
        strategy: :linear,
        on_retry: fn attempt, error ->
          Logger.warning("Retry \#{attempt}: \#{inspect(error)}")
        end
      )
  """
  @spec with_retry((-> {:ok, term()} | {:error, term()}), opts()) ::
          {:ok, term()} | {:error, term()}
  def with_retry(fun, opts \\ []) do
    opts = Keyword.merge(default_opts_with_fns(), opts)
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

  ## Examples

      iex> opts = [base_delay_ms: 100, max_delay_ms: 10_000, strategy: :exponential, jitter: false]
      iex> Codex.Retry.calculate_delay(1, opts)
      100
      iex> Codex.Retry.calculate_delay(2, opts)
      200
      iex> Codex.Retry.calculate_delay(3, opts)
      400
  """
  @spec calculate_delay(pos_integer(), opts()) :: non_neg_integer()
  def calculate_delay(attempt, opts) do
    base = Keyword.fetch!(opts, :base_delay_ms)
    max = Keyword.fetch!(opts, :max_delay_ms)
    strategy = Keyword.fetch!(opts, :strategy)
    jitter? = Keyword.fetch!(opts, :jitter)

    delay =
      case strategy do
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

  defp add_jitter(delay) when delay <= 0, do: 0

  defp add_jitter(delay) do
    # Add up to 25% random jitter
    jitter_amount = round(delay * 0.25)
    jitter = if jitter_amount > 0, do: :rand.uniform(jitter_amount), else: 0
    delay + jitter
  end

  @doc """
  Default predicate for retryable errors.

  Retries on:
  - Timeout errors
  - Connection errors
  - 5xx HTTP errors
  - Rate limit errors (429)
  - `Codex.Error` with `:rate_limit` kind
  - Stream errors
  - `Codex.TransportError` with `retryable?: true`

  Does NOT retry on:
  - Authentication errors
  - Invalid request errors
  - Context window exceeded
  - Unknown error types

  ## Examples

      iex> Codex.Retry.retryable?(:timeout)
      true
      iex> Codex.Retry.retryable?({:http_error, 503})
      true
      iex> Codex.Retry.retryable?({:http_error, 429})
      true
      iex> Codex.Retry.retryable?({:http_error, 401})
      false
      iex> Codex.Retry.retryable?(:auth_failed)
      false
  """
  @spec retryable?(term()) :: boolean()
  def retryable?(:timeout), do: true
  def retryable?(:econnrefused), do: true
  def retryable?(:econnreset), do: true
  def retryable?(:closed), do: true
  def retryable?(:nxdomain), do: true
  def retryable?({:http_error, status}) when status >= 500, do: true
  def retryable?({:http_error, 429}), do: true
  def retryable?(:stream_reset), do: true
  def retryable?(:stream_timeout), do: true
  def retryable?(%{__struct__: Codex.TransportError, retryable?: true}), do: true
  def retryable?(%{__struct__: Codex.Error, kind: :rate_limit}), do: true
  def retryable?({:turn_failed, %Codex.Error{} = error}), do: retryable?(error)
  def retryable?({:exec_failed, %Codex.Error{} = error}), do: retryable?(error)
  def retryable?(_), do: false

  @doc """
  Wraps an async stream with retry logic.

  For streaming operations, retries the entire stream from the beginning
  when a retryable error occurs.

  ## Options

  Same as `with_retry/2`.

  ## Examples

      stream = Codex.Retry.with_stream_retry(fn ->
        make_streaming_request()
      end, max_attempts: 3)

      Enum.each(stream, &process_item/1)
  """
  @spec with_stream_retry((-> Enumerable.t()), opts()) :: Enumerable.t()
  def with_stream_retry(stream_fun, opts \\ []) do
    opts = Keyword.merge(default_opts_with_fns(), opts)
    max_attempts = Keyword.fetch!(opts, :max_attempts)

    Stream.unfold({1, nil}, fn
      :done ->
        nil

      {attempt, _continuation} ->
        try do
          stream = stream_fun.()
          # Materialize the stream into a list and return elements one by one
          items = Enum.to_list(stream)
          emit_items(items)
        rescue
          e ->
            handle_stream_error(e, attempt, max_attempts, opts)
        catch
          :exit, reason ->
            handle_stream_error(reason, attempt, max_attempts, opts)
        end
    end)
    |> Stream.flat_map(fn items -> items end)
  end

  defp emit_items([]), do: {[], :done}
  defp emit_items(items), do: {items, :done}

  defp handle_stream_error(error, attempt, max_attempts, opts) do
    retry_if = Keyword.fetch!(opts, :retry_if)

    if attempt < max_attempts and retry_if.(error) do
      on_retry = Keyword.fetch!(opts, :on_retry)
      on_retry.(attempt, error)

      delay = calculate_delay(attempt, opts)
      Process.sleep(delay)
      {[], {attempt + 1, nil}}
    else
      raise error
    end
  end

  @doc """
  Returns the default options for retry operations.

  Useful for inspecting or modifying default configuration.

  ## Examples

      iex> Codex.Retry.default_opts()[:max_attempts]
      4
  """
  @spec default_opts() :: opts()
  def default_opts, do: default_opts_with_fns()
end

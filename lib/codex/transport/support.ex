defmodule Codex.Transport.Support do
  @moduledoc false

  alias Codex.RateLimit
  alias Codex.Retry
  alias Codex.Thread.Options, as: ThreadOptions

  @spec normalize_turn_opts(map() | keyword() | nil) :: map()
  def normalize_turn_opts(%{} = opts), do: opts
  def normalize_turn_opts(list) when is_list(list), do: Map.new(list)
  def normalize_turn_opts(_), do: %{}

  @spec with_retry_and_rate_limit((-> term()), ThreadOptions.t(), map()) :: term()
  def with_retry_and_rate_limit(fun, %ThreadOptions{} = thread_opts, %{} = turn_opts)
      when is_function(fun, 0) do
    {retry?, retry_opts} = resolve_retry(thread_opts, turn_opts)
    {rate_limit?, rate_limit_opts} = resolve_rate_limit(thread_opts, turn_opts)

    base_fun = fn -> fun.() end

    fun_with_rate_limit =
      if rate_limit? do
        fn -> RateLimit.with_rate_limit_handling(base_fun, rate_limit_opts) end
      else
        base_fun
      end

    if retry? do
      Retry.with_retry(fun_with_rate_limit, adjust_retry_opts(retry_opts, rate_limit?))
    else
      fun_with_rate_limit.()
    end
  end

  defp resolve_retry(%ThreadOptions{} = thread_opts, %{} = turn_opts) do
    retry = fetch_opt(turn_opts, :retry)
    retry_opts = fetch_opt(turn_opts, :retry_opts)

    retry =
      if is_nil(retry) do
        thread_opts.retry
      else
        retry
      end

    retry_opts =
      retry_opts ||
        thread_opts.retry_opts ||
        []

    {retry_enabled?(retry, retry_opts), normalize_opts(retry_opts)}
  end

  defp resolve_rate_limit(%ThreadOptions{} = thread_opts, %{} = turn_opts) do
    rate_limit = fetch_opt(turn_opts, :rate_limit)
    rate_limit_opts = fetch_opt(turn_opts, :rate_limit_opts)

    rate_limit =
      if is_nil(rate_limit) do
        thread_opts.rate_limit
      else
        rate_limit
      end

    rate_limit_opts =
      rate_limit_opts ||
        thread_opts.rate_limit_opts ||
        []

    {rate_limit_enabled?(rate_limit, rate_limit_opts), normalize_opts(rate_limit_opts)}
  end

  defp retry_enabled?(true, _opts), do: true
  defp retry_enabled?(false, _opts), do: false
  defp retry_enabled?(nil, opts), do: opts != []
  defp retry_enabled?(_other, _opts), do: false

  defp rate_limit_enabled?(true, _opts), do: true
  defp rate_limit_enabled?(false, _opts), do: false
  defp rate_limit_enabled?(nil, opts), do: opts != []
  defp rate_limit_enabled?(_other, _opts), do: false

  defp normalize_opts(nil), do: []
  defp normalize_opts(list) when is_list(list), do: list
  defp normalize_opts(%{} = map), do: Map.to_list(map)
  defp normalize_opts(_), do: []

  defp adjust_retry_opts(opts, false), do: opts

  defp adjust_retry_opts(opts, true) do
    default_retry_if = fn reason -> Retry.retryable?(reason) and not rate_limit_error?(reason) end

    Keyword.update(opts, :retry_if, default_retry_if, fn user_fun ->
      fn reason -> user_fun.(reason) and not rate_limit_error?(reason) end
    end)
  end

  defp rate_limit_error?(reason) do
    case RateLimit.detect({:error, reason}) do
      {:rate_limited, _info} -> true
      :ok -> false
    end
  end

  defp fetch_opt(%{} = opts, key) do
    case Map.fetch(opts, key) do
      {:ok, value} ->
        value

      :error ->
        case Map.fetch(opts, Atom.to_string(key)) do
          {:ok, value} -> value
          :error -> nil
        end
    end
  end
end

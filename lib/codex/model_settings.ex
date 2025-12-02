defmodule Codex.ModelSettings do
  @moduledoc """
  Model tuning options and provider selection used to configure codex runs.
  """

  @enforce_keys []
  defstruct temperature: nil,
            top_p: nil,
            frequency_penalty: nil,
            presence_penalty: nil,
            tool_choice: nil,
            parallel_tool_calls: nil,
            truncation: nil,
            max_tokens: nil,
            reasoning: nil,
            metadata: nil,
            store: nil,
            prompt_cache: nil,
            response_include: nil,
            top_logprobs: nil,
            extra_headers: %{},
            extra_body: %{},
            extra_query: %{},
            provider: :responses

  @type t :: %__MODULE__{
          temperature: number() | nil,
          top_p: number() | nil,
          frequency_penalty: number() | nil,
          presence_penalty: number() | nil,
          tool_choice: term() | nil,
          parallel_tool_calls: boolean() | nil,
          truncation: term() | nil,
          max_tokens: pos_integer() | nil,
          reasoning: term() | nil,
          metadata: map() | nil,
          store: term() | nil,
          prompt_cache: term() | nil,
          response_include: term() | nil,
          top_logprobs: term() | nil,
          extra_headers: map(),
          extra_body: map(),
          extra_query: map(),
          provider: :responses | :chat
        }

  @doc """
  Builds a validated `%Codex.ModelSettings{}` struct.
  """
  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = settings), do: {:ok, settings}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    temperature = Map.get(attrs, :temperature, Map.get(attrs, "temperature"))
    top_p = Map.get(attrs, :top_p, Map.get(attrs, "top_p"))
    frequency_penalty = Map.get(attrs, :frequency_penalty, Map.get(attrs, "frequency_penalty"))
    presence_penalty = Map.get(attrs, :presence_penalty, Map.get(attrs, "presence_penalty"))
    tool_choice = Map.get(attrs, :tool_choice, Map.get(attrs, "tool_choice"))

    parallel_tool_calls =
      Map.get(attrs, :parallel_tool_calls, Map.get(attrs, "parallel_tool_calls"))

    truncation = Map.get(attrs, :truncation, Map.get(attrs, "truncation"))
    max_tokens = Map.get(attrs, :max_tokens, Map.get(attrs, "max_tokens"))
    reasoning = Map.get(attrs, :reasoning, Map.get(attrs, "reasoning"))
    metadata = Map.get(attrs, :metadata, Map.get(attrs, "metadata"))
    store = Map.get(attrs, :store, Map.get(attrs, "store"))
    prompt_cache = Map.get(attrs, :prompt_cache, Map.get(attrs, "prompt_cache"))
    response_include = Map.get(attrs, :response_include, Map.get(attrs, "response_include"))
    top_logprobs = Map.get(attrs, :top_logprobs, Map.get(attrs, "top_logprobs"))
    extra_headers = Map.get(attrs, :extra_headers, Map.get(attrs, "extra_headers", %{}))
    extra_body = Map.get(attrs, :extra_body, Map.get(attrs, "extra_body", %{}))
    extra_query = Map.get(attrs, :extra_query, Map.get(attrs, "extra_query", %{}))

    provider =
      Map.get(attrs, :provider, Map.get(attrs, "provider", :responses))
      |> normalize_provider()

    with :ok <- validate_range(temperature, :temperature, 0.0, 2.0),
         :ok <- validate_range(top_p, :top_p, 0.0, 1.0),
         :ok <- validate_number(frequency_penalty, :frequency_penalty),
         :ok <- validate_number(presence_penalty, :presence_penalty),
         :ok <- validate_boolean(parallel_tool_calls, :parallel_tool_calls),
         :ok <- validate_positive(max_tokens, :max_tokens),
         :ok <- validate_provider(provider),
         {:ok, extra_headers} <- normalize_map(extra_headers, :extra_headers),
         {:ok, extra_body} <- normalize_map(extra_body, :extra_body),
         {:ok, extra_query} <- normalize_map(extra_query, :extra_query) do
      {:ok,
       %__MODULE__{
         temperature: temperature,
         top_p: top_p,
         frequency_penalty: frequency_penalty,
         presence_penalty: presence_penalty,
         tool_choice: tool_choice,
         parallel_tool_calls: parallel_tool_calls,
         truncation: truncation,
         max_tokens: max_tokens,
         reasoning: reasoning,
         metadata: metadata,
         store: store,
         prompt_cache: prompt_cache,
         response_include: response_include,
         top_logprobs: top_logprobs,
         extra_headers: extra_headers,
         extra_body: extra_body,
         extra_query: extra_query,
         provider: provider
       }}
    else
      {:error, _} = error -> error
    end
  end

  @doc """
  Merges two settings structs, preferring non-nil values from `overrides`.
  """
  @spec merge(t(), map() | keyword() | t()) :: {:ok, t()} | {:error, term()}
  def merge(%__MODULE__{} = base, overrides) do
    with {:ok, %__MODULE__{} = override_struct} <- new(overrides) do
      merged =
        base
        |> Map.from_struct()
        |> Map.merge(Map.from_struct(override_struct), fn _key, left, right ->
          if is_nil(right), do: left, else: right
        end)

      {:ok, struct!(__MODULE__, merged)}
    end
  end

  defp validate_range(nil, _field, _min, _max), do: :ok

  defp validate_range(value, field, min, max) when is_number(value) do
    if value >= min and value <= max do
      :ok
    else
      {:error, {:"invalid_#{field}", value}}
    end
  end

  defp validate_range(value, field, _min, _max), do: {:error, {:"invalid_#{field}", value}}

  defp validate_number(nil, _field), do: :ok
  defp validate_number(value, _field) when is_number(value), do: :ok
  defp validate_number(value, field), do: {:error, {:"invalid_#{field}", value}}

  defp validate_boolean(nil, _field), do: :ok
  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:"invalid_#{field}", value}}

  defp validate_positive(nil, _field), do: :ok

  defp validate_positive(value, _field) when is_integer(value) and value > 0, do: :ok
  defp validate_positive(value, field), do: {:error, {:"invalid_#{field}", value}}

  defp validate_provider(provider) when provider in [:responses, :chat], do: :ok
  defp validate_provider(provider), do: {:error, {:invalid_provider, provider}}

  defp normalize_provider(provider) when is_binary(provider) do
    provider
    |> String.downcase()
    |> case do
      "responses" -> :responses
      "chat" -> :chat
      other -> other
    end
  end

  defp normalize_provider(provider), do: provider

  defp normalize_map(value, _field) when is_map(value), do: {:ok, value}
  defp normalize_map(nil, _field), do: {:ok, %{}}

  defp normalize_map(value, field) do
    {:error, {:"invalid_#{field}", value}}
  end
end

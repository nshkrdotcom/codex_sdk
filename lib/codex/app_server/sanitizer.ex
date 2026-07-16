defmodule Codex.AppServer.Sanitizer do
  @moduledoc false

  import Kernel, except: [inspect: 2]

  defmodule Values do
    @moduledoc false

    @enforce_keys [:exact, :substrings, :count, :total_bytes]
    @derive {Inspect, only: [:count, :total_bytes]}
    defstruct [:exact, :substrings, :count, :total_bytes]

    @type t :: %__MODULE__{
            exact: [binary()],
            substrings: [binary()],
            count: non_neg_integer(),
            total_bytes: non_neg_integer()
          }
  end

  defimpl Jason.Encoder, for: Values do
    def encode(_values, _opts) do
      raise ArgumentError, "redaction values are transient and cannot be encoded"
    end
  end

  @redacted "[REDACTED]"
  @secret_names ~w(
    access_key access_token apikey api_key authorization bearer client_secret cookie
    credential credentials password private_key refresh_token secret session_token signing_key
    token tokens auth_tokens
  )

  @safe_token_keys ~w(
    cached_input_tokens input_tokens output_tokens reasoning_output_tokens total_tokens
  )

  @json_secret_pattern ~r/("(?:access[_-]?key|access[_-]?token|api[_-]?key|authorization|bearer|client[_-]?secret|codex[_-]?api[_-]?key|cookie|credentials?|openai[_-]?api[_-]?key|password|private[_-]?key|refresh[_-]?token|secret|session[_-]?token|signing[_-]?key|token|tokens)"\s*:\s*")[^"]*(")/i
  @authorization_pattern ~r/(Authorization\s*[=:]\s*)(?:Bearer\s+)?[^\s,;]+/i
  @assignment_pattern ~r/((?:CODEX_API_KEY|OPENAI_API_KEY|ACCESS_TOKEN|REFRESH_TOKEN|CLIENT_SECRET|PASSWORD|PRIVATE_KEY|SESSION_TOKEN)\s*[=:]\s*)[^\s,;]+/i
  @bearer_pattern ~r/(Bearer\s+)[A-Za-z0-9._~+\/-]+/i
  @openai_key_pattern ~r/\bsk-[A-Za-z0-9_-]{8,}\b/

  @max_dynamic_values 32
  @max_dynamic_value_bytes 4_096
  @max_dynamic_total_bytes 16_384
  @min_exact_bytes 4
  @min_substring_bytes 8

  @spec values(term()) :: Values.t()
  def values(source) do
    exact =
      source
      |> collect_values()
      |> Enum.filter(&(byte_size(&1) >= @min_exact_bytes))
      |> Enum.filter(&(byte_size(&1) <= @max_dynamic_value_bytes))
      |> Enum.uniq()
      |> Enum.sort_by(&byte_size/1, :desc)
      |> take_bounded_values()

    %Values{
      exact: exact,
      substrings: Enum.filter(exact, &(byte_size(&1) >= @min_substring_bytes)),
      count: length(exact),
      total_bytes: Enum.reduce(exact, 0, &(byte_size(&1) + &2))
    }
  end

  @spec empty_values() :: Values.t()
  def empty_values, do: %Values{exact: [], substrings: [], count: 0, total_bytes: 0}

  @spec empty?(Values.t()) :: boolean()
  def empty?(%Values{count: count}), do: count == 0

  @spec term(term()) :: term()
  def term(value), do: term(value, empty_values())

  @spec term(term(), Values.t()) :: term()
  def term(%Values{}, %Values{}), do: @redacted

  def term(%_{} = struct, %Values{} = values),
    do: struct |> Map.from_struct() |> term(values)

  def term(map, %Values{} = values) when is_map(map) do
    Map.new(map, fn {key, value} ->
      sanitized_key = if is_binary(key), do: text(key, values), else: key

      if secret_key?(key),
        do: {sanitized_key, @redacted},
        else: {sanitized_key, term(value, values)}
    end)
  end

  def term(list, %Values{} = values) when is_list(list) do
    if List.ascii_printable?(list) do
      list |> to_string() |> text(values)
    else
      Enum.map(list, &term(&1, values))
    end
  end

  def term(tuple, %Values{} = values) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&term(&1, values)) |> List.to_tuple()

  def term(value, %Values{} = values) when is_binary(value), do: text(value, values)
  def term(value, %Values{}), do: value

  @spec text(iodata()) :: String.t()
  def text(value), do: text(value, empty_values())

  @spec text(iodata(), Values.t()) :: String.t()
  def text(value, %Values{} = values) do
    value
    |> IO.iodata_to_binary()
    |> String.replace(@json_secret_pattern, "\\1#{@redacted}\\2")
    |> String.replace(@authorization_pattern, "\\1#{@redacted}")
    |> String.replace(@assignment_pattern, "\\1#{@redacted}")
    |> String.replace(@bearer_pattern, "\\1#{@redacted}")
    |> String.replace(@openai_key_pattern, @redacted)
    |> redact_dynamic(values)
  end

  @spec inspect(term()) :: String.t()
  def inspect(value), do: inspect(value, empty_values())

  @spec inspect(term(), Values.t()) :: String.t()
  def inspect(value, %Values{} = values), do: value |> term(values) |> Kernel.inspect()

  defp redact_dynamic(text, %Values{exact: exact, substrings: substrings}) do
    if text in exact do
      @redacted
    else
      Enum.reduce(substrings, text, &:binary.replace(&2, &1, @redacted, [:global]))
    end
  end

  defp collect_values(value) when is_binary(value), do: [value]

  defp collect_values(value) when is_map(value) do
    value
    |> Map.values()
    |> Enum.flat_map(&collect_values/1)
  end

  defp collect_values(value) when is_list(value) do
    if List.ascii_printable?(value) do
      [to_string(value)]
    else
      Enum.flat_map(value, &collect_values/1)
    end
  end

  defp collect_values(value) when is_tuple(value) do
    value |> Tuple.to_list() |> Enum.flat_map(&collect_values/1)
  end

  defp collect_values(_value), do: []

  defp take_bounded_values(values) do
    values
    |> Enum.reduce_while({[], 0}, fn value, {acc, total_bytes} ->
      value_bytes = byte_size(value)

      cond do
        length(acc) >= @max_dynamic_values ->
          {:halt, {acc, total_bytes}}

        total_bytes + value_bytes > @max_dynamic_total_bytes ->
          {:cont, {acc, total_bytes}}

        true ->
          {:cont, {[value | acc], total_bytes + value_bytes}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp secret_key?(key) do
    normalized = key |> to_string() |> Macro.underscore() |> String.downcase()

    normalized not in @safe_token_keys and
      not String.ends_with?(normalized, ["_ref", "_refs", "_id", "_ids"]) and
      Enum.any?(@secret_names, fn name ->
        normalized == name or String.ends_with?(normalized, "_" <> name)
      end)
  end
end

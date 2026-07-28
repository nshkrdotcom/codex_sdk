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
    @spec encode(term(), term()) :: no_return()
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

  # Keys whose name trips the `@secret_names` heuristic but whose value is never
  # credential material: usage counters, and the app-server
  # `item/tool/requestUserInput` question flag `isSecret` (a boolean telling a
  # client to mask the answer it collects, not a secret itself).
  @safe_keys ~w(
    cached_input_tokens input_tokens output_tokens reasoning_output_tokens total_tokens
    is_secret
  )

  # Literal scanners for the fixed credential shapes this module redacts. They
  # are hand-rolled binary matchers on purpose: this repository bans pattern
  # sigils and the pattern module in shipped code (`Codex.ForbiddenTokensTest`).
  @whitespace [?\s, ?\t, ?\n, ?\r, ?\f, ?\v]
  @value_stops [?,, ?;]
  @assignment_separators [?=, ?:]
  @json_separators [?:]
  @bearer_extra [?., ?_, ?~, ?+, ?/, ?-]

  @json_secret_key_parts [
    ~w(access key),
    ~w(access token),
    ~w(api key),
    ~w(authorization),
    ~w(bearer),
    ~w(client secret),
    ~w(codex api key),
    ~w(cookie),
    ~w(credential),
    ~w(credentials),
    ~w(openai api key),
    ~w(password),
    ~w(private key),
    ~w(refresh token),
    ~w(secret),
    ~w(session token),
    ~w(signing key),
    ~w(token),
    ~w(tokens)
  ]
  @json_secret_key_separators ["", "_", "-"]
  @json_secret_keys Enum.flat_map(@json_secret_key_parts, fn [first | rest] ->
                      Enum.reduce(rest, [first], fn part, prefixes ->
                        for prefix <- prefixes,
                            separator <- @json_secret_key_separators,
                            do: prefix <> separator <> part
                      end)
                    end)
  @min_json_secret_key_bytes Enum.min(Enum.map(@json_secret_keys, &byte_size/1))
  @max_json_secret_key_bytes Enum.max(Enum.map(@json_secret_keys, &byte_size/1))

  @assignment_keys ~w(
    codex_api_key openai_api_key access_token refresh_token client_secret password
    private_key session_token
  )

  @authorization_keyword "authorization"
  @bearer_keyword "bearer"
  @openai_key_prefix "sk-"
  @min_openai_key_bytes 8

  # Every scanner requires a fixed first byte (or literal), so scanning can jump
  # straight to the next candidate instead of testing every offset. These anchor
  # sets are derived from the keywords the matchers themselves use so they can
  # never drift out of sync.
  @json_anchors ["\""]
  @authorization_anchors [
    binary_part(@authorization_keyword, 0, 1),
    String.upcase(binary_part(@authorization_keyword, 0, 1))
  ]
  @bearer_anchors [
    binary_part(@bearer_keyword, 0, 1),
    String.upcase(binary_part(@bearer_keyword, 0, 1))
  ]
  @assignment_anchors @assignment_keys
                      |> Enum.flat_map(fn key ->
                        first = binary_part(key, 0, 1)
                        [first, String.upcase(first)]
                      end)
                      |> Enum.uniq()
  @openai_anchors [@openai_key_prefix]

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
      |> Enum.filter(&exact_candidate?/1)
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

  def term([], %Values{}), do: []

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
    |> scan(&match_json_secret/2, @json_anchors)
    |> scan(&match_authorization/2, @authorization_anchors)
    |> scan(&match_assignment/2, @assignment_anchors)
    |> scan(&match_bearer/2, @bearer_anchors)
    |> scan(&match_openai_key/2, @openai_anchors)
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

  defp exact_candidate?(value) do
    size = byte_size(value)
    size >= @min_exact_bytes and size <= @max_dynamic_value_bytes
  end

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

    normalized not in @safe_keys and
      not String.ends_with?(normalized, ["_ref", "_refs", "_id", "_ids"]) and
      Enum.any?(@secret_names, fn name ->
        normalized == name or String.ends_with?(normalized, "_" <> name)
      end)
  end

  # Left-to-right, non-overlapping scan: the earliest anchored position where
  # `matcher` succeeds is replaced and scanning resumes after the bytes it
  # consumed. Matchers receive the byte preceding their position so they can
  # require a word boundary.
  defp scan(binary, matcher, anchors),
    do: scan(binary, matcher, anchor_pattern(anchors), 0, 0, [])

  # `:binary.match/3` recompiles a raw pattern list on every call, so the five
  # anchor automatons are compiled once and memoized for the node's lifetime.
  defp anchor_pattern(anchors) do
    key = {__MODULE__, :anchor_pattern, anchors}

    case :persistent_term.get(key, nil) do
      nil ->
        pattern = :binary.compile_pattern(anchors)
        :persistent_term.put(key, pattern)
        pattern

      pattern ->
        pattern
    end
  end

  defp scan(binary, matcher, anchors, position, start, acc) do
    case next_anchor(binary, anchors, position) do
      nil ->
        finish(binary, start, acc)

      index ->
        scan_anchor(binary, matcher, anchors, {index, start}, acc)
    end
  end

  defp scan_anchor(binary, matcher, anchors, {index, start}, acc) do
    case matcher.(drop(binary, index), previous_byte(binary, index)) do
      {:match, replacement, remaining} ->
        resume = byte_size(binary) - byte_size(remaining)
        literal = binary_part(binary, start, index - start)
        scan(binary, matcher, anchors, resume, resume, [replacement, literal | acc])

      :nomatch ->
        scan(binary, matcher, anchors, index + 1, start, acc)
    end
  end

  defp finish(binary, 0, []), do: binary

  defp finish(binary, start, acc),
    do: [drop(binary, start) | acc] |> Enum.reverse() |> IO.iodata_to_binary()

  defp next_anchor(binary, anchors, position) do
    size = byte_size(binary)

    if position >= size do
      nil
    else
      case :binary.match(binary, anchors, scope: {position, size - position}) do
        {index, _length} -> index
        :nomatch -> nil
      end
    end
  end

  defp previous_byte(_binary, 0), do: nil
  defp previous_byte(binary, index), do: :binary.at(binary, index - 1)

  # "<secret key>" <whitespace> : <whitespace> "<value>"
  defp match_json_secret(<<?", rest::binary>> = binary, _previous) do
    with {:ok, key, after_key} <- take_quoted(rest),
         true <- json_secret_key?(key),
         {:ok, after_separator} <- skip_separator(after_key, @json_separators),
         <<?", value::binary>> <- after_separator,
         {:ok, _value, remaining} <- take_quoted(value) do
      prefix = binary_part(binary, 0, byte_size(binary) - byte_size(after_separator) + 1)
      {:match, [prefix, @redacted, ?"], remaining}
    else
      _other -> :nomatch
    end
  end

  defp match_json_secret(_binary, _previous), do: :nomatch

  defp json_secret_key?(key)
       when byte_size(key) >= @min_json_secret_key_bytes and
              byte_size(key) <= @max_json_secret_key_bytes,
       do: downcase_ascii(key) in @json_secret_keys

  defp json_secret_key?(_key), do: false

  # Authorization <whitespace> [=:] <whitespace> [Bearer <whitespace>] <value>
  defp match_authorization(binary, _previous) do
    with {:ok, after_keyword} <- take_prefix_ci(binary, @authorization_keyword),
         {:ok, after_separator} <- skip_separator(after_keyword, @assignment_separators),
         {:ok, remaining} <- take_authorization_value(after_separator) do
      prefix = binary_part(binary, 0, byte_size(binary) - byte_size(after_separator))
      {:match, [prefix, @redacted], remaining}
    else
      _other -> :nomatch
    end
  end

  # The `Bearer` prefix is optional: when nothing follows it, the keyword itself
  # is the redacted value.
  defp take_authorization_value(binary) do
    case take_bearer_prefix(binary) do
      {:ok, after_bearer} -> take_bearer_or_plain_value(binary, after_bearer)
      :error -> take_unquoted_value(binary)
    end
  end

  defp take_bearer_or_plain_value(binary, after_bearer) do
    case take_unquoted_value(after_bearer) do
      {:ok, _remaining} = taken -> taken
      :error -> take_unquoted_value(binary)
    end
  end

  # <ASSIGNMENT KEY> <whitespace> [=:] <whitespace> <value>
  defp match_assignment(binary, _previous) do
    with {:ok, after_keyword} <- take_any_prefix_ci(binary, @assignment_keys),
         {:ok, after_separator} <- skip_separator(after_keyword, @assignment_separators),
         {:ok, remaining} <- take_unquoted_value(after_separator) do
      prefix = binary_part(binary, 0, byte_size(binary) - byte_size(after_separator))
      {:match, [prefix, @redacted], remaining}
    else
      _other -> :nomatch
    end
  end

  # Bearer <whitespace> <token>
  defp match_bearer(binary, _previous) do
    with {:ok, after_keyword} <- take_prefix_ci(binary, @bearer_keyword),
         {:ok, after_whitespace} <- take_required_whitespace(after_keyword),
         {:ok, remaining} <- take_run(after_whitespace, &bearer_byte?/1) do
      prefix = binary_part(binary, 0, byte_size(binary) - byte_size(after_whitespace))
      {:match, [prefix, @redacted], remaining}
    else
      _other -> :nomatch
    end
  end

  # Word boundary, "sk-", then at least eight key bytes ending on a word byte.
  defp match_openai_key(<<@openai_key_prefix, rest::binary>> = binary, previous) do
    if word_byte?(previous),
      do: :nomatch,
      else: match_openai_key_body(binary, rest)
  end

  defp match_openai_key(_binary, _previous), do: :nomatch

  defp match_openai_key_body(binary, rest) do
    run = binary_part(rest, 0, run_length(rest, &key_byte?/1))
    trimmed = String.trim_trailing(run, "-")

    if byte_size(trimmed) >= @min_openai_key_bytes do
      consumed = byte_size(@openai_key_prefix) + byte_size(trimmed)
      {:match, [@redacted], drop(binary, consumed)}
    else
      :nomatch
    end
  end

  defp take_bearer_prefix(binary) do
    case take_prefix_ci(binary, @bearer_keyword) do
      {:ok, after_keyword} -> take_required_whitespace(after_keyword)
      :error -> :error
    end
  end

  defp take_quoted(binary) do
    case :binary.match(binary, "\"") do
      {position, 1} -> {:ok, binary_part(binary, 0, position), drop(binary, position + 1)}
      :nomatch -> :error
    end
  end

  defp skip_separator(binary, separators) do
    case skip_whitespace(binary) do
      <<byte, rest::binary>> ->
        if byte in separators, do: {:ok, skip_whitespace(rest)}, else: :error

      _other ->
        :error
    end
  end

  defp take_prefix_ci(binary, keyword) do
    size = byte_size(keyword)
    if prefix_ci?(binary, keyword, 0, size), do: {:ok, drop(binary, size)}, else: :error
  end

  defp prefix_ci?(_binary, _keyword, index, size) when index >= size, do: true

  defp prefix_ci?(binary, keyword, index, size) when byte_size(binary) > index do
    downcase_byte(:binary.at(binary, index)) == :binary.at(keyword, index) and
      prefix_ci?(binary, keyword, index + 1, size)
  end

  defp prefix_ci?(_binary, _keyword, _index, _size), do: false

  defp take_any_prefix_ci(_binary, []), do: :error

  defp take_any_prefix_ci(binary, [keyword | rest]) do
    case take_prefix_ci(binary, keyword) do
      {:ok, _remaining} = taken -> taken
      :error -> take_any_prefix_ci(binary, rest)
    end
  end

  defp take_required_whitespace(binary), do: take_run(binary, &whitespace?/1)

  defp take_unquoted_value(binary), do: take_run(binary, &value_byte?/1)

  defp take_run(binary, predicate) do
    case run_length(binary, predicate) do
      0 -> :error
      count -> {:ok, drop(binary, count)}
    end
  end

  defp skip_whitespace(binary), do: drop(binary, run_length(binary, &whitespace?/1))

  defp run_length(binary, predicate), do: run_length(binary, predicate, 0)

  defp run_length(binary, predicate, count) when byte_size(binary) > count do
    if predicate.(:binary.at(binary, count)),
      do: run_length(binary, predicate, count + 1),
      else: count
  end

  defp run_length(_binary, _predicate, count), do: count

  defp drop(binary, count), do: binary_part(binary, count, byte_size(binary) - count)

  defp downcase_ascii(binary),
    do: for(<<byte <- binary>>, into: <<>>, do: <<downcase_byte(byte)>>)

  defp downcase_byte(byte) when byte in ?A..?Z, do: byte + 32
  defp downcase_byte(byte), do: byte

  defp whitespace?(byte), do: byte in @whitespace

  defp value_byte?(byte), do: not whitespace?(byte) and byte not in @value_stops

  defp bearer_byte?(byte), do: alphanumeric?(byte) or byte in @bearer_extra

  defp key_byte?(byte), do: word_byte?(byte) or byte == ?-

  defp word_byte?(nil), do: false
  defp word_byte?(byte), do: alphanumeric?(byte) or byte == ?_

  defp alphanumeric?(byte), do: byte in ?a..?z or byte in ?A..?Z or byte in ?0..?9
end

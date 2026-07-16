defmodule Codex.AppServer.Sanitizer do
  @moduledoc false

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

  @spec term(term()) :: term()
  def term(%_{} = struct), do: struct |> Map.from_struct() |> term()

  def term(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      if secret_key?(key), do: {key, @redacted}, else: {key, term(value)}
    end)
  end

  def term(list) when is_list(list) do
    if List.ascii_printable?(list) do
      list |> to_string() |> text()
    else
      Enum.map(list, &term/1)
    end
  end

  def term(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&term/1) |> List.to_tuple()

  def term(value) when is_binary(value), do: text(value)
  def term(value), do: value

  @spec text(iodata()) :: String.t()
  def text(value) do
    value
    |> IO.iodata_to_binary()
    |> String.replace(@json_secret_pattern, "\\1#{@redacted}\\2")
    |> String.replace(@authorization_pattern, "\\1#{@redacted}")
    |> String.replace(@assignment_pattern, "\\1#{@redacted}")
    |> String.replace(@bearer_pattern, "\\1#{@redacted}")
    |> String.replace(@openai_key_pattern, @redacted)
  end

  @spec inspect(term()) :: String.t()
  def inspect(value), do: value |> term() |> Kernel.inspect()

  defp secret_key?(key) do
    normalized = key |> to_string() |> Macro.underscore() |> String.downcase()

    normalized not in @safe_token_keys and
      not String.ends_with?(normalized, ["_ref", "_refs", "_id", "_ids"]) and
      Enum.any?(@secret_names, fn name ->
        normalized == name or String.ends_with?(normalized, "_" <> name)
      end)
  end
end

defmodule Codex.AppServer.Protocol do
  @moduledoc false

  alias Codex.AppServer.Sanitizer
  alias Codex.IO.Buffer

  require Logger

  @type message :: map()
  @type message_type :: :request | :notification | :response | :error | :unknown

  @spec decode_lines(String.t(), iodata()) :: {[message()], String.t(), [String.t()]}
  def decode_lines(buffer, chunk) when is_binary(buffer) do
    decode_lines(buffer, chunk, Sanitizer.empty_values())
  end

  @spec decode_lines(String.t(), iodata(), Sanitizer.Values.t()) ::
          {[message()], String.t(), [String.t()]}
  def decode_lines(buffer, chunk, %Sanitizer.Values{} = redaction_values)
      when is_binary(buffer) do
    data = buffer <> IO.iodata_to_binary(chunk)
    {lines, rest} = Buffer.split_lines(data)

    {messages, non_json} =
      lines
      |> Enum.reject(&(&1 == ""))
      |> Enum.reduce({[], []}, &decode_line(&1, &2, redaction_values))

    {Enum.reverse(messages), rest, Enum.reverse(non_json)}
  end

  @spec message_type(message()) :: message_type()
  def message_type(%{"id" => _id, "method" => _method}), do: :request
  def message_type(%{"method" => _method}), do: :notification
  def message_type(%{"id" => _id, "result" => _result}), do: :response
  def message_type(%{"id" => _id, "error" => _error}), do: :error
  def message_type(_), do: :unknown

  @spec encode_request(String.t() | integer(), String.t(), map() | list() | nil) :: iolist()
  def encode_request(id, method, params \\ nil) when is_binary(method) do
    base = %{"id" => id, "method" => method}

    base
    |> put_optional("params", params)
    |> Jason.encode_to_iodata!()
    |> then(&[&1, "\n"])
  end

  @spec encode_notification(String.t(), map() | list() | nil) :: iolist()
  def encode_notification(method, params \\ nil) when is_binary(method) do
    %{"method" => method}
    |> put_optional("params", params)
    |> Jason.encode_to_iodata!()
    |> then(&[&1, "\n"])
  end

  @spec encode_response(String.t() | integer(), map()) :: iolist()
  def encode_response(id, result) when is_map(result) do
    %{"id" => id, "result" => result}
    |> Jason.encode_to_iodata!()
    |> then(&[&1, "\n"])
  end

  @spec encode_error(String.t() | integer(), integer(), String.t(), map() | nil) :: iolist()
  def encode_error(id, code, message, data \\ nil)
      when is_integer(code) and is_binary(message) do
    message = Sanitizer.text(message)
    data = Sanitizer.term(data)

    %{
      "id" => id,
      "error" =>
        %{
          "code" => code,
          "message" => message
        }
        |> put_optional("data", data)
    }
    |> Jason.encode_to_iodata!()
    |> then(&[&1, "\n"])
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, _key, []), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp decode_line(line, {messages, non_json}, redaction_values) do
    case Jason.decode(line) do
      {:ok, decoded} when is_map(decoded) ->
        decoded = sanitize_dynamic_term(decoded, redaction_values)
        {[decoded | messages], non_json}

      {:ok, decoded} ->
        Logger.debug(
          "Ignoring non-object JSON line: #{Sanitizer.inspect(decoded, redaction_values)}"
        )

        {messages, [Sanitizer.text(line, redaction_values) | non_json]}

      {:error, reason} ->
        Logger.warning(
          "Failed to decode JSON line: #{Sanitizer.inspect(reason, redaction_values)} " <>
            "(#{Sanitizer.text(line, redaction_values)})"
        )

        {messages, [Sanitizer.text(line, redaction_values) | non_json]}
    end
  end

  defp sanitize_dynamic_term(value, redaction_values) do
    if Sanitizer.empty?(redaction_values),
      do: value,
      else: Sanitizer.term(value, redaction_values)
  end
end

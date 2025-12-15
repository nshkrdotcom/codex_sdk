defmodule Codex.AppServer.Protocol do
  @moduledoc false

  require Logger

  @type message :: map()
  @type message_type :: :request | :notification | :response | :error | :unknown

  @spec decode_lines(String.t(), iodata()) :: {[message()], String.t(), [String.t()]}
  def decode_lines(buffer, chunk) when is_binary(buffer) do
    data = buffer <> IO.iodata_to_binary(chunk)
    {lines, rest} = split_lines(data)
    {messages, non_json} = decode_complete_lines(lines)
    {messages, rest, non_json}
  end

  defp split_lines(data) do
    parts = String.split(data, "\n", trim: false)

    case parts do
      [] -> {[], data}
      [single] -> {[], single}
      _ -> {Enum.drop(parts, -1), List.last(parts)}
    end
  end

  defp decode_complete_lines(lines) do
    lines
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce({[], []}, fn line, {messages, non_json} ->
      case decode_line(line) do
        {:ok, msg} -> {[msg | messages], non_json}
        {:non_json, raw_line} -> {messages, [raw_line | non_json]}
      end
    end)
    |> then(fn {messages, non_json} -> {Enum.reverse(messages), Enum.reverse(non_json)} end)
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

  defp decode_line(line) do
    case Jason.decode(line) do
      {:ok, decoded} when is_map(decoded) ->
        {:ok, decoded}

      {:ok, decoded} ->
        Logger.debug("Ignoring non-object JSON-RPC message: #{inspect(decoded)}")
        {:non_json, line}

      {:error, reason} ->
        Logger.warning("Failed to decode JSON-RPC message: #{inspect(reason)} (#{line})")
        {:non_json, line}
    end
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, _key, []), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)
end

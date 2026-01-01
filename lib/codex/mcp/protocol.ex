defmodule Codex.MCP.Protocol do
  @moduledoc false

  require Logger

  @type message :: map()

  @spec encode_message(message()) :: nonempty_list(iodata())
  def encode_message(%{} = message) do
    message
    |> Jason.encode_to_iodata!()
    |> then(&[&1, "\n"])
  end

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
end

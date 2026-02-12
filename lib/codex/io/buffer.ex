defmodule Codex.IO.Buffer do
  @moduledoc """
  Shared helpers for newline-delimited subprocess output buffering and JSON decoding.
  """

  require Logger

  @type line :: binary()

  @spec split_lines(binary()) :: {[line()], binary()}
  def split_lines(data) when is_binary(data) do
    case :binary.split(data, "\n", [:global]) do
      [single] ->
        {[], single}

      parts ->
        {complete, [rest]} = Enum.split(parts, length(parts) - 1)
        {Enum.map(complete, &strip_trailing_cr/1), rest}
    end
  end

  @spec decode_json_lines(binary(), iodata()) :: {[map()], binary(), [binary()]}
  def decode_json_lines(buffer, chunk) when is_binary(buffer) do
    data = buffer <> iodata_to_binary(chunk)
    {lines, rest} = split_lines(data)
    {messages, non_json} = decode_complete_lines(lines)
    {messages, rest, non_json}
  end

  @spec decode_complete_lines([binary()]) :: {[map()], [binary()]}
  def decode_complete_lines(lines) when is_list(lines) do
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

  @spec decode_line(binary()) :: {:ok, map()} | {:non_json, binary()}
  def decode_line(line) when is_binary(line) do
    case Jason.decode(line) do
      {:ok, decoded} when is_map(decoded) ->
        {:ok, decoded}

      {:ok, decoded} ->
        Logger.debug("Ignoring non-object JSON line: #{inspect(decoded)}")
        {:non_json, line}

      {:error, reason} ->
        Logger.warning("Failed to decode JSON line: #{inspect(reason)} (#{line})")
        {:non_json, line}
    end
  end

  @spec iodata_to_binary(iodata()) :: binary()
  def iodata_to_binary(data) when is_binary(data), do: data
  def iodata_to_binary(data), do: IO.iodata_to_binary(data)

  defp strip_trailing_cr(line) when is_binary(line) do
    size = byte_size(line)

    if size > 0 and :binary.at(line, size - 1) == ?\r do
      :binary.part(line, 0, size - 1)
    else
      line
    end
  end
end

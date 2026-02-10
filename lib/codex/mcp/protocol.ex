defmodule Codex.MCP.Protocol do
  @moduledoc false

  alias Codex.IO.Buffer

  @type message :: map()

  @spec encode_message(message()) :: nonempty_list(iodata())
  def encode_message(%{} = message) do
    message
    |> Jason.encode_to_iodata!()
    |> then(&[&1, "\n"])
  end

  @spec decode_lines(String.t(), iodata()) :: {[message()], String.t(), [String.t()]}
  def decode_lines(buffer, chunk) when is_binary(buffer) do
    Buffer.decode_json_lines(buffer, chunk)
  end
end

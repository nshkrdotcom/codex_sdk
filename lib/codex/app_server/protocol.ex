defmodule Codex.AppServer.Protocol do
  @moduledoc false

  alias Codex.IO.Buffer

  @type message :: map()
  @type message_type :: :request | :notification | :response | :error | :unknown

  @spec decode_lines(String.t(), iodata()) :: {[message()], String.t(), [String.t()]}
  def decode_lines(buffer, chunk) when is_binary(buffer) do
    Buffer.decode_json_lines(buffer, chunk)
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

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, _key, []), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)
end

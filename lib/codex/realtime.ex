defmodule Codex.Realtime do
  @moduledoc """
  Placeholder for realtime pipelines.

  Realtime APIs are not yet supported by the Elixir SDK. Calls to this module
  return an `{:error, %Codex.Error{kind: :unsupported_feature}}` tuple with
  a descriptive message.
  """

  alias Codex.Error

  @spec connect(map() | keyword()) :: {:error, Error.t()}
  def connect(_opts \\ %{}), do: unsupported(:realtime)

  @spec stream(map() | keyword()) :: {:error, Error.t()}
  def stream(_opts \\ %{}), do: unsupported(:realtime)

  defp unsupported(feature) do
    message =
      "#{String.capitalize(to_string(feature))} support is not available in the Elixir SDK yet"

    {:error, Error.new(:unsupported_feature, message, %{feature: feature})}
  end
end

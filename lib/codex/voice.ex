defmodule Codex.Voice do
  @moduledoc """
  Placeholder for voice pipelines.

  Voice capture/playback APIs are currently out of scope for the Elixir SDK.
  Calls return an `{:error, %Codex.Error{kind: :unsupported_feature}}` tuple
  with a clear message.
  """

  alias Codex.Error

  @spec stream(map() | keyword()) :: {:error, Error.t()}
  def stream(_opts \\ %{}), do: unsupported(:voice)

  @spec call(map() | keyword()) :: {:error, Error.t()}
  def call(_opts \\ %{}), do: unsupported(:voice)

  defp unsupported(feature) do
    message =
      "#{String.capitalize(to_string(feature))} support is not available in the Elixir SDK yet"

    {:error, Error.new(:unsupported_feature, message, %{feature: feature})}
  end
end

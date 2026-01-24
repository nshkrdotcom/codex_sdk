defmodule Codex.Protocol.Elicitation do
  @moduledoc """
  MCP elicitation request and action types.
  """

  @type action :: :accept | :decline | :cancel

  defmodule Request do
    @moduledoc "MCP elicitation request"
    use TypedStruct

    typedstruct do
      field(:server_name, String.t(), enforce: true)
      field(:id, String.t(), enforce: true)
      field(:message, String.t(), enforce: true)
    end

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        server_name: Map.fetch!(data, "server_name"),
        id: Map.fetch!(data, "id"),
        message: Map.fetch!(data, "message")
      }
    end
  end

  @spec encode_action(action()) :: String.t()
  def encode_action(:accept), do: "accept"
  def encode_action(:decline), do: "decline"
  def encode_action(:cancel), do: "cancel"

  @spec decode_action(String.t()) :: action()
  def decode_action("accept"), do: :accept
  def decode_action("decline"), do: :decline
  def decode_action("cancel"), do: :cancel
end

defmodule Codex.MCP.Client do
  @moduledoc """
  Minimal MCP client responsible for performing the handshake with external servers.
  """

  defstruct transport: nil, capabilities: []

  @type transport_ref :: {module(), term()}
  @type t :: %__MODULE__{transport: transport_ref(), capabilities: [String.t()]}

  @doc """
  Performs a handshake against the given transport.
  """
  @spec handshake(transport_ref(), keyword()) :: {:ok, t()} | {:error, term()}
  def handshake({mod, state} = transport, opts \\ []) when is_atom(mod) do
    request = %{
      "type" => "handshake",
      "client" => Keyword.get(opts, :client, "codex-elixir"),
      "version" => Keyword.get(opts, :version, "0.0.0")
    }

    :ok = mod.send(state, request)

    with {:ok, response} <- mod.recv(state),
         {:ok, caps} <- extract_capabilities(response) do
      {:ok, %__MODULE__{transport: transport, capabilities: caps}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns capabilities advertised by the MCP server.
  """
  @spec capabilities(t()) :: [String.t()]
  def capabilities(%__MODULE__{capabilities: caps}), do: caps

  defp extract_capabilities(%{"type" => "handshake.ack", "capabilities" => caps})
       when is_list(caps) do
    {:ok, Enum.map(caps, &to_string/1)}
  end

  defp extract_capabilities(_other), do: {:error, :invalid_handshake}
end

defmodule Codex.MCP.Client do
  @moduledoc """
  Minimal MCP client responsible for performing the handshake with external servers.
  """

  defstruct transport: nil, capabilities: %{}

  @type transport_ref :: {module(), term()}
  @type capabilities :: %{optional(String.t()) => term()}
  @type t :: %__MODULE__{transport: transport_ref(), capabilities: capabilities()}

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
  @spec capabilities(t()) :: capabilities()
  def capabilities(%__MODULE__{capabilities: caps}), do: caps

  defp extract_capabilities(%{"type" => "handshake.ack"} = response),
    do: extract_capabilities(response, Map.get(response, "capabilities"))

  defp extract_capabilities(%{"capabilities" => caps}), do: normalize_capabilities(caps)
  defp extract_capabilities(_other), do: {:error, :invalid_handshake}

  defp extract_capabilities(%{"capabilities" => caps}, _), do: normalize_capabilities(caps)
  defp extract_capabilities(_other, _caps), do: {:error, :invalid_handshake}

  defp normalize_capabilities(caps) when is_map(caps), do: {:ok, stringify_keys(caps)}

  defp normalize_capabilities(caps) when is_list(caps) do
    normalized =
      caps
      |> Enum.map(fn cap -> {to_string(cap), %{}} end)
      |> Map.new()

    {:ok, normalized}
  end

  defp normalize_capabilities(_other), do: {:error, :invalid_handshake}

  defp stringify_keys(value) when is_map(value) do
    Map.new(value, fn {key, val} -> {to_string(key), stringify_keys(val)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(other), do: other
end

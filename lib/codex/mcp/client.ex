defmodule Codex.MCP.Client do
  @moduledoc """
  Minimal MCP client responsible for performing the handshake with external servers and
  providing lightweight tool discovery/invocation helpers with caching and retries.
  """

  defstruct transport: nil, capabilities: %{}, tool_cache: %{}

  @type transport_ref :: {module(), term()}
  @type capabilities :: %{optional(String.t()) => term()}
  @type t :: %__MODULE__{
          transport: transport_ref(),
          capabilities: capabilities(),
          tool_cache: map()
        }

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

  @doc """
  Lists available tools, applying allow/block filters and caching results unless `cache?: false`
  is supplied.
  """
  @spec list_tools(t(), keyword()) :: {:ok, [map()], t()} | {:error, term()}
  def list_tools(%__MODULE__{} = client, opts \\ []) do
    cache? = Keyword.get(opts, :cache?, true)

    case {cache?, client.tool_cache} do
      {true, %{tools: tools}} when is_list(tools) ->
        {:ok, filter_tools(tools, opts), client}

      _ ->
        fetch_tools(client, opts)
    end
  end

  @doc """
  Calls a tool with optional retry/backoff and approval callbacks.
  """
  @spec call_tool(t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def call_tool(%__MODULE__{} = client, tool, args, opts \\ []) when is_binary(tool) do
    retries = Keyword.get(opts, :retries, 0)
    backoff = Keyword.get(opts, :backoff, fn _ -> :ok end)
    approval = Keyword.get(opts, :approval)
    context = Keyword.get(opts, :context, %{})

    with :ok <- run_approval(approval, tool, args, context) do
      do_call_tool(client, tool, args, retries, backoff, 0)
    end
  end

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

  defp fetch_tools(%__MODULE__{transport: {mod, state}} = client, opts) do
    :ok = mod.send(state, %{"type" => "list_tools"})

    with {:ok, response} <- mod.recv(state),
         {:ok, tools} <- normalize_tools(response) do
      filtered = filter_tools(tools, opts)
      updated = %{client | tool_cache: %{tools: filtered}}
      {:ok, filtered, updated}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_tools(%{"tools" => tools}) when is_list(tools) do
    {:ok,
     Enum.map(tools, fn
       %{} = tool -> stringify_keys(tool)
       other -> %{"name" => to_string(other)}
     end)}
  end

  defp normalize_tools(_), do: {:error, :invalid_tools_response}

  defp filter_tools(tools, opts) do
    allow = Keyword.get(opts, :allow)
    deny = Keyword.get(opts, :deny, [])
    filter_fun = Keyword.get(opts, :filter)

    tools
    |> Enum.filter(fn tool ->
      name = tool |> Map.get("name") |> to_string()

      cond do
        is_list(allow) and name not in Enum.map(allow, &to_string/1) -> false
        name in Enum.map(deny, &to_string/1) -> false
        is_function(filter_fun) -> truthy?(filter_fun.(tool))
        true -> true
      end
    end)
  end

  defp truthy?(value), do: value not in [false, nil]

  defp run_approval(nil, _tool, _args, _context), do: :ok

  defp run_approval(fun, tool, args, context) when is_function(fun) do
    case safe_apply(fun, tool, args, context) do
      {:deny, reason} -> {:error, {:approval_denied, reason}}
      :deny -> {:error, {:approval_denied, :denied}}
      false -> {:error, {:approval_denied, :denied}}
      _ -> :ok
    end
  end

  defp run_approval(_other, _tool, _args, _context), do: :ok

  defp do_call_tool(
         %__MODULE__{transport: {mod, state}} = client,
         tool,
         args,
         retries,
         backoff,
         attempt
       ) do
    :ok =
      mod.send(state, %{
        "type" => "call_tool",
        "tool" => tool,
        "arguments" => args
      })

    case mod.recv(state) do
      {:ok, %{"result" => result}} ->
        {:ok, stringify_keys(result)}

      {:ok, %{"error" => reason}} ->
        retry_or_error(client, tool, args, retries, backoff, attempt, reason)

      {:error, reason} ->
        retry_or_error(client, tool, args, retries, backoff, attempt, reason)
    end
  end

  defp retry_or_error(client, tool, args, retries, backoff, attempt, reason) do
    if attempt < retries do
      safe_backoff(backoff, attempt + 1)
      do_call_tool(client, tool, args, retries, backoff, attempt + 1)
    else
      {:error, reason}
    end
  end

  defp safe_backoff(fun, attempt) when is_function(fun, 1), do: fun.(attempt)
  defp safe_backoff(_fun, _attempt), do: :ok

  defp safe_apply(fun, tool, args, context) when is_function(fun, 3),
    do: fun.(tool, args, context)

  defp safe_apply(fun, tool, args, _context) when is_function(fun, 2), do: fun.(tool, args)
  defp safe_apply(fun, tool, _args, _context) when is_function(fun, 1), do: fun.(tool)
end

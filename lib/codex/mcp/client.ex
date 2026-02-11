defmodule Codex.MCP.Client do
  @moduledoc """
  MCP JSON-RPC client for stdio and streamable HTTP transports.

  ## Tool Name Qualification

  When `list_tools/2` is called with `qualify?: true`, tool names are qualified with
  the server name prefix in the format `mcp__<server>__<tool>`. This follows the
  OpenAI tool name constraint (`^[a-zA-Z0-9_-]+$`).

  If the qualified name exceeds 64 characters, it is truncated and a SHA1 hash suffix
  is appended to ensure uniqueness.

  ## Tool Invocation

  The `call_tool/4` function invokes tools on the MCP server with support for:

    * **Retry Logic** - Configurable retries with exponential backoff
    * **Approval Integration** - Optional approval callbacks before invocation
    * **Timeout Control** - Per-call timeout settings
    * **Telemetry** - Events emitted for observability

  ## Telemetry Events

  The following telemetry events are emitted during tool invocation:

    * `[:codex, :mcp, :tool_call, :start]` - When a tool call begins
      * Measurements: `%{system_time: integer()}`
      * Metadata: `%{tool: String.t(), arguments: map(), server_name: String.t() | nil}`

    * `[:codex, :mcp, :tool_call, :success]` - When a tool call succeeds
      * Measurements: `%{duration: integer()}`
      * Metadata: `%{tool: String.t(), arguments: map(), server_name: String.t() | nil, attempt: integer()}`

    * `[:codex, :mcp, :tool_call, :failure]` - When a tool call fails
      * Measurements: `%{duration: integer()}`
      * Metadata: `%{tool: String.t(), arguments: map(), server_name: String.t() | nil, reason: term(), attempt: integer()}`
  """

  alias Codex.Config.Defaults
  alias Codex.Telemetry
  alias Codex.Thread.Backoff

  defstruct transport: nil,
            capabilities: %{},
            tool_cache: %{},
            server_name: nil,
            server_info: nil,
            protocol_version: nil,
            instructions: nil

  @type transport_ref :: {module(), term()}
  @type capabilities :: %{optional(String.t()) => term()}

  @type t :: %__MODULE__{
          transport: transport_ref(),
          capabilities: capabilities(),
          tool_cache: map(),
          server_name: String.t() | nil,
          server_info: map() | nil,
          protocol_version: String.t() | nil,
          instructions: String.t() | nil
        }

  @mcp_tool_name_delimiter Defaults.mcp_tool_name_delimiter()
  @max_tool_name_length Defaults.mcp_max_tool_name_length()
  @mcp_protocol_version Defaults.mcp_protocol_version()
  @jsonrpc_version Defaults.jsonrpc_version()

  @default_init_timeout_ms Defaults.mcp_init_timeout_ms()
  @default_list_timeout_ms Defaults.mcp_list_timeout_ms()
  @default_timeout_ms Defaults.mcp_call_timeout_ms()
  @default_retries Defaults.mcp_default_retries()

  @doc """
  Performs MCP initialization against the given transport.

  This sends `initialize` and then emits the `notifications/initialized` notification.

  ## Options

    * `:client` - Client name to send during initialization (default: `"codex-elixir"`)
    * `:client_title` - Optional client title for UI display
    * `:version` - Client version (default: `"0.0.0"`)
    * `:capabilities` - Client capability map (default: `%{}`)
    * `:protocol_version` - MCP protocol version (default: `#{@mcp_protocol_version}`)
    * `:server_name` - Server name for tool name qualification (e.g., `"shell"`)
    * `:timeout_ms` - Timeout for initialization (default: `#{@default_init_timeout_ms}`)
  """
  @spec initialize(transport_ref(), keyword()) :: {:ok, t()} | {:error, term()}
  def initialize({mod, _state} = transport, opts \\ []) when is_atom(mod) do
    params = %{
      "protocolVersion" => Keyword.get(opts, :protocol_version, @mcp_protocol_version),
      "clientInfo" => client_info(opts),
      "capabilities" => normalize_client_capabilities(Keyword.get(opts, :capabilities, %{}))
    }

    timeout_ms = Keyword.get(opts, :timeout_ms, @default_init_timeout_ms)

    with {:ok, result} <- request_raw(transport, "initialize", params, timeout_ms),
         {:ok, caps} <- normalize_capabilities(Map.get(result, "capabilities")),
         :ok <- send_initialized_notification(transport) do
      server_name = Keyword.get(opts, :server_name)
      server_info = Map.get(result, "serverInfo")
      protocol_version = Map.get(result, "protocolVersion")
      instructions = Map.get(result, "instructions")

      {:ok,
       %__MODULE__{
         transport: transport,
         capabilities: caps,
         tool_cache: %{},
         server_name: server_name,
         server_info: server_info,
         protocol_version: protocol_version,
         instructions: instructions
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Backwards compatible alias for `initialize/2`.
  """
  @spec handshake(transport_ref(), keyword()) :: {:ok, t()} | {:error, term()}
  def handshake(transport, opts \\ []) do
    initialize(transport, opts)
  end

  @doc """
  Returns capabilities advertised by the MCP server.
  """
  @spec capabilities(t()) :: capabilities()
  def capabilities(%__MODULE__{capabilities: caps}), do: caps

  @doc """
  Lists available tools, applying allow/block filters and caching results unless `cache?: false`
  is supplied.

  ## Options

    * `:cache?` - Whether to use cached results (default: `true`)
    * `:allow` - List of tool names to allow (allowlist filter)
    * `:deny` - List of tool names to deny (blocklist filter)
    * `:filter` - Custom filter function `(tool -> boolean)`
    * `:qualify?` - Whether to add qualified names with server prefix (default: `false`)
    * `:cursor` - Pagination cursor (default: `nil`)
    * `:timeout_ms` - Request timeout (default: `#{@default_list_timeout_ms}`)

  ## Returns

    * `{:ok, tools, updated_client}` on success
    * `{:error, reason}` on failure
  """
  @spec list_tools(t(), keyword()) :: {:ok, [map()], t()} | {:error, term()}
  def list_tools(%__MODULE__{} = client, opts \\ []) do
    cache? = Keyword.get(opts, :cache?, true)
    qualify? = Keyword.get(opts, :qualify?, false)

    case {cache?, client.tool_cache} do
      {true, %{tools: tools}} when is_list(tools) ->
        filtered = filter_tools(tools, opts)
        processed = maybe_qualify_tools(filtered, client.server_name, qualify?)
        {:ok, processed, client}

      _ ->
        fetch_tools(client, opts, qualify?)
    end
  end

  @doc """
  Lists available resources via `resources/list`.

  ## Options

    * `:cursor` - Pagination cursor (default: `nil`)
    * `:timeout_ms` - Request timeout (default: `#{@default_list_timeout_ms}`)
  """
  @spec list_resources(t(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_resources(%__MODULE__{} = client, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_list_timeout_ms)
    params = build_cursor_params(opts)
    request(client, "resources/list", params, timeout_ms)
  end

  @doc """
  Lists available prompts via `prompts/list`.

  ## Options

    * `:cursor` - Pagination cursor (default: `nil`)
    * `:timeout_ms` - Request timeout (default: `#{@default_list_timeout_ms}`)
  """
  @spec list_prompts(t(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_prompts(%__MODULE__{} = client, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_list_timeout_ms)
    params = build_cursor_params(opts)
    request(client, "prompts/list", params, timeout_ms)
  end

  @doc """
  Invokes a tool on the MCP server.

  ## Options

    * `:retries` - Number of retry attempts (default: `#{@default_retries}`)
    * `:backoff` - Backoff function `(attempt -> :ok)` (default: exponential backoff)
    * `:timeout_ms` - Request timeout in milliseconds (default: `#{@default_timeout_ms}`)
    * `:approval` - Approval callback function `(tool, args, context) -> :ok | {:deny, reason}`
    * `:context` - Tool context map passed to approval callback (default: `%{}`)

  ## Backoff

  The default backoff uses exponential delays: 100ms, 200ms, 400ms, 800ms, ... up to 5000ms max.
  Provide a custom function to override: `backoff: fn attempt -> Process.sleep(attempt * 100) end`

  ## Approval Callbacks

  Approval callbacks are invoked before the first attempt. They can be:

    * A 3-arity function `(tool, args, context) -> result`
    * A 2-arity function `(tool, args) -> result`
    * A 1-arity function `(tool) -> result`

  Where result is one of:

    * `:ok` or any truthy value - Approved
    * `:deny` or `false` - Denied
    * `{:deny, reason}` - Denied with reason

  ## Telemetry

  Emits the following events:

    * `[:codex, :mcp, :tool_call, :start]` - When the call begins
    * `[:codex, :mcp, :tool_call, :success]` - On successful completion
    * `[:codex, :mcp, :tool_call, :failure]` - On failure (after all retries exhausted)

  ## Returns

    * `{:ok, result}` - Tool execution succeeded
    * `{:error, {:approval_denied, reason}}` - Approval callback denied the call
    * `{:error, reason}` - Tool execution failed after all retries

  ## Examples

      # Basic invocation with defaults
      {:ok, result} = Codex.MCP.Client.call_tool(client, "echo", %{"text" => "hello"})

      # With custom retry and backoff
      {:ok, result} = Codex.MCP.Client.call_tool(client, "fetch", %{"url" => url},
        retries: 5,
        backoff: fn attempt -> Process.sleep(attempt * 200) end,
        timeout_ms: 30_000
      )

      # With approval callback
      {:ok, result} = Codex.MCP.Client.call_tool(client, "write_file", args,
        approval: fn tool, args, _ctx ->
          if safe_tool?(tool, args), do: :ok, else: {:deny, "unsafe"}
        end
      )
  """
  @spec call_tool(t(), String.t(), map() | nil, keyword()) :: {:ok, map()} | {:error, term()}
  def call_tool(%__MODULE__{} = client, tool, args, opts \\ []) when is_binary(tool) do
    retries = Keyword.get(opts, :retries, @default_retries)
    backoff = Keyword.get(opts, :backoff, &exponential_backoff/1)
    approval = Keyword.get(opts, :approval)
    context = Keyword.get(opts, :context, %{})
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    with :ok <- run_approval(approval, tool, args, context) do
      emit_start_telemetry(client, tool, args || %{})
      started = System.monotonic_time()
      result = do_call_tool(client, tool, args, retries, backoff, timeout_ms, 0)
      emit_result_telemetry(result, client, tool, args || %{}, started, retries)
      result
    end
  end

  defp do_call_tool(%__MODULE__{} = client, tool, args, retries, backoff, timeout_ms, attempt) do
    params =
      %{"name" => tool}
      |> maybe_put("arguments", args)

    case request(client, "tools/call", params, timeout_ms) do
      {:ok, result} ->
        {:ok, stringify_keys(result)}

      {:error, reason} ->
        retry_or_error(client, tool, args, retries, backoff, timeout_ms, attempt, reason)
    end
  end

  defp exponential_backoff(attempt) do
    Backoff.sleep(attempt)
  end

  defp request(%__MODULE__{transport: transport}, method, params, timeout_ms) do
    request_raw(transport, method, params, timeout_ms)
  end

  defp request_raw({mod, _state} = transport, method, params, timeout_ms) when is_atom(mod) do
    id = new_request_id()

    message =
      %{
        "jsonrpc" => @jsonrpc_version,
        "id" => id,
        "method" => method
      }
      |> maybe_put("params", params)

    with :ok <- send_message(transport, message) do
      await_response(transport, id, timeout_ms)
    end
  end

  defp send_message({mod, state}, message) do
    mod.send(state, message)
  end

  defp send_initialized_notification({mod, state}) do
    notification = %{
      "jsonrpc" => @jsonrpc_version,
      "method" => "notifications/initialized"
    }

    mod.send(state, notification)
  end

  defp await_response(transport, id, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + max(timeout_ms, 0)
    do_await_response(transport, id, deadline)
  end

  defp do_await_response({mod, state} = transport, id, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    if remaining == 0 do
      {:error, :timeout}
    else
      case recv_with_timeout(mod, state, remaining) do
        {:ok, %{"id" => ^id, "result" => result}} ->
          {:ok, result}

        {:ok, %{"id" => ^id, "error" => error}} ->
          {:error, error}

        {:ok, %{"method" => _method}} ->
          do_await_response(transport, id, deadline)

        {:ok, %{"id" => _other_id}} ->
          do_await_response(transport, id, deadline)

        {:ok, _other} ->
          do_await_response(transport, id, deadline)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp recv_with_timeout(mod, state, timeout_ms) do
    if function_exported?(mod, :recv, 2) do
      mod.recv(state, timeout_ms)
    else
      mod.recv(state)
    end
  end

  defp normalize_client_capabilities(capabilities) when is_map(capabilities), do: capabilities
  defp normalize_client_capabilities(_), do: %{}

  defp normalize_capabilities(nil), do: {:ok, %{}}
  defp normalize_capabilities(%{} = caps), do: {:ok, stringify_keys(caps)}
  defp normalize_capabilities(_other), do: {:error, :invalid_capabilities}

  defp stringify_keys(value) when is_map(value) do
    Map.new(value, fn {key, val} -> {to_string(key), stringify_keys(val)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(other), do: other

  defp fetch_tools(%__MODULE__{} = client, opts, qualify?) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_list_timeout_ms)
    params = build_cursor_params(opts)

    with {:ok, result} <- request(client, "tools/list", params, timeout_ms),
         {:ok, tools} <- normalize_tools(result) do
      filtered = filter_tools(tools, opts)
      processed = maybe_qualify_tools(filtered, client.server_name, qualify?)
      updated = %{client | tool_cache: %{tools: filtered}}
      {:ok, processed, updated}
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

  defp normalize_tools(%{tools: tools}) when is_list(tools) do
    normalize_tools(%{"tools" => tools})
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

  defp retry_or_error(client, tool, args, retries, backoff, timeout_ms, attempt, reason) do
    if attempt < retries do
      safe_backoff(backoff, attempt + 1)
      do_call_tool(client, tool, args, retries, backoff, timeout_ms, attempt + 1)
    else
      {:error, reason}
    end
  end

  defp safe_backoff(fun, attempt) when is_function(fun, 1), do: fun.(attempt)
  defp safe_backoff(_fun, _attempt), do: :ok

  defp build_cursor_params(opts) do
    case Keyword.get(opts, :cursor) do
      nil -> nil
      cursor -> %{"cursor" => cursor}
    end
  end

  defp client_info(opts) do
    %{
      "name" => Keyword.get(opts, :client, Defaults.client_name()),
      "version" => Keyword.get(opts, :version, Defaults.client_version())
    }
    |> maybe_put("title", Keyword.get(opts, :client_title))
  end

  defp new_request_id do
    System.unique_integer([:positive])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, %{} = value) when map_size(value) == 0, do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Telemetry helpers

  defp emit_start_telemetry(client, tool, args) do
    Telemetry.emit(
      [:codex, :mcp, :tool_call, :start],
      %{system_time: System.system_time()},
      %{tool: tool, arguments: args, server_name: client.server_name}
    )
  end

  defp emit_result_telemetry({:ok, _result}, client, tool, args, started, retries) do
    duration = System.monotonic_time() - started
    attempt = retries + 1

    Telemetry.emit(
      [:codex, :mcp, :tool_call, :success],
      %{duration: duration, system_time: System.system_time()},
      %{tool: tool, arguments: args, server_name: client.server_name, attempt: attempt}
    )
  end

  defp emit_result_telemetry({:error, reason}, client, tool, args, started, retries) do
    duration = System.monotonic_time() - started
    attempt = retries + 1

    Telemetry.emit(
      [:codex, :mcp, :tool_call, :failure],
      %{duration: duration, system_time: System.system_time()},
      %{
        tool: tool,
        arguments: args,
        server_name: client.server_name,
        reason: reason,
        attempt: attempt
      }
    )
  end

  defp safe_apply(fun, tool, args, context) when is_function(fun, 3),
    do: fun.(tool, args, context)

  defp safe_apply(fun, tool, args, _context) when is_function(fun, 2), do: fun.(tool, args)
  defp safe_apply(fun, tool, _args, _context) when is_function(fun, 1), do: fun.(tool)

  # Tool name qualification functions

  @doc """
  Qualifies a tool name with the server prefix.

  Returns the fully qualified name in the format `mcp__<server>__<tool>`.
  If the qualified name exceeds 64 characters, it is truncated and a SHA1
  hash suffix is appended to ensure uniqueness.

  ## Examples

      iex> Codex.MCP.Client.qualify_tool_name("server1", "tool_a")
      "mcp__server1__tool_a"

      iex> long_tool = String.duplicate("a", 80)
      iex> result = Codex.MCP.Client.qualify_tool_name("srv", long_tool)
      iex> String.length(result)
      64
  """
  @spec qualify_tool_name(String.t(), String.t()) :: String.t()
  def qualify_tool_name(server_name, tool_name) do
    qualified =
      "mcp#{@mcp_tool_name_delimiter}#{server_name}#{@mcp_tool_name_delimiter}#{tool_name}"

    if String.length(qualified) > @max_tool_name_length do
      truncate_with_hash(qualified)
    else
      qualified
    end
  end

  defp truncate_with_hash(qualified_name) do
    sha1 = :crypto.hash(:sha, qualified_name) |> Base.encode16(case: :lower)
    prefix_len = @max_tool_name_length - String.length(sha1)
    String.slice(qualified_name, 0, prefix_len) <> sha1
  end

  defp maybe_qualify_tools(tools, _server_name, false), do: tools

  defp maybe_qualify_tools(tools, server_name, true) when is_binary(server_name) do
    {qualified_tools, _seen} =
      Enum.reduce(tools, {[], MapSet.new()}, fn tool, {acc, seen} ->
        tool_name = Map.get(tool, "name") |> to_string()
        qualified_name = qualify_tool_name(server_name, tool_name)

        if MapSet.member?(seen, qualified_name) do
          {acc, seen}
        else
          qualified_tool =
            tool
            |> Map.put("qualified_name", qualified_name)
            |> Map.put("server_name", server_name)

          {[qualified_tool | acc], MapSet.put(seen, qualified_name)}
        end
      end)

    Enum.reverse(qualified_tools)
  end

  defp maybe_qualify_tools(tools, nil, true), do: tools
end

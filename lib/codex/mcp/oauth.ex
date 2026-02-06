defmodule Codex.MCP.OAuth do
  @moduledoc """
  Stores and refreshes OAuth credentials for streamable HTTP MCP servers.
  """

  alias Codex.Auth
  alias Codex.Config.LayerStack
  alias Codex.Runtime.KeyringWarning

  @typedoc "Where to store OAuth credentials."
  @type store_mode :: :auto | :file | :keyring

  @typedoc "Stored OAuth credentials for an MCP server."
  @type tokens :: %{
          server_name: String.t(),
          url: String.t(),
          client_id: String.t(),
          access_token: String.t(),
          refresh_token: String.t() | nil,
          expires_at: non_neg_integer() | nil,
          scopes: [String.t()]
        }

  @refresh_skew_ms 30_000
  @oauth_discovery_header "MCP-Protocol-Version"
  @oauth_discovery_version "2024-11-05"

  @keyring_warning_key {__MODULE__, :keyring_warning_emitted}

  @doc """
  Loads OAuth tokens for the given MCP server name and URL.

  Returns `nil` when no tokens are stored or the entry cannot be decoded.
  """
  @spec load_tokens(String.t(), String.t(), store_mode() | nil) :: tokens() | nil
  def load_tokens(server_name, url, store_mode \\ nil) do
    with {:ok, store} <- read_store(store_mode),
         key <- compute_store_key(server_name, url),
         %{} = entry <- Map.get(store, key),
         {:ok, tokens} <- normalize_tokens(entry) do
      tokens
    else
      _ -> nil
    end
  end

  @doc """
  Stores OAuth tokens for the given MCP server name and URL.
  """
  @spec save_tokens(tokens(), store_mode() | nil) :: :ok | {:error, term()}
  def save_tokens(%{} = tokens, store_mode \\ nil) do
    with {:ok, store} <- read_store(store_mode) do
      key = compute_store_key(tokens.server_name, tokens.url)
      entry = tokens_to_entry(tokens)
      updated = Map.put(store, key, entry)
      write_store(updated, store_mode)
    end
  end

  @doc """
  Deletes stored OAuth tokens for the given MCP server name and URL.
  """
  @spec delete_tokens(String.t(), String.t(), store_mode() | nil) :: :ok | {:error, term()}
  def delete_tokens(server_name, url, store_mode \\ nil) do
    with {:ok, store} <- read_store(store_mode) do
      key = compute_store_key(server_name, url)
      updated = Map.delete(store, key)
      write_store(updated, store_mode)
    end
  end

  @doc """
  Refreshes OAuth tokens when they are near expiry.

  Returns the original tokens when refresh is not needed or not possible.
  """
  @spec refresh_if_needed(tokens() | nil, String.t(), keyword()) ::
          {:ok, tokens() | nil} | {:error, term()}
  def refresh_if_needed(nil, _url, _opts), do: {:ok, nil}

  def refresh_if_needed(%{expires_at: nil} = tokens, _url, _opts), do: {:ok, tokens}

  def refresh_if_needed(%{refresh_token: nil} = tokens, _url, _opts), do: {:ok, tokens}

  def refresh_if_needed(%{} = tokens, url, opts) do
    if token_needs_refresh?(tokens.expires_at) do
      do_refresh(tokens, url, opts)
    else
      {:ok, tokens}
    end
  end

  defp do_refresh(%{} = tokens, url, opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 10_000)
    headers = build_discovery_headers(opts)

    with {:ok, token_endpoint} <- discover_token_endpoint(url, headers, timeout_ms),
         {:ok, refreshed} <- refresh_token(tokens, token_endpoint, timeout_ms) do
      store_mode = Keyword.get(opts, :store_mode)

      case save_tokens(refreshed, store_mode) do
        :ok -> {:ok, refreshed}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp refresh_token(tokens, token_endpoint, timeout_ms) do
    form = [
      grant_type: "refresh_token",
      refresh_token: tokens.refresh_token,
      client_id: tokens.client_id
    ]

    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    opts = [headers: headers, form: form, receive_timeout: timeout_ms]

    case Req.post(token_endpoint, opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        with {:ok, response} <- normalize_json_body(body),
             {:ok, access_token} <- fetch_string(response, "access_token") do
          expires_at = compute_expires_at(Map.get(response, "expires_in"))

          refresh_token =
            Map.get(response, "refresh_token") || Map.get(response, :refresh_token) ||
              tokens.refresh_token

          scopes = normalize_scopes(response, tokens.scopes)

          {:ok,
           %{
             tokens
             | access_token: access_token,
               refresh_token: refresh_token,
               expires_at: expires_at,
               scopes: scopes
           }}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:oauth_refresh_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_scopes(response, fallback) do
    scope = Map.get(response, "scope") || Map.get(response, :scope)

    cond do
      is_binary(scope) ->
        scope
        |> String.split(" ", trim: true)

      is_list(scope) ->
        Enum.map(scope, &to_string/1)

      true ->
        fallback || []
    end
  end

  defp normalize_json_body(%{} = body), do: {:ok, stringify_keys(body)}

  defp normalize_json_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{} = decoded} -> {:ok, stringify_keys(decoded)}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_oauth_response}
    end
  end

  defp normalize_json_body(_), do: {:error, :invalid_oauth_response}

  defp fetch_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing_oauth_field, key}}
    end
  end

  defp discover_token_endpoint(url, headers, timeout_ms) do
    base = URI.parse(url)

    paths = discovery_paths(base.path || "")

    Enum.reduce_while(paths, {:error, :oauth_discovery_failed}, fn path, _acc ->
      discovery_url = URI.to_string(%URI{base | path: path, query: nil, fragment: nil})

      case fetch_token_endpoint(discovery_url, headers, timeout_ms) do
        {:ok, token_endpoint} -> {:halt, {:ok, token_endpoint}}
        :error -> {:cont, {:error, :oauth_discovery_failed}}
      end
    end)
  end

  defp fetch_token_endpoint(url, headers, timeout_ms) do
    with {:ok, %Req.Response{status: 200, body: body}} <-
           Req.get(url, headers: headers, receive_timeout: timeout_ms),
         {:ok, response} <- normalize_json_body(body),
         {:ok, token_endpoint} <- extract_token_endpoint(response) do
      {:ok, token_endpoint}
    else
      _ -> :error
    end
  end

  defp extract_token_endpoint(response) do
    case Map.get(response, "token_endpoint") || Map.get(response, :token_endpoint) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :missing_token_endpoint}
    end
  end

  defp discovery_paths(base_path) do
    trimmed = base_path |> String.trim_leading("/") |> String.trim_trailing("/")
    canonical = "/.well-known/oauth-authorization-server"

    if trimmed == "" do
      [canonical]
    else
      [
        "#{canonical}/#{trimmed}",
        "/#{trimmed}#{canonical}",
        canonical
      ]
    end
  end

  defp build_discovery_headers(opts) do
    headers =
      [{@oauth_discovery_header, @oauth_discovery_version}]
      |> add_headers(Keyword.get(opts, :http_headers))
      |> add_env_headers(Keyword.get(opts, :env_http_headers))

    headers
  end

  defp add_headers(headers, nil), do: headers

  defp add_headers(headers, %{} = map) do
    Enum.reduce(map, headers, fn {key, value}, acc ->
      [{to_string(key), to_string(value)} | acc]
    end)
  end

  defp add_headers(headers, list) when is_list(list), do: headers ++ list
  defp add_headers(headers, _), do: headers

  defp add_env_headers(headers, nil), do: headers

  defp add_env_headers(headers, %{} = map) do
    Enum.reduce(map, headers, fn {key, env_var}, acc ->
      case System.get_env(env_var) do
        value when is_binary(value) and value != "" ->
          [{to_string(key), value} | acc]

        _ ->
          acc
      end
    end)
  end

  defp add_env_headers(headers, _), do: headers

  defp token_needs_refresh?(expires_at_ms) when is_integer(expires_at_ms) do
    now_ms = System.system_time(:millisecond)
    now_ms + @refresh_skew_ms >= expires_at_ms
  end

  defp token_needs_refresh?(_), do: false

  defp compute_expires_at(expires_in) when is_integer(expires_in) and expires_in > 0 do
    System.system_time(:millisecond) + expires_in * 1_000
  end

  defp compute_expires_at(expires_in) when is_float(expires_in) and expires_in > 0 do
    System.system_time(:millisecond) + trunc(expires_in * 1_000)
  end

  defp compute_expires_at(_), do: nil

  defp normalize_tokens(%{} = entry) do
    with {:ok, server_name} <- fetch_string(entry, "server_name"),
         {:ok, server_url} <- fetch_string(entry, "server_url"),
         {:ok, client_id} <- fetch_string(entry, "client_id"),
         {:ok, access_token} <- fetch_string(entry, "access_token") do
      {:ok,
       %{
         server_name: server_name,
         url: server_url,
         client_id: client_id,
         access_token: access_token,
         refresh_token: Map.get(entry, "refresh_token"),
         expires_at: Map.get(entry, "expires_at"),
         scopes: Map.get(entry, "scopes") || []
       }}
    end
  end

  defp tokens_to_entry(%{} = tokens) do
    %{
      "server_name" => tokens.server_name,
      "server_url" => tokens.url,
      "client_id" => tokens.client_id,
      "access_token" => tokens.access_token,
      "expires_at" => tokens.expires_at,
      "refresh_token" => tokens.refresh_token,
      "scopes" => tokens.scopes || []
    }
  end

  defp read_store(store_mode) do
    case effective_store_mode(store_mode) do
      :file ->
        case read_file() do
          {:ok, %{} = store} -> {:ok, store}
          {:ok, nil} -> {:ok, %{}}
          {:error, _} = error -> error
        end

      :keyring ->
        warn_keyring_unsupported(:keyring)
        read_store(:file)

      :auto ->
        warn_keyring_unsupported(:auto)
        read_store(:file)
    end
  end

  defp write_store(store, store_mode) do
    case effective_store_mode(store_mode) do
      :file ->
        write_file(store)

      :keyring ->
        warn_keyring_unsupported(:keyring)
        write_file(store)

      :auto ->
        warn_keyring_unsupported(:auto)
        write_file(store)
    end
  end

  defp effective_store_mode(nil) do
    codex_home = Auth.codex_home()
    cwd = current_cwd()

    case LayerStack.load(codex_home, cwd) do
      {:ok, layers} ->
        layers
        |> LayerStack.effective_config()
        |> fetch_store_mode()

      {:error, _} ->
        :auto
    end
  end

  defp effective_store_mode(mode) when is_atom(mode), do: mode

  defp effective_store_mode(mode) when is_binary(mode) do
    case mode do
      "file" -> :file
      "auto" -> :auto
      "keyring" -> :keyring
      _ -> :auto
    end
  end

  defp fetch_store_mode(%{} = config) do
    case Map.get(config, "mcp_oauth_credentials_store") ||
           Map.get(config, :mcp_oauth_credentials_store) do
      "file" -> :file
      "keyring" -> :keyring
      "auto" -> :auto
      :file -> :file
      :keyring -> :keyring
      :auto -> :auto
      _ -> :auto
    end
  end

  defp read_file do
    path = credentials_path()

    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, %{} = decoded} -> {:ok, decoded}
          {:ok, _} -> {:ok, %{}}
          {:error, reason} -> {:error, reason}
        end

      {:error, :enoent} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_file(store) when map_size(store) == 0 do
    path = credentials_path()

    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_file(store) do
    path = credentials_path()
    dir = Path.dirname(path)
    _ = File.mkdir_p(dir)

    with {:ok, data} <- Jason.encode(store),
         :ok <- File.write(path, data) do
      maybe_chmod(path)
      :ok
    end
  end

  defp maybe_chmod(path) do
    if function_exported?(File, :chmod, 2) do
      _ = File.chmod(path, 0o600)
    end
  end

  defp credentials_path do
    Path.join(Auth.codex_home(), ".credentials.json")
  end

  defp compute_store_key(server_name, url) do
    payload =
      Jason.OrderedObject.new([
        {"type", "http"},
        {"url", url},
        {"headers", %{}}
      ])

    json = Jason.encode!(payload)
    sha = :crypto.hash(:sha256, json) |> Base.encode16(case: :lower)
    prefix = String.slice(sha, 0, 16)
    "#{server_name}|#{prefix}"
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, val} -> {to_string(key), stringify_keys(val)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(other), do: other

  defp current_cwd do
    case File.cwd() do
      {:ok, cwd} -> cwd
      _ -> nil
    end
  end

  defp keyring_supported? do
    Application.get_env(:codex_sdk, :keyring_supported?, false)
  end

  defp warn_keyring_unsupported(mode) do
    case :persistent_term.get(@keyring_warning_key, false) do
      true ->
        :ok

      false ->
        if mode in [:auto, :keyring] and keyring_supported?() do
          KeyringWarning.warn_once(
            @keyring_warning_key,
            "codex_sdk does not support keyring auth for MCP OAuth (mcp_oauth_credentials_store=#{mode}); falling back to file"
          )
        end
    end
  end
end

defmodule Codex.Net.CA do
  @moduledoc """
  Shared custom CA bundle resolution for subprocesses and outbound TLS clients.

  `CODEX_CA_CERTIFICATE` takes precedence over `SSL_CERT_FILE`. Blank values are
  treated as unset. When neither variable is set, callers should fall back to
  system trust roots.
  """

  @codex_ca_env "CODEX_CA_CERTIFICATE"
  @ssl_cert_file_env "SSL_CERT_FILE"

  @doc """
  Returns the effective CA certificate bundle path, if any.
  """
  @spec certificate_file() :: String.t() | nil
  def certificate_file, do: certificate_file(System.get_env())

  @spec certificate_file(map()) :: String.t() | nil
  def certificate_file(env) when is_map(env) do
    normalize(Map.get(env, @codex_ca_env)) || normalize(Map.get(env, @ssl_cert_file_env))
  end

  @doc """
  Returns subprocess environment overrides for the resolved CA bundle.
  """
  @spec env_overrides() :: %{optional(String.t()) => String.t()}
  def env_overrides, do: env_overrides(System.get_env())

  @doc """
  Returns subprocess environment overrides for the resolved CA bundle.
  """
  @spec env_overrides(map()) :: %{optional(String.t()) => String.t()}
  def env_overrides(env) when is_map(env) do
    case certificate_file(env) do
      nil ->
        %{}

      path ->
        %{
          @codex_ca_env => path,
          @ssl_cert_file_env => path
        }
    end
  end

  @doc """
  Returns Req `connect_options` for the resolved CA bundle.
  """
  @spec req_connect_options() :: keyword()
  def req_connect_options, do: req_connect_options(System.get_env())

  @spec req_connect_options(map()) :: keyword()
  def req_connect_options(env) when is_map(env) do
    case certificate_file(env) do
      nil -> []
      path -> [transport_opts: [cacertfile: path]]
    end
  end

  @doc """
  Merges CA-specific `connect_options` into an existing Req options keyword list.
  """
  @spec merge_req_options(keyword()) :: keyword()
  @spec merge_req_options(keyword(), map()) :: keyword()
  def merge_req_options(opts, env) when is_list(opts) and is_map(env) do
    case req_connect_options(env) do
      [] ->
        opts

      connect_options ->
        Keyword.update(opts, :connect_options, connect_options, fn existing ->
          merge_req_connect_options(existing, connect_options)
        end)
    end
  end

  def merge_req_options(opts \\ []) when is_list(opts) do
    merge_req_options(opts, System.get_env())
  end

  @doc """
  Returns `:httpc` SSL options for the resolved CA bundle.
  """
  @spec httpc_ssl_options() :: keyword()
  def httpc_ssl_options, do: httpc_ssl_options(System.get_env())

  @spec httpc_ssl_options(map()) :: keyword()
  def httpc_ssl_options(env) when is_map(env) do
    case certificate_file(env) do
      nil -> []
      path -> [cacertfile: path]
    end
  end

  @doc """
  Merges CA-specific SSL options into an `:httpc` options keyword list.
  """
  @spec merge_httpc_options(keyword()) :: keyword()
  @spec merge_httpc_options(keyword(), map()) :: keyword()
  def merge_httpc_options(opts, env) when is_list(opts) and is_map(env) do
    case httpc_ssl_options(env) do
      [] ->
        opts

      ssl_options ->
        Keyword.update(opts, :ssl, ssl_options, fn existing ->
          Keyword.merge(normalize_keyword(existing), ssl_options)
        end)
    end
  end

  def merge_httpc_options(opts \\ []) when is_list(opts) do
    merge_httpc_options(opts, System.get_env())
  end

  @doc """
  Returns websocket SSL options for the resolved CA bundle.
  """
  @spec websocket_ssl_options() :: keyword()
  def websocket_ssl_options, do: websocket_ssl_options(System.get_env())

  @spec websocket_ssl_options(map()) :: keyword()
  def websocket_ssl_options(env) when is_map(env) do
    case certificate_file(env) do
      nil -> []
      path -> [cacertfile: path]
    end
  end

  defp merge_req_connect_options(existing, connect_options) do
    existing = normalize_keyword(existing)
    transport_defaults = Keyword.get(connect_options, :transport_opts, [])

    Keyword.update(existing, :transport_opts, transport_defaults, fn transport_opts ->
      Keyword.merge(normalize_keyword(transport_opts), transport_defaults)
    end)
  end

  defp normalize(nil), do: nil

  defp normalize(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_keyword(value) when is_list(value), do: value
  defp normalize_keyword(_), do: []
end

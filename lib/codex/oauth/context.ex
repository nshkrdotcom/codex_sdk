defmodule Codex.OAuth.Context do
  @moduledoc false

  alias Codex.Auth.Store
  alias Codex.Config.Defaults
  alias Codex.Config.LayerStack
  alias Codex.Net.CA
  alias Codex.OAuth.Environment
  alias Codex.OAuth.Provider.OpenAI
  alias Codex.Runtime.Env, as: RuntimeEnv

  @enforce_keys [
    :cwd,
    :codex_home,
    :child_process_env,
    :effective_config,
    :api_base_url,
    :auth_issuer,
    :client_id,
    :credentials_store_mode,
    :ca_bundle_path,
    :interactive?,
    :environment,
    :provider
  ]
  defstruct [
    :cwd,
    :codex_home,
    :child_process_env,
    :effective_config,
    :api_base_url,
    :auth_issuer,
    :client_id,
    :credentials_store_mode,
    :ca_bundle_path,
    :interactive?,
    :environment,
    :provider,
    storage: :auto,
    presenter: nil,
    browser_opener: nil
  ]

  @type t :: %__MODULE__{
          cwd: String.t() | nil,
          codex_home: String.t(),
          child_process_env: map(),
          effective_config: map(),
          api_base_url: String.t(),
          auth_issuer: String.t(),
          client_id: String.t(),
          credentials_store_mode: Store.credentials_store_mode(),
          ca_bundle_path: String.t() | nil,
          interactive?: boolean(),
          environment: Environment.t(),
          provider: OpenAI.t(),
          storage: :auto | :file | :memory,
          presenter: term(),
          browser_opener: term()
        }

  @spec resolve(keyword()) :: {:ok, t()} | {:error, term()}
  def resolve(opts \\ []) when is_list(opts) do
    with {:ok, child_process_env} <- resolve_child_env(opts),
         {:ok, cwd} <- resolve_cwd(opts),
         codex_home <- resolve_codex_home(opts, child_process_env),
         {:ok, layers} <- LayerStack.load(codex_home, cwd) do
      effective_config = LayerStack.effective_config(layers)
      environment = resolve_environment(opts, child_process_env)
      auth_issuer = resolve_auth_issuer(opts, effective_config)
      client_id = Keyword.get(opts, :client_id, OpenAI.build(issuer: auth_issuer).client_id)

      provider =
        OpenAI.build(
          issuer: auth_issuer,
          client_id: client_id
        )

      {:ok,
       %__MODULE__{
         cwd: cwd,
         codex_home: codex_home,
         child_process_env: child_process_env,
         effective_config: effective_config,
         api_base_url: resolve_api_base_url(opts, effective_config, child_process_env),
         auth_issuer: auth_issuer,
         client_id: client_id,
         credentials_store_mode: Store.credentials_store_mode(codex_home, cwd),
         ca_bundle_path: CA.certificate_file(child_process_env),
         interactive?: environment.interactive?,
         environment: environment,
         provider: provider,
         storage: Keyword.get(opts, :storage, :auto),
         presenter: Keyword.get(opts, :presenter),
         browser_opener: Keyword.get(opts, :browser_opener)
       }}
    end
  end

  @spec resolve!(keyword()) :: t()
  def resolve!(opts \\ []) do
    case resolve(opts) do
      {:ok, context} ->
        context

      {:error, reason} ->
        raise ArgumentError, "failed to resolve OAuth context: #{inspect(reason)}"
    end
  end

  defp resolve_child_env(opts) do
    process_env = Keyword.get(opts, :process_env, Keyword.get(opts, :env))

    with {:ok, overrides} <- RuntimeEnv.normalize_overrides(process_env) do
      {:ok, Map.merge(System.get_env(), overrides)}
    end
  end

  defp resolve_cwd(opts) do
    case Keyword.get(opts, :cwd) do
      nil ->
        case File.cwd() do
          {:ok, cwd} -> {:ok, cwd}
          _ -> {:ok, nil}
        end

      cwd when is_binary(cwd) ->
        if String.trim(cwd) == "", do: {:error, {:invalid_cwd, cwd}}, else: {:ok, cwd}

      other ->
        {:error, {:invalid_cwd, other}}
    end
  end

  defp resolve_codex_home(opts, child_process_env) do
    case Keyword.get(opts, :codex_home) || Map.get(child_process_env, "CODEX_HOME") do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        home =
          Map.get(child_process_env, "HOME") || Map.get(child_process_env, "USERPROFILE") ||
            System.user_home!()

        Path.join(home, ".codex")
    end
  end

  defp resolve_environment(opts, child_process_env) do
    Environment.detect(
      os: Keyword.get(opts, :os),
      env: child_process_env,
      interactive?: Keyword.get(opts, :interactive?)
    )
  end

  defp resolve_api_base_url(opts, effective_config, child_process_env) do
    Keyword.get(opts, :api_base_url) ||
      Keyword.get(opts, :openai_base_url) ||
      Map.get(effective_config, "openai_base_url") ||
      Map.get(child_process_env, "OPENAI_BASE_URL") ||
      Defaults.openai_api_base_url()
  end

  defp resolve_auth_issuer(opts, effective_config) do
    Keyword.get(opts, :auth_issuer) ||
      Map.get(effective_config, "auth_issuer") ||
      OpenAI.default_issuer()
  end
end

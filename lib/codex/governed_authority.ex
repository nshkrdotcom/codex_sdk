defmodule Codex.GovernedAuthority do
  @moduledoc """
  Exact, transient Codex launch materialization for a governed account.

  The struct is the provider-family boundary between a credential materializer
  and Codex. It deliberately contains the secret-bearing child environment, so
  it is redacted from inspection and cannot be JSON encoded. Callers may not
  supplement any of its command, account, routing, root, or environment fields.
  """

  alias Codex.Runtime.Env, as: RuntimeEnv

  @reference_fields [
    :authority_ref,
    :credential_lease_ref,
    :native_auth_assertion_ref,
    :connector_instance_ref,
    :provider_account_ref,
    :connector_binding_ref,
    :target_ref,
    :operation_policy_ref,
    :materialization_ref,
    :endpoint_ref,
    :operation_ref,
    :account_namespace
  ]

  @materialized_fields [
    :command,
    :cwd,
    :env,
    :config_root,
    :auth_root,
    :base_url,
    :clear_env?,
    :generation,
    :fence,
    :issued_at,
    :expires_at
  ]

  @fields @reference_fields ++ @materialized_fields
  @input_aliases [
    :materialized_command,
    :materialized_cwd,
    :materialized_env,
    :credential_generation,
    :rotation_epoch,
    :fence_token,
    :lease_id
  ]

  @provider_env_keys ~w(
    CODEX_API_KEY
    OPENAI_API_KEY
    OPENAI_BASE_URL
    CODEX_HOME
    CODEX_PROVIDER_BACKEND
    CODEX_OSS_PROVIDER
    CODEX_OLLAMA_BASE_URL
  )

  @routing_option_keys [
    :api_key,
    :base_url,
    :codex_path,
    :codex_path_override,
    :command,
    :cwd,
    :working_directory,
    :process_env,
    :env,
    :codex_home,
    :config_root,
    :auth_root,
    :oauth,
    :auth_token,
    :auth_token_env,
    :execution_surface
  ]

  @secret_config_terms ~w(
    api_key apikey token secret password bearer authorization refresh access
    base_url baseurl provider_backend model_provider oss_provider ollama_base_url
    codex_home config_root auth_root
  )

  @enforce_keys @fields
  @derive {Inspect, except: [:command, :cwd, :env, :config_root, :auth_root, :base_url]}
  defstruct @fields

  @type t :: %__MODULE__{
          authority_ref: String.t(),
          credential_lease_ref: String.t(),
          native_auth_assertion_ref: String.t(),
          connector_instance_ref: String.t(),
          provider_account_ref: String.t(),
          connector_binding_ref: String.t(),
          target_ref: String.t(),
          operation_policy_ref: String.t(),
          materialization_ref: String.t(),
          endpoint_ref: String.t(),
          operation_ref: String.t(),
          account_namespace: String.t(),
          command: String.t(),
          cwd: String.t(),
          env: %{required(String.t()) => String.t()},
          config_root: String.t(),
          auth_root: String.t(),
          base_url: String.t(),
          clear_env?: true,
          generation: pos_integer(),
          fence: non_neg_integer(),
          issued_at: DateTime.t(),
          expires_at: DateTime.t()
        }

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, term()}
  def new(attrs), do: normalize(attrs)

  @doc """
  Builds a Codex launch materialization from the frozen Jido request and secret
  material contracts plus provider-specific launch fields.
  """
  @spec new(map() | struct(), map() | struct(), map() | keyword()) ::
          {:ok, t()} | {:error, term()}
  def new(request, secret_material, launch) when is_map(launch) or is_list(launch) do
    request = attrs(request)
    secret_material = attrs(secret_material)
    launch = attrs(launch)
    account = request |> value(:account, %{}) |> attrs()

    with :ok <- validate_jido_alignment(request, account, secret_material),
         {:ok, credential_env} <- credential_env(value(secret_material, :payload, %{})) do
      launch
      |> Map.merge(%{
        materialization_ref: value(request, :materialization_ref),
        credential_lease_ref: value(request, :lease_id),
        provider_account_ref: value(account, :account_ref),
        endpoint_ref: value(request, :endpoint_ref),
        authority_ref: value(request, :authority_ref),
        target_ref: value(request, :target_ref),
        operation_ref: value(request, :operation_ref),
        account_namespace: value(account, :account_ref),
        generation: value(account, :generation),
        fence: value(account, :fence),
        issued_at: value(request, :issued_at),
        expires_at: value(request, :expires_at)
      })
      |> Map.update(:env, credential_env, fn env ->
        env
        |> normalize_env!()
        |> Map.merge(credential_env)
      end)
      |> normalize()
    end
  end

  @spec normalize(term()) :: {:ok, t() | nil} | {:error, term()}
  def normalize(nil), do: {:ok, nil}
  def normalize(%__MODULE__{} = authority), do: validate(authority)

  def normalize(authority) when is_list(authority) do
    if Keyword.keyword?(authority) do
      authority |> Map.new() |> normalize()
    else
      {:error, :invalid_governed_materialization}
    end
  end

  def normalize(%{} = authority) do
    attrs = normalize_keys(authority)

    if known_fields?(attrs) do
      attrs
      |> materialization_from_attrs()
      |> validate()
    else
      {:error, :invalid_governed_materialization}
    end
  end

  def normalize(_authority), do: {:error, :invalid_governed_materialization}

  @spec fetch(map() | keyword()) :: {:ok, t() | nil} | {:error, term()}
  def fetch(attrs) when is_list(attrs), do: attrs |> Map.new() |> fetch()

  def fetch(%{} = attrs) do
    attrs
    |> fetch_first([
      :credential_materialization,
      "credential_materialization",
      :governed_materialization,
      "governed_materialization",
      :governed_authority,
      "governed_authority"
    ])
    |> normalize()
  end

  @spec present?(term()) :: boolean()
  def present?(%__MODULE__{}), do: true
  def present?(_value), do: false

  @spec validate_current(t() | nil) :: :ok | {:error, term()}
  def validate_current(nil), do: :ok

  def validate_current(%__MODULE__{} = authority) do
    case validate(authority) do
      {:ok, %__MODULE__{}} -> :ok
      {:error, _reason} = error -> error
    end
  end

  @spec child_env(t()) :: map()
  def child_env(%__MODULE__{env: env}), do: env

  @spec child_cwd(t()) :: String.t()
  def child_cwd(%__MODULE__{cwd: cwd}), do: cwd

  @spec command(t()) :: String.t()
  def command(%__MODULE__{command: command}), do: command

  @spec redacted(t() | nil) :: map() | nil
  def redacted(nil), do: nil

  def redacted(%__MODULE__{} = authority) do
    authority
    |> Map.take(@reference_fields ++ [:generation, :fence, :issued_at, :expires_at])
    |> Map.put(:env_keys, authority.env |> Map.keys() |> Enum.sort())
    |> Map.put(:clear_env?, true)
  end

  @spec validate_clear_env(t() | nil, term(), atom()) :: :ok | {:error, term()}
  def validate_clear_env(nil, _clear_env?, _surface), do: :ok
  def validate_clear_env(%__MODULE__{}, true, _surface), do: :ok

  def validate_clear_env(%__MODULE__{}, clear_env?, surface),
    do: {:error, {:governed_clear_env_required, surface, clear_env?}}

  @spec validate_runtime_env(t() | nil, map()) :: :ok | {:error, term()}
  def validate_runtime_env(nil, _env), do: :ok

  def validate_runtime_env(%__MODULE__{env: expected}, env) when is_map(env) do
    if env == expected,
      do: :ok,
      else: {:error, {:governed_launch_mismatch, :env, env_keys(env)}}
  end

  @spec validate_cwd(t() | nil, term(), atom()) :: :ok | {:error, term()}
  def validate_cwd(nil, _cwd, _surface), do: :ok
  def validate_cwd(%__MODULE__{cwd: cwd}, cwd, _surface), do: :ok

  def validate_cwd(%__MODULE__{}, cwd, surface),
    do: {:error, {:governed_launch_mismatch, surface, :cwd, redact_value(cwd)}}

  @spec validate_command_override(t() | nil, String.t() | nil, atom()) ::
          :ok | {:error, term()}
  def validate_command_override(nil, _command, _surface), do: :ok
  def validate_command_override(%__MODULE__{command: command}, command, _surface), do: :ok

  def validate_command_override(%__MODULE__{}, command, surface),
    do: {:error, {:governed_launch_mismatch, surface, :command, redact_value(command)}}

  @spec validate_execution_surface(t() | nil, term()) :: :ok | {:error, term()}
  def validate_execution_surface(nil, _surface), do: :ok

  def validate_execution_surface(%__MODULE__{} = authority, %{
        surface_kind: surface_kind,
        transport_options: transport_options,
        target_id: target,
        lease_ref: lease
      }) do
    cond do
      surface_kind != :local_subprocess ->
        {:error, {:governed_execution_surface_mismatch, :surface_kind}}

      transport_options not in [nil, []] ->
        {:error, {:governed_execution_surface_mismatch, :transport_options}}

      target not in [nil, authority.target_ref] ->
        {:error, {:governed_execution_surface_mismatch, :target_ref}}

      lease not in [nil, authority.credential_lease_ref] ->
        {:error, {:governed_execution_surface_mismatch, :credential_lease_ref}}

      true ->
        :ok
    end
  end

  @spec reject_config_overrides(t() | nil, list() | nil, atom()) ::
          :ok | {:error, term()}
  def reject_config_overrides(nil, _overrides, _surface), do: :ok

  def reject_config_overrides(%__MODULE__{}, overrides, _surface) when overrides in [nil, []],
    do: :ok

  def reject_config_overrides(%__MODULE__{}, overrides, surface) when is_list(overrides) do
    case Enum.find_value(overrides, &forbidden_config_key/1) do
      nil -> :ok
      key -> {:error, {:governed_config_override_forbidden, surface, key}}
    end
  end

  @spec reject_option_supplementation(t() | nil, keyword(), atom()) ::
          :ok | {:error, term()}
  def reject_option_supplementation(nil, _opts, _surface), do: :ok

  def reject_option_supplementation(%__MODULE__{}, opts, surface) when is_list(opts) do
    case Enum.find(@routing_option_keys, &present_option?(opts, &1)) do
      nil -> :ok
      key -> {:error, {:governed_option_supplementation, surface, key}}
    end
  end

  @spec governed_child_env(keyword(), atom()) :: {:ok, map()} | {:error, term()}
  def governed_child_env(opts, surface) when is_list(opts) do
    with {:ok, authority} <- fetch(opts) do
      case authority do
        nil ->
          opts
          |> Keyword.get(:process_env, Keyword.get(opts, :env, %{}))
          |> RuntimeEnv.normalize_overrides()

        %__MODULE__{} ->
          with :ok <- reject_option_supplementation(authority, opts, surface) do
            {:ok, authority.env}
          end
      end
    end
  end

  defimpl Jason.Encoder do
    def encode(_authority, _opts) do
      raise ArgumentError, "governed Codex materialization is transient and cannot be encoded"
    end
  end

  defp validate(%__MODULE__{} = authority) do
    with :ok <- require_refs(authority),
         :ok <- validate_generation(authority),
         :ok <- validate_times(authority),
         :ok <- validate_launch(authority) do
      {:ok, authority}
    end
  end

  defp validate(other), do: {:error, {:invalid_governed_materialization, other}}

  defp materialization_from_attrs(attrs) do
    %__MODULE__{
      authority_ref: value(attrs, :authority_ref),
      credential_lease_ref: value(attrs, :credential_lease_ref, value(attrs, :lease_id)),
      native_auth_assertion_ref: value(attrs, :native_auth_assertion_ref),
      connector_instance_ref: value(attrs, :connector_instance_ref),
      provider_account_ref: value(attrs, :provider_account_ref),
      connector_binding_ref: value(attrs, :connector_binding_ref),
      target_ref: value(attrs, :target_ref),
      operation_policy_ref: value(attrs, :operation_policy_ref),
      materialization_ref: value(attrs, :materialization_ref),
      endpoint_ref: value(attrs, :endpoint_ref),
      operation_ref: value(attrs, :operation_ref),
      account_namespace: value(attrs, :account_namespace),
      command: value(attrs, :command, value(attrs, :materialized_command)),
      cwd: value(attrs, :cwd, value(attrs, :materialized_cwd)),
      env: value(attrs, :env, value(attrs, :materialized_env, %{})) |> normalize_env!(),
      config_root: value(attrs, :config_root),
      auth_root: value(attrs, :auth_root),
      base_url: value(attrs, :base_url),
      clear_env?: value(attrs, :clear_env?, true),
      generation:
        value(
          attrs,
          :generation,
          value(attrs, :credential_generation, value(attrs, :rotation_epoch))
        ),
      fence: value(attrs, :fence, value(attrs, :fence_token, 0)),
      issued_at: value(attrs, :issued_at),
      expires_at: value(attrs, :expires_at)
    }
  end

  defp require_refs(authority) do
    missing = Enum.reject(@reference_fields, &present_string?(Map.get(authority, &1)))
    if missing == [], do: :ok, else: {:error, {:missing_governed_materialization_fields, missing}}
  end

  defp validate_generation(%{generation: generation, fence: fence})
       when is_integer(generation) and generation > 0 and is_integer(fence) and fence >= 0,
       do: :ok

  defp validate_generation(_authority), do: {:error, :invalid_governed_account_generation}

  defp validate_times(%{issued_at: %DateTime{} = issued_at, expires_at: %DateTime{} = expires_at}) do
    cond do
      DateTime.compare(expires_at, issued_at) != :gt ->
        {:error, :invalid_governed_materialization_expiry}

      DateTime.compare(expires_at, DateTime.utc_now()) != :gt ->
        {:error, :expired_governed_materialization}

      true ->
        :ok
    end
  end

  defp validate_times(_authority), do: {:error, :invalid_governed_materialization_expiry}

  defp validate_launch(authority) do
    cond do
      not valid_env?(authority.env) ->
        {:error, :invalid_governed_environment}

      not present_string?(authority.command) ->
        {:error, {:missing_governed_materialization_fields, [:command]}}

      not absolute_path?(authority.cwd) ->
        {:error, :invalid_governed_working_directory}

      not absolute_path?(authority.config_root) or not absolute_path?(authority.auth_root) ->
        {:error, :invalid_governed_account_roots}

      authority.config_root != authority.auth_root ->
        {:error, :governed_account_root_mismatch}

      authority.clear_env? != true ->
        {:error, :governed_clear_env_required}

      not present_string?(authority.base_url) ->
        {:error, :invalid_governed_endpoint}

      Map.get(authority.env, "CODEX_HOME") != authority.config_root ->
        {:error, :governed_codex_home_mismatch}

      Map.get(authority.env, "OPENAI_BASE_URL", authority.base_url) != authority.base_url ->
        {:error, :governed_endpoint_mismatch}

      map_size(authority.env) == 0 ->
        {:error, :empty_governed_environment}

      true ->
        :ok
    end
  end

  defp validate_jido_alignment(request, account, secret) do
    cond do
      value(account, :provider_family) not in ["codex", :codex] ->
        {:error, :invalid_codex_provider_family}

      value(request, :materialization_ref) != value(secret, :materialization_ref) ->
        {:error, :materialization_ref_mismatch}

      value(account, :provider_family) != value(secret, :provider_family) ->
        {:error, :materialization_provider_mismatch}

      value(account, :account_ref) != value(secret, :account_ref) ->
        {:error, :materialization_account_mismatch}

      value(account, :generation) != value(secret, :generation) ->
        {:error, :materialization_generation_mismatch}

      value(request, :endpoint_ref) != value(account, :endpoint_ref) ->
        {:error, :materialization_endpoint_mismatch}

      true ->
        :ok
    end
  end

  defp credential_env(payload) when is_map(payload) do
    payload = normalize_keys(payload)

    cond do
      is_map(value(payload, :env)) ->
        {:ok, value(payload, :env) |> normalize_env!() |> Map.take(@provider_env_keys)}

      present_string?(value(payload, :api_key)) ->
        api_key = value(payload, :api_key)
        {:ok, %{"CODEX_API_KEY" => api_key, "OPENAI_API_KEY" => api_key}}

      true ->
        {:error, :unsupported_codex_secret_material}
    end
  end

  defp credential_env(_payload), do: {:error, :unsupported_codex_secret_material}

  defp forbidden_config_key({key, _value}), do: forbidden_config_key(key)

  defp forbidden_config_key(value) do
    key = value |> to_string() |> String.split("=", parts: 2) |> hd() |> normalize_key()
    if Enum.any?(@secret_config_terms, &String.contains?(key, &1)), do: key
  end

  defp present_option?(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value not in [nil, "", [], %{}]
      :error -> false
    end
  end

  defp known_fields?(attrs) do
    allowed = MapSet.new(@fields ++ @input_aliases)
    Enum.all?(Map.keys(attrs), &MapSet.member?(allowed, &1))
  end

  defp normalize_keys(map) when is_map(map) do
    Map.new(map, fn {key, val} -> {normalize_key_atom(key), val} end)
  end

  defp normalize_key_atom(key) when is_atom(key), do: key

  defp normalize_key_atom(key) when is_binary(key) do
    case Enum.find(@fields ++ @input_aliases, &(Atom.to_string(&1) == key)) do
      nil -> key
      field -> field
    end
  end

  defp normalize_key_atom(key), do: key
  defp normalize_key(key), do: key |> to_string() |> String.trim() |> String.downcase()

  defp normalize_env!(env) do
    case RuntimeEnv.normalize_overrides(env) do
      {:ok, normalized} -> normalized
      {:error, _reason} -> env
    end
  end

  defp attrs(%_{} = struct), do: Map.from_struct(struct)
  defp attrs(value) when is_list(value), do: Map.new(value)
  defp attrs(value) when is_map(value), do: value
  defp attrs(_value), do: %{}

  defp value(attrs, key, default \\ nil) when is_map(attrs) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp fetch_first(attrs, [key | rest]) do
    case Map.get(attrs, key) do
      nil -> fetch_first(attrs, rest)
      value -> value
    end
  end

  defp fetch_first(_attrs, []), do: nil
  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""
  defp absolute_path?(value), do: present_string?(value) and Path.type(value) == :absolute

  defp valid_env?(env) when is_map(env) and map_size(env) > 0 do
    Enum.all?(env, fn {key, value} -> present_string?(key) and is_binary(value) end)
  end

  defp valid_env?(_env), do: false

  defp env_keys(env) when is_map(env),
    do: env |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()

  defp env_keys(_env), do: []
  defp redact_value(nil), do: nil
  defp redact_value(value) when is_binary(value), do: "[redacted:#{byte_size(value)}]"
  defp redact_value(_value), do: "[redacted]"
end

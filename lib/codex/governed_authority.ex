defmodule Codex.GovernedAuthority do
  @moduledoc false

  alias Codex.Runtime.Env, as: RuntimeEnv

  @required_ref_keys ~w(
    authority_ref
    credential_lease_ref
    native_auth_assertion_ref
    provider_account_ref
    connector_binding_ref
    target_ref
    materialization_ref
  )

  @command_ref_keys ~w(command_ref command_materialization_ref provider_command_ref)

  @ambient_env_keys ~w(
    CODEX_HOME
    CODEX_API_KEY
    OPENAI_API_KEY
    OPENAI_BASE_URL
    CODEX_MODEL
    OPENAI_DEFAULT_MODEL
    CODEX_MODEL_DEFAULT
    CODEX_PROVIDER_BACKEND
    CODEX_OSS_PROVIDER
    CODEX_OLLAMA_BASE_URL
    CODEX_PATH
  )

  @secret_key_terms ~w(api_key apikey token secret password bearer authorization refresh access)

  @allowed_secret_key_names ~w(
    authority_ref
    credential_lease_ref
    native_auth_assertion_ref
    provider_account_ref
    connector_binding_ref
    target_ref
    materialization_ref
    command_ref
    command_materialization_ref
    provider_command_ref
  )

  @type t :: %{required(String.t()) => String.t()}

  @spec normalize(term()) :: {:ok, t() | nil} | {:error, term()}
  def normalize(nil), do: {:ok, nil}

  def normalize(authority) when is_list(authority) do
    if Keyword.keyword?(authority) do
      authority
      |> Map.new()
      |> normalize()
    else
      {:error, {:invalid_governed_authority, authority}}
    end
  end

  def normalize(%{} = authority) do
    normalized =
      Map.new(authority, fn {key, value} ->
        {normalize_key(key), value}
      end)

    with :ok <- validate_required_refs(normalized),
         :ok <- reject_secret_key_names(normalized) do
      {:ok, normalized}
    end
  end

  def normalize(authority), do: {:error, {:invalid_governed_authority, authority}}

  @spec fetch(map() | keyword()) :: {:ok, t() | nil} | {:error, term()}
  def fetch(attrs) when is_list(attrs), do: attrs |> Map.new() |> fetch()

  def fetch(%{} = attrs) do
    attrs
    |> fetch_first([:governed_authority, "governed_authority", :authority_refs, "authority_refs"])
    |> normalize()
  end

  @spec present?(term()) :: boolean()
  def present?(nil), do: false
  def present?(%{}), do: true
  def present?(_value), do: false

  @spec validate_clear_env(t() | nil, term(), atom()) :: :ok | {:error, term()}
  def validate_clear_env(nil, _clear_env?, _surface), do: :ok
  def validate_clear_env(_authority, true, _surface), do: :ok

  def validate_clear_env(_authority, clear_env?, surface) do
    {:error, {:governed_clear_env_required, surface, clear_env?}}
  end

  @spec validate_runtime_env(t() | nil, map()) :: :ok | {:error, term()}
  def validate_runtime_env(nil, _materialized_env), do: :ok

  def validate_runtime_env(%{} = authority, materialized_env) when is_map(materialized_env) do
    with :ok <- validate_required_refs(authority) do
      reject_unmanaged_ambient_env(materialized_env)
    end
  end

  @spec validate_command_override(t() | nil, String.t() | nil, atom()) :: :ok | {:error, term()}
  def validate_command_override(nil, _command_override, _surface), do: :ok
  def validate_command_override(_authority, nil, _surface), do: :ok
  def validate_command_override(_authority, "", _surface), do: :ok

  def validate_command_override(%{} = authority, command_override, surface)
      when is_binary(command_override) do
    if Enum.any?(@command_ref_keys, &ref_present?(authority, &1)) do
      :ok
    else
      {:error, {:governed_command_ref_required, surface}}
    end
  end

  @spec reject_config_overrides(t() | nil, list(), atom()) :: :ok | {:error, term()}
  def reject_config_overrides(nil, _overrides, _surface), do: :ok
  def reject_config_overrides(_authority, nil, _surface), do: :ok

  def reject_config_overrides(%{} = _authority, overrides, surface) when is_list(overrides) do
    case Enum.find_value(overrides, &secret_config_key/1) do
      nil -> :ok
      key -> {:error, {:governed_secret_config_override, surface, key}}
    end
  end

  @spec governed_child_env(keyword(), atom()) :: {:ok, map()} | {:error, term()}
  def governed_child_env(opts, surface) when is_list(opts) do
    with {:ok, authority} <- fetch(opts),
         {:ok, env} <- normalize_process_env(opts),
         :ok <- validate_runtime_env(authority, env),
         :ok <- require_codex_home(authority, env, opts, surface) do
      {:ok, maybe_merge_system_env(authority, env)}
    end
  end

  defp validate_required_refs(authority) do
    missing = Enum.reject(@required_ref_keys, &ref_present?(authority, &1))

    case missing do
      [] -> :ok
      _ -> {:error, {:missing_governed_authority_refs, missing}}
    end
  end

  defp reject_secret_key_names(authority) do
    authority
    |> flatten_keys()
    |> Enum.find(&secret_key_name?/1)
    |> case do
      nil -> :ok
      key -> {:error, {:raw_secret_field_in_governed_authority, key}}
    end
  end

  defp reject_unmanaged_ambient_env(materialized_env) do
    ambient = System.get_env()

    Enum.find_value(@ambient_env_keys, fn key ->
      ambient_value = normalize_env_value(Map.get(ambient, key))
      materialized_value = normalize_env_value(Map.get(materialized_env, key))

      cond do
        ambient_value == nil ->
          nil

        materialized_value == ambient_value ->
          nil

        true ->
          {:error, {:unmanaged_governed_env, key}}
      end
    end) || :ok
  end

  defp require_codex_home(nil, _env, _opts, _surface), do: :ok

  defp require_codex_home(%{} = _authority, env, opts, surface) do
    codex_home = fetch_first(opts, [:codex_home, "codex_home"]) || Map.get(env, "CODEX_HOME")

    case normalize_env_value(codex_home) do
      nil -> {:error, {:governed_codex_home_required, surface}}
      _value -> :ok
    end
  end

  defp maybe_merge_system_env(nil, env), do: Map.merge(System.get_env(), env)
  defp maybe_merge_system_env(%{}, env), do: env

  defp normalize_process_env(opts) do
    opts
    |> Keyword.get(:process_env, Keyword.get(opts, :env, %{}))
    |> RuntimeEnv.normalize_overrides()
  end

  defp secret_config_key({key, _value}), do: secret_config_key(key)

  defp secret_config_key(value) when is_binary(value) do
    key =
      value
      |> String.split("=", parts: 2)
      |> List.first()
      |> normalize_key()

    if secret_key_name?(key), do: key
  end

  defp secret_config_key(value), do: secret_config_key(to_string(value))

  defp secret_key_name?(key) do
    key = normalize_key(key)

    if key in @allowed_secret_key_names do
      false
    else
      Enum.any?(@secret_key_terms, &String.contains?(key, &1))
    end
  end

  defp flatten_keys(%{} = map) do
    Enum.flat_map(map, fn {key, value} ->
      [normalize_key(key) | flatten_keys(value)]
    end)
  end

  defp flatten_keys(list) when is_list(list) do
    if Keyword.keyword?(list) do
      flatten_keys(Map.new(list))
    else
      []
    end
  end

  defp flatten_keys(_value), do: []

  defp ref_present?(authority, key) do
    case Map.get(authority, key) do
      value when is_binary(value) -> String.trim(value) != ""
      _ -> false
    end
  end

  defp fetch_first(attrs, keys) when is_list(attrs) do
    attrs
    |> Map.new()
    |> fetch_first(keys)
  end

  defp fetch_first(attrs, [key | rest]) do
    case Map.get(attrs, key) do
      nil -> fetch_first(attrs, rest)
      value -> value
    end
  end

  defp fetch_first(_attrs, []), do: nil

  defp normalize_key(key) when is_atom(key), do: key |> Atom.to_string() |> normalize_key()
  defp normalize_key(key) when is_binary(key), do: key |> String.trim() |> String.downcase()
  defp normalize_key(key), do: key |> to_string() |> normalize_key()

  defp normalize_env_value(nil), do: nil

  defp normalize_env_value(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_env_value(value), do: value |> to_string() |> normalize_env_value()
end

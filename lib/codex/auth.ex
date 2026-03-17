defmodule Codex.Auth do
  @moduledoc """
  API key resolution with `CODEX_API_KEY` → `auth.json` → `OPENAI_API_KEY` precedence.
  """

  alias Codex.Auth.Store
  alias Codex.Runtime.KeyringWarning

  @keyring_warning_key {__MODULE__, :keyring_warning_emitted}

  @spec codex_home() :: String.t()
  def codex_home do
    System.get_env("CODEX_HOME") || Path.join(System.user_home!(), ".codex")
  end

  @spec auth_paths() :: [String.t()]
  def auth_paths do
    Store.auth_paths(codex_home(), codex_home_explicit?: !!System.get_env("CODEX_HOME"))
  end

  @spec infer_auth_mode() :: :api | :chatgpt
  def infer_auth_mode do
    if api_key_env?(), do: :api, else: stored_auth_mode()
  end

  @spec api_key() :: String.t() | nil
  def api_key do
    api_key_env() || stored_api_key()
  end

  @spec direct_api_key() :: String.t() | nil
  def direct_api_key do
    api_key() || normalize_string(System.get_env("OPENAI_API_KEY"))
  end

  @spec chatgpt_access_token() :: String.t() | nil
  def chatgpt_access_token do
    with {:ok, %Store.Record{tokens: %Store.Tokens{} = tokens} = record} <- load_stored_auth(),
         true <- record.auth_mode in [:chatgpt, :chatgpt_auth_tokens] do
      tokens.access_token
    else
      _ -> nil
    end
  end

  defp api_key_env? do
    case api_key_env() do
      value when is_binary(value) and value != "" -> true
      _ -> false
    end
  end

  defp api_key_env do
    System.get_env("CODEX_API_KEY")
    |> normalize_string()
  end

  defp stored_api_key do
    case load_stored_auth() do
      {:ok, %Store.Record{auth_mode: :api_key, openai_api_key: api_key}} ->
        api_key

      _ ->
        nil
    end
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp credentials_store_mode do
    cwd =
      case File.cwd() do
        {:ok, value} -> value
        _ -> nil
      end

    Store.credentials_store_mode(codex_home(), cwd)
  end

  defp keyring_supported? do
    Store.keyring_supported?()
  end

  defp warn_keyring_unsupported(mode) do
    KeyringWarning.warn_once(
      @keyring_warning_key,
      "codex_sdk does not support keyring auth (cli_auth_credentials_store=#{mode}); remote model fetch is disabled"
    )
  end

  defp stored_auth_mode do
    case load_stored_auth() do
      {:ok, %Store.Record{} = record} -> Store.infer_auth_mode(record)
      _ -> :chatgpt
    end
  end

  defp load_stored_auth do
    case credentials_store_mode() do
      :keyring ->
        warn_keyring_unsupported(:keyring)
        {:ok, nil}

      :auto ->
        if keyring_supported?() do
          warn_keyring_unsupported(:auto)
          {:ok, nil}
        else
          Store.load(
            codex_home: codex_home(),
            codex_home_explicit?: !!System.get_env("CODEX_HOME")
          )
        end

      _ ->
        Store.load(codex_home: codex_home(), codex_home_explicit?: !!System.get_env("CODEX_HOME"))
    end
  end
end

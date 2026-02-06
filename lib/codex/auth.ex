defmodule Codex.Auth do
  @moduledoc false

  alias Codex.Config.LayerStack
  alias Codex.Runtime.KeyringWarning

  @keyring_warning_key {__MODULE__, :keyring_warning_emitted}

  @spec codex_home() :: String.t()
  def codex_home do
    System.get_env("CODEX_HOME") || Path.join(System.user_home!(), ".codex")
  end

  @spec auth_paths() :: [String.t()]
  def auth_paths do
    codex_home = codex_home()

    base_paths = [
      Path.join(codex_home, "auth.json"),
      Path.join(codex_home, ".credentials.json")
    ]

    if System.get_env("CODEX_HOME") do
      base_paths
    else
      (base_paths ++
         [
           Path.join(System.user_home!(), ".config/codex/credentials.json"),
           Path.join(System.user_home!(), ".config/openai/codex.json"),
           Path.join(System.user_home!(), ".codex/credentials.json")
         ])
      |> Enum.uniq()
    end
  end

  @spec infer_auth_mode() :: :api | :chatgpt
  def infer_auth_mode do
    if api_key_env?() || openai_api_key_from_auth() do
      :api
    else
      :chatgpt
    end
  end

  @spec api_key() :: String.t() | nil
  def api_key do
    api_key_env() || openai_api_key_from_auth()
  end

  @spec chatgpt_access_token() :: String.t() | nil
  def chatgpt_access_token do
    case credentials_store_mode() do
      :keyring ->
        warn_keyring_unsupported(:keyring)
        nil

      :auto ->
        if keyring_supported?() do
          warn_keyring_unsupported(:auto)
          nil
        else
          auth_paths()
          |> Enum.find_value(&read_chatgpt_access_token/1)
        end

      _ ->
        auth_paths()
        |> Enum.find_value(&read_chatgpt_access_token/1)
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

  defp openai_api_key_from_auth do
    case credentials_store_mode() do
      :keyring ->
        warn_keyring_unsupported(:keyring)
        nil

      :auto ->
        if keyring_supported?() do
          warn_keyring_unsupported(:auto)
          nil
        else
          auth_paths()
          |> Enum.find_value(&read_openai_api_key/1)
        end

      _ ->
        auth_paths()
        |> Enum.find_value(&read_openai_api_key/1)
    end
  end

  defp read_openai_api_key(path) do
    case read_auth_json(path) do
      %{} = decoded -> extract_openai_api_key(decoded)
      _ -> nil
    end
  end

  defp read_chatgpt_access_token(path) do
    case read_auth_json(path) do
      %{} = decoded -> extract_chatgpt_access_token(decoded)
      _ -> nil
    end
  end

  defp read_auth_json(path) do
    with true <- File.exists?(path),
         {:ok, contents} <- File.read(path),
         {:ok, decoded} <- Jason.decode(contents) do
      decoded
    else
      _ -> nil
    end
  end

  defp extract_openai_api_key(%{"OPENAI_API_KEY" => key}) when is_binary(key) and key != "" do
    String.trim(key)
  end

  defp extract_openai_api_key(%{"openai_api_key" => key}) when is_binary(key) and key != "" do
    String.trim(key)
  end

  defp extract_openai_api_key(_), do: nil

  defp extract_chatgpt_access_token(%{"tokens" => %{"access_token" => token}})
       when is_binary(token) and token != "" do
    String.trim(token)
  end

  defp extract_chatgpt_access_token(%{"tokens" => %{"token" => token}})
       when is_binary(token) and token != "" do
    String.trim(token)
  end

  defp extract_chatgpt_access_token(%{"access_token" => token})
       when is_binary(token) and token != "" do
    String.trim(token)
  end

  defp extract_chatgpt_access_token(%{"token" => token}) when is_binary(token) and token != "" do
    String.trim(token)
  end

  defp extract_chatgpt_access_token(_), do: nil

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

    case LayerStack.load(codex_home(), cwd) do
      {:ok, layers} ->
        layers
        |> LayerStack.effective_config()
        |> fetch_auth_store()

      {:error, _} ->
        :file
    end
  end

  defp fetch_auth_store(%{} = config) do
    case Map.get(config, "cli_auth_credentials_store") ||
           Map.get(config, :cli_auth_credentials_store) do
      "keyring" -> :keyring
      "auto" -> :auto
      "file" -> :file
      nil -> :file
      _ -> :file
    end
  end

  defp keyring_supported? do
    Application.get_env(:codex_sdk, :keyring_supported?, false)
  end

  defp warn_keyring_unsupported(mode) do
    KeyringWarning.warn_once(
      @keyring_warning_key,
      "codex_sdk does not support keyring auth (cli_auth_credentials_store=#{mode}); remote model fetch is disabled"
    )
  end
end

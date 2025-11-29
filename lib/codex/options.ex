defmodule Codex.Options do
  @moduledoc """
  Global configuration for Codex interactions.

  Options are built from caller-supplied values merged with environment defaults.
  """

  require Bitwise

  @default_base_url "https://api.openai.com/v1"

  @default_model System.get_env("CODEX_MODEL") || System.get_env("CODEX_MODEL_DEFAULT")

  @enforce_keys []
  defstruct api_key: nil,
            base_url: @default_base_url,
            codex_path_override: nil,
            telemetry_prefix: [:codex],
            model: @default_model

  @type t :: %__MODULE__{
          api_key: String.t() | nil,
          base_url: String.t(),
          codex_path_override: String.t() | nil,
          telemetry_prefix: [atom()],
          model: String.t()
        }

  @doc """
  Builds a validated options struct.

  The API key is required. It can be provided directly or via the `CODEX_API_KEY`
  environment variable.
  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}) do
    attrs = Map.new(attrs)

    with {:ok, api_key} <- fetch_api_key(attrs),
         {:ok, base_url} <- fetch_base_url(attrs),
         {:ok, override} <- fetch_codex_path_override(attrs),
         {:ok, telemetry_prefix} <- fetch_telemetry_prefix(attrs),
         {:ok, model} <- fetch_model(attrs) do
      {:ok,
       %__MODULE__{
         api_key: api_key,
         base_url: base_url,
         codex_path_override: override,
         telemetry_prefix: telemetry_prefix,
         model: model
       }}
    end
  end

  @doc """
  Determines the executable path to `codex-rs`.

  Order of precedence:
  1. Explicit override on the struct.
  2. `CODEX_PATH` environment variable.
  3. `System.find_executable("codex")`.
  """
  @spec codex_path(t()) :: {:ok, String.t()} | {:error, term()}
  def codex_path(%__MODULE__{codex_path_override: override}) when is_binary(override) do
    validate_executable(override)
  end

  def codex_path(%__MODULE__{} = opts) do
    env_path = System.get_env("CODEX_PATH")

    path =
      cond do
        env_path && env_path != "" -> env_path
        true -> System.find_executable("codex")
      end

    case path do
      nil -> {:error, :codex_binary_not_found}
      path -> validate_executable(path)
    end
    |> add_override_ref(opts)
  end

  defp add_override_ref(result, %__MODULE__{codex_path_override: nil}), do: result
  defp add_override_ref(result, _opts), do: result

  defp fetch_api_key(attrs) do
    case pick(attrs, [:api_key, "api_key"], System.get_env("CODEX_API_KEY")) do
      key when is_binary(key) and key != "" ->
        {:ok, key}

      _ ->
        {:ok, fetch_cli_api_key()}
    end
  end

  defp fetch_cli_api_key do
    cli_auth_paths()
    |> Enum.find_value(&read_auth_token/1)
  end

  defp cli_auth_paths do
    codex_home =
      System.get_env("CODEX_HOME") ||
        Path.join(System.user_home!(), ".codex")

    [
      Path.join(codex_home, "auth.json"),
      Path.join(codex_home, ".credentials.json"),
      Path.join(System.user_home!(), ".config/codex/credentials.json"),
      Path.join(System.user_home!(), ".config/openai/codex.json"),
      Path.join(System.user_home!(), ".codex/credentials.json")
    ]
    |> Enum.uniq()
  end

  defp read_auth_token(path) do
    with true <- File.exists?(path),
         {:ok, contents} <- File.read(path),
         {:ok, decoded} <- Jason.decode(contents),
         token when is_binary(token) and token != "" <- extract_token(decoded) do
      token
    else
      _ -> nil
    end
  end

  defp extract_token(%{"OPENAI_API_KEY" => token}), do: token
  defp extract_token(%{"access_token" => token}), do: token

  defp extract_token(%{"tokens" => %{"access_token" => token}}), do: token
  defp extract_token(%{"tokens" => %{"token" => token}}), do: token
  defp extract_token(_), do: nil

  defp fetch_base_url(attrs) do
    case pick(attrs, [:base_url, "base_url"], @default_base_url) do
      url when is_binary(url) and url != "" -> {:ok, url}
      _ -> {:error, :invalid_base_url}
    end
  end

  defp fetch_codex_path_override(attrs) do
    case pick(attrs, [:codex_path_override, "codex_path_override", :codex_path, "codex_path"]) do
      nil -> {:ok, nil}
      "" -> {:error, :invalid_codex_path}
      override -> {:ok, override}
    end
  end

  defp fetch_telemetry_prefix(attrs) do
    case pick(attrs, [:telemetry_prefix, "telemetry_prefix"], [:codex]) do
      prefix when is_list(prefix) ->
        if Enum.all?(prefix, &is_atom/1) do
          {:ok, prefix}
        else
          {:error, {:invalid_telemetry_prefix, prefix}}
        end

      other ->
        {:error, {:invalid_telemetry_prefix, other}}
    end
  end

  defp validate_executable(path) do
    with true <- File.exists?(path) || {:error, {:codex_binary_missing, path}},
         {:ok, stat} <- File.stat(path),
         true <- stat.type == :regular || {:error, {:codex_binary_not_regular, path}},
         true <-
           Bitwise.band(stat.mode, 0o111) > 0 || {:error, {:codex_binary_not_executable, path}} do
      {:ok, path}
    else
      {:error, _} = error -> error
      false -> {:error, {:codex_binary_missing, path}}
      error when is_atom(error) -> {:error, error}
    end
  end

  defp pick(attrs, keys, default \\ nil)

  defp pick(attrs, [key | rest], default) do
    case Map.get(attrs, key) do
      nil -> pick(attrs, rest, default)
      value -> value
    end
  end

  defp pick(_attrs, [], default), do: default

  defp fetch_model(attrs) do
    default = System.get_env("CODEX_MODEL") || @default_model

    case pick(attrs, [:model, "model"], default) do
      nil -> {:ok, nil}
      "" -> {:ok, nil}
      model -> {:ok, model}
    end
  end
end

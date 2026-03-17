defmodule Codex.Auth.Store do
  @moduledoc false

  alias Codex.Config.LayerStack

  @type auth_mode :: :api_key | :chatgpt | :chatgpt_auth_tokens
  @type credentials_store_mode :: :file | :keyring | :auto
  @api_auth_modes ~w(apikey apiKey api_key api)
  @chatgpt_auth_modes ~w(chatgpt)
  @chatgpt_token_auth_modes ~w(chatgptAuthTokens chatgpt_auth_tokens)

  defmodule Tokens do
    @moduledoc false

    @enforce_keys []
    defstruct access_token: nil,
              refresh_token: nil,
              id_token: nil,
              account_id: nil,
              chatgpt_account_id: nil,
              chatgpt_user_id: nil,
              email: nil,
              plan_type: nil,
              expires_at: nil

    @type t :: %__MODULE__{
            access_token: String.t() | nil,
            refresh_token: String.t() | nil,
            id_token: String.t() | nil,
            account_id: String.t() | nil,
            chatgpt_account_id: String.t() | nil,
            chatgpt_user_id: String.t() | nil,
            email: String.t() | nil,
            plan_type: String.t() | nil,
            expires_at: DateTime.t() | nil
          }
  end

  defmodule Record do
    @moduledoc false

    @enforce_keys []
    defstruct auth_mode: nil,
              openai_api_key: nil,
              tokens: nil,
              last_refresh: nil,
              path: nil

    @type t :: %__MODULE__{
            auth_mode: Codex.Auth.Store.auth_mode(),
            openai_api_key: String.t() | nil,
            tokens: Codex.Auth.Store.Tokens.t() | nil,
            last_refresh: DateTime.t() | nil,
            path: String.t() | nil
          }
  end

  @spec auth_paths(String.t(), keyword()) :: [String.t()]
  def auth_paths(codex_home, opts \\ []) when is_binary(codex_home) and is_list(opts) do
    base_paths = [
      primary_path(codex_home),
      Path.join(codex_home, ".credentials.json")
    ]

    if Keyword.get(opts, :codex_home_explicit?, false) do
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

  @spec primary_path(String.t()) :: String.t()
  def primary_path(codex_home) when is_binary(codex_home) do
    Path.join(codex_home, "auth.json")
  end

  @spec load(keyword()) :: {:ok, Record.t() | nil} | {:error, term()}
  def load(opts \\ []) when is_list(opts) do
    codex_home = Keyword.fetch!(opts, :codex_home)

    paths =
      Keyword.get_lazy(opts, :paths, fn ->
        auth_paths(codex_home,
          codex_home_explicit?: Keyword.get(opts, :codex_home_explicit?, false)
        )
      end)

    load_from_paths(paths)
  end

  @spec load_path(String.t()) :: {:ok, Record.t() | nil} | {:error, term()}
  def load_path(path) when is_binary(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, decoded} <- Jason.decode(contents) do
      {:ok, decode_record(decoded, path)}
    else
      {:error, :enoent} -> {:ok, nil}
      {:error, _} = error -> error
    end
  end

  @spec load_from_paths([String.t()]) :: {:ok, Record.t() | nil} | {:error, term()}
  def load_from_paths(paths) when is_list(paths) do
    Enum.reduce_while(paths, {:ok, nil}, fn path, _acc ->
      case load_path(path) do
        {:ok, nil} -> {:cont, {:ok, nil}}
        {:ok, %Record{} = record} -> {:halt, {:ok, record}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec write(Record.t(), keyword()) :: :ok | {:error, term()}
  def write(%Record{} = record, opts) when is_list(opts) do
    codex_home = Keyword.fetch!(opts, :codex_home)
    path = primary_path(codex_home)
    tmp_path = path <> ".tmp"

    case File.mkdir_p(Path.dirname(path)) do
      :ok ->
        write_atomic_json(tmp_path, path, encode_record(record))

      {:error, _} = error ->
        error
    end
  end

  @spec delete(keyword()) :: :ok | {:error, atom()}
  def delete(opts) when is_list(opts) do
    path =
      opts
      |> Keyword.fetch!(:codex_home)
      |> primary_path()

    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, _} = error -> error
    end
  end

  @spec infer_auth_mode(Record.t() | nil) :: :api | :chatgpt
  def infer_auth_mode(%Record{auth_mode: :api_key}), do: :api
  def infer_auth_mode(%Record{}), do: :chatgpt
  def infer_auth_mode(nil), do: :chatgpt

  @spec build_record(keyword()) :: Record.t()
  def build_record(opts) when is_list(opts) do
    openai_api_key = normalize_string(Keyword.get(opts, :openai_api_key))

    %Record{
      auth_mode: Keyword.get(opts, :auth_mode, resolve_auth_mode(nil, openai_api_key)),
      openai_api_key: openai_api_key,
      tokens:
        decode_tokens(
          %{}
          |> put_optional("id_token", Keyword.get(opts, :id_token))
          |> put_optional("access_token", Keyword.get(opts, :access_token))
          |> put_optional("refresh_token", Keyword.get(opts, :refresh_token))
          |> put_optional("account_id", Keyword.get(opts, :account_id)),
          openai_api_key
        ),
      last_refresh: Keyword.get(opts, :last_refresh),
      path: Keyword.get(opts, :path)
    }
  end

  @spec credentials_store_mode(String.t(), String.t() | nil) :: credentials_store_mode()
  def credentials_store_mode(codex_home, cwd \\ nil) when is_binary(codex_home) do
    case LayerStack.load(codex_home, cwd) do
      {:ok, layers} ->
        layers
        |> LayerStack.effective_config()
        |> fetch_auth_store()

      {:error, _} ->
        :file
    end
  end

  @spec keyring_supported?() :: boolean()
  def keyring_supported? do
    Application.get_env(:codex_sdk, :keyring_supported?, false)
  end

  defp decode_record(%{} = decoded, path) do
    openai_api_key = extract_openai_api_key(decoded)
    tokens = decode_tokens(Map.get(decoded, "tokens"), openai_api_key)

    %Record{
      auth_mode: resolve_auth_mode(Map.get(decoded, "auth_mode"), openai_api_key),
      openai_api_key: openai_api_key,
      tokens: tokens,
      last_refresh: decode_datetime(Map.get(decoded, "last_refresh")),
      path: path
    }
  end

  defp decode_tokens(nil, _openai_api_key), do: nil

  defp decode_tokens(%{} = tokens, openai_api_key) do
    id_token = normalize_string(Map.get(tokens, "id_token"))
    access_token = normalize_string(Map.get(tokens, "access_token") || Map.get(tokens, "token"))
    refresh_token = normalize_string(Map.get(tokens, "refresh_token"))
    id_claims = decode_jwt_claims(id_token)
    access_claims = decode_jwt_claims(access_token)

    %Tokens{
      access_token: access_token,
      refresh_token: refresh_token,
      id_token: id_token,
      account_id: token_account_id(tokens, access_claims, id_claims),
      chatgpt_account_id: token_chatgpt_account_id(access_claims, id_claims),
      chatgpt_user_id: token_chatgpt_user_id(access_claims, id_claims),
      email: token_email(id_claims),
      plan_type: token_plan_type(access_claims, id_claims, openai_api_key),
      expires_at: decode_expiry(access_claims)
    }
  end

  defp encode_record(%Record{} = record) do
    %{}
    |> put_optional("auth_mode", encode_auth_mode(record.auth_mode))
    |> put_optional("OPENAI_API_KEY", normalize_string(record.openai_api_key))
    |> put_optional("tokens", encode_tokens(record.tokens))
    |> put_optional("last_refresh", encode_datetime(record.last_refresh))
  end

  defp encode_tokens(nil), do: nil

  defp encode_tokens(%Tokens{} = tokens) do
    %{}
    |> put_optional("id_token", normalize_string(tokens.id_token))
    |> put_optional("access_token", normalize_string(tokens.access_token))
    |> put_optional("refresh_token", normalize_string(tokens.refresh_token))
    |> put_optional("account_id", normalize_string(tokens.account_id))
  end

  defp write_atomic_json(tmp_path, path, payload) do
    encoded = Jason.encode_to_iodata!(payload)

    case :file.open(String.to_charlist(tmp_path), [:write, :binary, :exclusive]) do
      {:ok, io_device} ->
        result = do_write_atomic_json(io_device, encoded, tmp_path, path)

        if result != :ok do
          _ = File.rm(tmp_path)
        end

        result

      {:error, _} = error ->
        error
    end
  end

  defp maybe_chmod(path) do
    case :os.type() do
      {:unix, _} -> File.chmod(path, 0o600)
      _ -> :ok
    end
  end

  defp resolve_auth_mode(raw_auth_mode, openai_api_key) do
    normalized_auth_mode = normalize_string(raw_auth_mode)

    cond do
      normalized_auth_mode in @api_auth_modes ->
        :api_key

      normalized_auth_mode in @chatgpt_auth_modes ->
        :chatgpt

      normalized_auth_mode in @chatgpt_token_auth_modes ->
        :chatgpt_auth_tokens

      is_binary(openai_api_key) ->
        :api_key

      true ->
        :chatgpt
    end
  end

  defp encode_auth_mode(:api_key), do: "apikey"
  defp encode_auth_mode(:chatgpt), do: "chatgpt"
  defp encode_auth_mode(:chatgpt_auth_tokens), do: "chatgptAuthTokens"
  defp encode_auth_mode(_), do: nil

  defp extract_openai_api_key(%{"OPENAI_API_KEY" => key}), do: normalize_string(key)
  defp extract_openai_api_key(%{"openai_api_key" => key}), do: normalize_string(key)
  defp extract_openai_api_key(_), do: nil

  defp decode_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp decode_datetime(_), do: nil

  defp encode_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp encode_datetime(_), do: nil

  defp decode_jwt_claims(nil), do: %{}

  defp decode_jwt_claims(jwt) when is_binary(jwt) do
    case String.split(jwt, ".", parts: 3) do
      [_header, payload, _signature] ->
        with {:ok, bytes} <- Base.url_decode64(payload, padding: false),
             {:ok, %{} = decoded} <- Jason.decode(bytes) do
          decoded
        else
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp chatgpt_claim(%{} = claims, key) when is_binary(key) do
    claims
    |> Map.get("https://api.openai.com/auth", %{})
    |> Map.get(key)
    |> normalize_string()
  end

  defp decode_expiry(%{} = claims) do
    case Map.get(claims, "exp") do
      value when is_integer(value) ->
        case DateTime.from_unix(value) do
          {:ok, datetime} -> datetime
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp token_account_id(tokens, access_claims, id_claims) do
    normalize_string(Map.get(tokens, "account_id")) ||
      token_chatgpt_account_id(access_claims, id_claims)
  end

  defp token_chatgpt_account_id(access_claims, id_claims) do
    chatgpt_claim(access_claims, "chatgpt_account_id") ||
      chatgpt_claim(id_claims, "chatgpt_account_id")
  end

  defp token_chatgpt_user_id(access_claims, id_claims) do
    chatgpt_claim(id_claims, "chatgpt_user_id") ||
      chatgpt_claim(id_claims, "user_id") ||
      chatgpt_claim(access_claims, "chatgpt_user_id") ||
      chatgpt_claim(access_claims, "user_id")
  end

  defp token_email(id_claims) do
    normalize_string(Map.get(id_claims, "email")) ||
      id_claims
      |> Map.get("https://api.openai.com/profile", %{})
      |> Map.get("email")
      |> normalize_string()
  end

  defp token_plan_type(access_claims, id_claims, _openai_api_key) do
    chatgpt_claim(access_claims, "chatgpt_plan_type") ||
      chatgpt_claim(id_claims, "chatgpt_plan_type")
  end

  defp do_write_atomic_json(io_device, encoded, tmp_path, path) do
    with :ok <- :file.write(io_device, encoded),
         :ok <- :file.sync(io_device),
         :ok <- close_io_device(io_device),
         :ok <- maybe_chmod(tmp_path) do
      rename_tmp_file(tmp_path, path)
    end
  end

  defp close_io_device(io_device), do: :file.close(io_device)
  defp rename_tmp_file(tmp_path, path), do: File.rename(tmp_path, path)

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

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, _key, ""), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_string()

  defp normalize_string(_), do: nil
end

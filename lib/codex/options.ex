defmodule Codex.Options do
  @moduledoc """
  Global configuration for Codex interactions.

  Options are built from caller-supplied values merged with environment defaults.
  """

  require Bitwise
  alias Codex.Auth
  alias Codex.Models

  @default_base_url "https://api.openai.com/v1"

  @enforce_keys []
  defstruct api_key: nil,
            base_url: @default_base_url,
            codex_path_override: nil,
            telemetry_prefix: [:codex],
            model: Models.default_model(),
            reasoning_effort: Models.default_reasoning_effort(),
            model_reasoning_summary: nil,
            model_verbosity: nil,
            model_context_window: nil,
            model_supports_reasoning_summaries: nil,
            history_persistence: nil,
            history_max_bytes: nil

  @type t :: %__MODULE__{
          api_key: String.t() | nil,
          base_url: String.t(),
          codex_path_override: String.t() | nil,
          telemetry_prefix: [atom()],
          model: String.t() | nil,
          reasoning_effort: Models.reasoning_effort() | nil,
          model_reasoning_summary: String.t() | nil,
          model_verbosity: String.t() | nil,
          model_context_window: pos_integer() | nil,
          model_supports_reasoning_summaries: boolean() | nil,
          history_persistence: String.t() | nil,
          history_max_bytes: non_neg_integer() | nil
        }

  @doc """
  Builds a validated options struct.

  API keys are optional. When omitted, the Codex CLI relies on your existing
  `codex` login (ChatGPT tokens stored in `auth.json`).
  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}) do
    attrs = Map.new(attrs)

    with {:ok, api_key} <- fetch_api_key(attrs),
         {:ok, base_url} <- fetch_base_url(attrs),
         {:ok, override} <- fetch_codex_path_override(attrs),
         {:ok, telemetry_prefix} <- fetch_telemetry_prefix(attrs),
         {:ok, model} <- fetch_model(attrs, auth_mode_for(api_key)),
         {:ok, reasoning_effort} <- fetch_reasoning_effort(attrs, model),
         {:ok, reasoning_summary} <- fetch_reasoning_summary(attrs),
         {:ok, model_verbosity} <- fetch_model_verbosity(attrs),
         {:ok, model_context_window} <- fetch_model_context_window(attrs),
         {:ok, supports_reasoning_summaries} <- fetch_supports_reasoning_summaries(attrs),
         {:ok, history_persistence} <- fetch_history_persistence(attrs),
         {:ok, history_max_bytes} <- fetch_history_max_bytes(attrs) do
      {:ok,
       %__MODULE__{
         api_key: api_key,
         base_url: base_url,
         codex_path_override: override,
         telemetry_prefix: telemetry_prefix,
         model: model,
         reasoning_effort: reasoning_effort,
         model_reasoning_summary: reasoning_summary,
         model_verbosity: model_verbosity,
         model_context_window: model_context_window,
         model_supports_reasoning_summaries: supports_reasoning_summaries,
         history_persistence: history_persistence,
         history_max_bytes: history_max_bytes
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
      if env_path && env_path != "" do
        env_path
      else
        System.find_executable("codex")
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
    case normalize_string(pick(attrs, [:api_key, "api_key"], Auth.api_key())) do
      nil -> {:ok, nil}
      key -> {:ok, key}
    end
  end

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

  defp fetch_model(attrs, auth_mode) do
    case pick(attrs, [:model, "model"], Models.default_model(auth_mode)) do
      nil -> {:ok, nil}
      "" -> {:ok, nil}
      model -> {:ok, model}
    end
  end

  defp fetch_reasoning_effort(attrs, model) do
    default = Models.default_reasoning_effort(model)

    attrs
    |> pick([:reasoning_effort, "reasoning_effort", :reasoning, "reasoning"], default)
    |> Models.normalize_reasoning_effort()
  end

  defp fetch_reasoning_summary(attrs) do
    attrs
    |> pick([
      :model_reasoning_summary,
      "model_reasoning_summary",
      :reasoning_summary,
      "reasoning_summary"
    ])
    |> normalize_reasoning_summary()
  end

  defp fetch_model_verbosity(attrs) do
    attrs
    |> pick([:model_verbosity, "model_verbosity", :verbosity, "verbosity"])
    |> normalize_model_verbosity()
  end

  defp fetch_model_context_window(attrs) do
    case pick(attrs, [
           :model_context_window,
           "model_context_window",
           :context_window,
           "context_window"
         ]) do
      nil -> {:ok, nil}
      value when is_integer(value) and value > 0 -> {:ok, value}
      other -> {:error, {:invalid_model_context_window, other}}
    end
  end

  defp fetch_supports_reasoning_summaries(attrs) do
    case pick(
           attrs,
           [
             :model_supports_reasoning_summaries,
             "model_supports_reasoning_summaries",
             :supports_reasoning_summaries,
             "supports_reasoning_summaries"
           ]
         ) do
      nil -> {:ok, nil}
      value when is_boolean(value) -> {:ok, value}
      other -> {:error, {:invalid_model_supports_reasoning_summaries, other}}
    end
  end

  defp fetch_history_persistence(attrs) do
    history = pick(attrs, [:history, "history"])

    value =
      pick(attrs, [:history_persistence, "history_persistence"]) ||
        if is_map(history) do
          Map.get(history, :persistence, Map.get(history, "persistence"))
        end

    normalize_history_persistence(value)
  end

  defp fetch_history_max_bytes(attrs) do
    history = pick(attrs, [:history, "history"])

    value =
      pick(attrs, [:history_max_bytes, "history_max_bytes"]) ||
        if is_map(history) do
          Map.get(
            history,
            :max_bytes,
            Map.get(history, "max_bytes", Map.get(history, "maxBytes"))
          )
        end

    validate_history_max_bytes(value)
  end

  defp auth_mode_for(api_key) when is_binary(api_key) and api_key != "", do: :api
  defp auth_mode_for(_), do: Auth.infer_auth_mode()

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_string(_), do: nil

  defp normalize_reasoning_summary(nil), do: {:ok, nil}

  defp normalize_reasoning_summary(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_reasoning_summary()
  end

  defp normalize_reasoning_summary(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "" -> {:ok, nil}
      "auto" -> {:ok, "auto"}
      "concise" -> {:ok, "concise"}
      "detailed" -> {:ok, "detailed"}
      "none" -> {:ok, "none"}
      other -> {:error, {:invalid_model_reasoning_summary, other}}
    end
  end

  defp normalize_reasoning_summary(other),
    do: {:error, {:invalid_model_reasoning_summary, other}}

  defp normalize_history_persistence(nil), do: {:ok, nil}

  defp normalize_history_persistence(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_history_persistence()
  end

  defp normalize_history_persistence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, nil}
      trimmed -> {:ok, trimmed}
    end
  end

  defp normalize_history_persistence(other),
    do: {:error, {:invalid_history_persistence, other}}

  defp validate_history_max_bytes(nil), do: {:ok, nil}

  defp validate_history_max_bytes(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp validate_history_max_bytes(other),
    do: {:error, {:invalid_history_max_bytes, other}}

  defp normalize_model_verbosity(nil), do: {:ok, nil}

  defp normalize_model_verbosity(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_model_verbosity()
  end

  defp normalize_model_verbosity(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "" -> {:ok, nil}
      "low" -> {:ok, "low"}
      "medium" -> {:ok, "medium"}
      "high" -> {:ok, "high"}
      other -> {:error, {:invalid_model_verbosity, other}}
    end
  end

  defp normalize_model_verbosity(other), do: {:error, {:invalid_model_verbosity, other}}
end

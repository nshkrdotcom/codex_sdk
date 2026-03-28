defmodule Codex.Options do
  @moduledoc """
  Global configuration for Codex interactions.

  Options are built from caller-supplied values merged with environment defaults.
  """

  require Bitwise
  alias CliSubprocessCore.{CommandSpec, ExecutionSurface, ModelInput, ProviderCLI}
  alias Codex.Auth
  alias Codex.Config.BaseURL
  alias Codex.Config.OptionNormalizers
  alias Codex.Config.Overrides
  alias Codex.Models

  @enforce_keys []
  defstruct api_key: nil,
            base_url: BaseURL.default(),
            codex_path_override: nil,
            execution_surface: %ExecutionSurface{},
            telemetry_prefix: [:codex],
            model_payload: nil,
            model: Models.default_model(),
            reasoning_effort: Models.default_reasoning_effort(),
            model_personality: nil,
            model_reasoning_summary: nil,
            model_verbosity: nil,
            model_context_window: nil,
            model_supports_reasoning_summaries: nil,
            model_auto_compact_token_limit: nil,
            review_model: nil,
            history_persistence: nil,
            history_max_bytes: nil,
            hide_agent_reasoning: false,
            tool_output_token_limit: nil,
            agent_max_threads: nil,
            config_overrides: []

  @typep config_override_value_scalar :: String.t() | boolean() | integer() | float()
  @typep config_override_value ::
           config_override_value_scalar()
           | [config_override_value()]
           | %{optional(String.t() | atom()) => config_override_value()}

  @type t :: %__MODULE__{
          api_key: String.t() | nil,
          base_url: String.t(),
          codex_path_override: String.t() | nil,
          execution_surface: ExecutionSurface.t(),
          telemetry_prefix: [atom()],
          model_payload: CliSubprocessCore.ModelRegistry.selection() | nil,
          model: String.t() | nil,
          reasoning_effort: Models.reasoning_effort() | nil,
          model_personality: Codex.Protocol.ConfigTypes.personality() | nil,
          model_reasoning_summary: String.t() | nil,
          model_verbosity: String.t() | nil,
          model_context_window: pos_integer() | nil,
          model_supports_reasoning_summaries: boolean() | nil,
          model_auto_compact_token_limit: pos_integer() | nil,
          review_model: String.t() | nil,
          history_persistence: String.t() | nil,
          history_max_bytes: non_neg_integer() | nil,
          hide_agent_reasoning: boolean(),
          tool_output_token_limit: pos_integer() | nil,
          agent_max_threads: pos_integer() | nil,
          config_overrides: [
            String.t() | {String.t(), config_override_value()}
          ]
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
         {:ok, execution_surface} <- fetch_execution_surface(attrs),
         {:ok, telemetry_prefix} <- fetch_telemetry_prefix(attrs),
         {:ok, model_input} <- normalize_model_input(attrs),
         model_payload = model_input.selection,
         normalized_attrs = model_input.attrs,
         {:ok, model} <- fetch_model(model_payload),
         {:ok, reasoning_effort} <- fetch_reasoning_effort(model_payload),
         {:ok, model_personality} <- fetch_model_personality(normalized_attrs),
         {:ok, reasoning_summary} <- fetch_reasoning_summary(normalized_attrs),
         {:ok, model_verbosity} <- fetch_model_verbosity(normalized_attrs),
         {:ok, model_context_window} <- fetch_model_context_window(normalized_attrs),
         {:ok, supports_reasoning_summaries} <-
           fetch_supports_reasoning_summaries(normalized_attrs),
         {:ok, model_auto_compact_token_limit} <-
           fetch_model_auto_compact_token_limit(normalized_attrs),
         {:ok, review_model} <- fetch_review_model(normalized_attrs),
         {:ok, history_persistence} <- fetch_history_persistence(normalized_attrs),
         {:ok, history_max_bytes} <- fetch_history_max_bytes(normalized_attrs),
         {:ok, hide_agent_reasoning} <- fetch_hide_agent_reasoning(normalized_attrs),
         {:ok, tool_output_token_limit} <- fetch_tool_output_token_limit(normalized_attrs),
         {:ok, agent_max_threads} <- fetch_agent_max_threads(normalized_attrs),
         {:ok, config_overrides} <- fetch_config_overrides(normalized_attrs) do
      {:ok,
       %__MODULE__{
         api_key: api_key,
         base_url: base_url,
         codex_path_override: override,
         execution_surface: execution_surface,
         telemetry_prefix: telemetry_prefix,
         model_payload: model_payload,
         model: model,
         reasoning_effort: reasoning_effort,
         model_personality: model_personality,
         model_reasoning_summary: reasoning_summary,
         model_verbosity: model_verbosity,
         model_context_window: model_context_window,
         model_supports_reasoning_summaries: supports_reasoning_summaries,
         model_auto_compact_token_limit: model_auto_compact_token_limit,
         review_model: review_model,
         history_persistence: history_persistence,
         history_max_bytes: history_max_bytes,
         hide_agent_reasoning: hide_agent_reasoning,
         tool_output_token_limit: tool_output_token_limit,
         agent_max_threads: agent_max_threads,
         config_overrides: config_overrides
       }}
    end
  end

  @doc """
  Determines a stable command spec for launching `codex`.

  Order of precedence:
  1. Explicit override on the struct.
  2. `CODEX_PATH` environment variable.
  3. `System.find_executable("codex")`.
  """
  @spec codex_command_spec(t()) :: {:ok, CommandSpec.t()} | {:error, term()}
  def codex_command_spec(%__MODULE__{codex_path_override: override}) when is_binary(override) do
    with {:ok, path} <- validate_executable(override) do
      ProviderCLI.resolve(:codex, command: path)
    end
  end

  def codex_command_spec(%__MODULE__{} = _opts) do
    env_path = System.get_env("CODEX_PATH")

    if is_binary(env_path) and env_path != "" do
      with {:ok, path} <- validate_executable(env_path) do
        ProviderCLI.resolve(:codex, command: path)
      end
    else
      case ProviderCLI.resolve(:codex) do
        {:ok, spec} -> {:ok, spec}
        {:error, %ProviderCLI.Error{kind: :cli_not_found}} -> {:error, :codex_binary_not_found}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Determines the stable executable path to `codex`.

  This returns the resolved program from `codex_command_spec/1`. Internal
  launchers should prefer `codex_command_spec/1` so argv prefixes remain
  available when needed.
  """
  @spec codex_path(t()) :: {:ok, String.t()} | {:error, term()}
  def codex_path(%__MODULE__{} = opts) do
    with {:ok, %CommandSpec{program: program}} <- codex_command_spec(opts) do
      {:ok, program}
    end
  end

  @doc false
  @spec normalize_execution_surface(term()) :: {:ok, ExecutionSurface.t()} | {:error, term()}
  def normalize_execution_surface(nil), do: {:ok, %ExecutionSurface{}}

  def normalize_execution_surface(%ExecutionSurface{} = execution_surface),
    do: {:ok, execution_surface}

  def normalize_execution_surface(execution_surface) when is_list(execution_surface) do
    ExecutionSurface.new(execution_surface)
  end

  def normalize_execution_surface(%{} = execution_surface) do
    execution_surface
    |> execution_surface_attrs()
    |> ExecutionSurface.new()
  end

  def normalize_execution_surface(other), do: {:error, {:invalid_execution_surface, other}}

  @doc false
  @spec execution_surface_options(t() | ExecutionSurface.t() | nil) :: keyword()
  def execution_surface_options(%__MODULE__{execution_surface: execution_surface}) do
    execution_surface_options(execution_surface)
  end

  def execution_surface_options(%ExecutionSurface{} = execution_surface) do
    execution_surface
    |> ExecutionSurface.surface_metadata()
    |> Keyword.put(:transport_options, execution_surface.transport_options)
  end

  def execution_surface_options(nil), do: []

  defp fetch_api_key(attrs) do
    case normalize_string(pick(attrs, [:api_key, "api_key"], Auth.api_key())) do
      nil -> {:ok, nil}
      key -> {:ok, key}
    end
  end

  defp fetch_base_url(attrs) do
    case BaseURL.resolve(attrs) do
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

  defp fetch_execution_surface(attrs) do
    attrs
    |> pick([:execution_surface, "execution_surface"])
    |> normalize_execution_surface()
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

  defp normalize_model_input(attrs) do
    attrs
    |> apply_model_env_defaults()
    |> then(&ModelInput.normalize(:codex, &1, []))
  end

  defp apply_model_env_defaults(attrs) when is_map(attrs) do
    if explicit_model_payload?(attrs) do
      attrs
    else
      attrs
      |> put_missing_attr(
        :env_model,
        System.get_env("CODEX_MODEL") ||
          System.get_env("OPENAI_DEFAULT_MODEL") ||
          System.get_env("CODEX_MODEL_DEFAULT")
      )
      |> put_missing_attr(:provider_backend, System.get_env("CODEX_PROVIDER_BACKEND"))
      |> put_missing_attr(:oss_provider, System.get_env("CODEX_OSS_PROVIDER"))
      |> put_missing_attr(:ollama_base_url, System.get_env("CODEX_OLLAMA_BASE_URL"))
    end
  end

  defp explicit_model_payload?(attrs) when is_map(attrs) do
    case Map.get(attrs, :model_payload, Map.get(attrs, "model_payload")) do
      nil -> false
      _payload -> true
    end
  end

  defp execution_surface_attrs(attrs) when is_map(attrs) do
    [
      surface_kind: Map.get(attrs, :surface_kind, Map.get(attrs, "surface_kind")),
      transport_options: Map.get(attrs, :transport_options, Map.get(attrs, "transport_options")),
      target_id: Map.get(attrs, :target_id, Map.get(attrs, "target_id")),
      lease_ref: Map.get(attrs, :lease_ref, Map.get(attrs, "lease_ref")),
      surface_ref: Map.get(attrs, :surface_ref, Map.get(attrs, "surface_ref")),
      boundary_class: Map.get(attrs, :boundary_class, Map.get(attrs, "boundary_class")),
      observability: Map.get(attrs, :observability, Map.get(attrs, "observability", %{}))
    ]
  end

  defp put_missing_attr(attrs, _key, nil), do: attrs
  defp put_missing_attr(attrs, _key, ""), do: attrs

  defp put_missing_attr(attrs, key, value) when is_map(attrs) and is_atom(key) do
    cond do
      Map.has_key?(attrs, key) -> attrs
      Map.has_key?(attrs, Atom.to_string(key)) -> attrs
      true -> Map.put(attrs, key, value)
    end
  end

  defp fetch_model(model_payload) when is_map(model_payload) do
    {:ok, Map.get(model_payload, :resolved_model, Map.get(model_payload, "resolved_model"))}
  end

  defp fetch_reasoning_effort(model_payload) when is_map(model_payload) do
    reasoning =
      Map.get(model_payload, :reasoning, Map.get(model_payload, "reasoning"))

    {:ok, normalize_reasoning_atom(reasoning)}
  end

  defp normalize_reasoning_atom(nil), do: nil
  defp normalize_reasoning_atom(value) when is_atom(value), do: value
  defp normalize_reasoning_atom(value) when is_binary(value), do: String.to_atom(value)

  defp fetch_model_personality(attrs) do
    attrs
    |> pick([:model_personality, "model_personality", :personality, "personality"])
    |> normalize_personality()
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

  defp fetch_model_auto_compact_token_limit(attrs) do
    case pick(attrs, [
           :model_auto_compact_token_limit,
           "model_auto_compact_token_limit",
           :auto_compact_token_limit,
           "auto_compact_token_limit"
         ]) do
      nil -> {:ok, nil}
      value when is_integer(value) and value > 0 -> {:ok, value}
      other -> {:error, {:invalid_model_auto_compact_token_limit, other}}
    end
  end

  defp fetch_review_model(attrs) do
    case pick(attrs, [:review_model, "review_model"]) do
      nil -> {:ok, nil}
      "" -> {:ok, nil}
      value when is_binary(value) -> {:ok, value}
      other -> {:error, {:invalid_review_model, other}}
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

  defp fetch_hide_agent_reasoning(attrs) do
    case pick(attrs, [:hide_agent_reasoning, "hide_agent_reasoning"]) do
      nil -> {:ok, false}
      value when is_boolean(value) -> {:ok, value}
      other -> {:error, {:invalid_hide_agent_reasoning, other}}
    end
  end

  defp fetch_tool_output_token_limit(attrs) do
    case pick(attrs, [
           :tool_output_token_limit,
           "tool_output_token_limit",
           :tool_output_limit,
           "tool_output_limit"
         ]) do
      nil -> {:ok, nil}
      value when is_integer(value) and value > 0 -> {:ok, value}
      other -> {:error, {:invalid_tool_output_token_limit, other}}
    end
  end

  defp fetch_agent_max_threads(attrs) do
    case pick(attrs, [
           :agent_max_threads,
           "agent_max_threads",
           :max_threads,
           "max_threads"
         ]) do
      nil -> {:ok, nil}
      value when is_integer(value) and value > 0 -> {:ok, value}
      other -> {:error, {:invalid_agent_max_threads, other}}
    end
  end

  defp fetch_config_overrides(attrs) do
    attrs
    |> pick([:config_overrides, "config_overrides", :config, "config"], [])
    |> Overrides.normalize_config_overrides()
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_string(_), do: nil

  defp normalize_reasoning_summary(value),
    do: OptionNormalizers.normalize_reasoning_summary(value, :invalid_model_reasoning_summary)

  defp normalize_history_persistence(value),
    do: OptionNormalizers.normalize_history_persistence(value, :invalid_history_persistence)

  defp validate_history_max_bytes(nil), do: {:ok, nil}

  defp validate_history_max_bytes(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp validate_history_max_bytes(other),
    do: {:error, {:invalid_history_max_bytes, other}}

  defp normalize_model_verbosity(value),
    do: OptionNormalizers.normalize_model_verbosity(value, :invalid_model_verbosity)

  defp normalize_personality(nil), do: {:ok, nil}

  defp normalize_personality(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_personality()
  end

  defp normalize_personality(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "" -> {:ok, nil}
      "friendly" -> {:ok, :friendly}
      "pragmatic" -> {:ok, :pragmatic}
      "none" -> {:ok, :none}
      other -> {:error, {:invalid_model_personality, other}}
    end
  end

  defp normalize_personality(other), do: {:error, {:invalid_model_personality, other}}
end

defmodule Codex.Models do
  @moduledoc """
  Known Codex models and their defaults.
  """

  alias Codex.Auth
  alias Codex.Config.BaseURL
  alias Codex.Config.Defaults
  alias Codex.Config.LayerStack

  @type reasoning_effort :: :none | :minimal | :low | :medium | :high | :xhigh

  @type reasoning_effort_preset :: %{
          effort: reasoning_effort(),
          description: String.t()
        }

  @type model_upgrade :: %{
          id: String.t(),
          reasoning_effort_mapping: %{reasoning_effort() => reasoning_effort()} | nil,
          migration_config_key: String.t(),
          model_link: String.t() | nil,
          upgrade_copy: String.t() | nil
        }

  @type model_preset :: %{
          id: String.t(),
          model: String.t(),
          display_name: String.t(),
          description: String.t(),
          default_reasoning_effort: reasoning_effort(),
          supported_reasoning_efforts: [reasoning_effort_preset()],
          is_default: boolean(),
          upgrade: model_upgrade() | nil,
          show_in_picker: boolean(),
          supported_in_api: boolean()
        }

  @type model_visibility :: :list | :hide | :none
  @type shell_tool_type :: :default | :local | :unified_exec | :disabled | :shell_command
  @type apply_patch_tool_type :: :freeform | :function
  @type truncation_policy :: %{mode: :bytes | :tokens, limit: non_neg_integer()}
  @type client_version :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  @type verbosity :: :low | :medium | :high
  @type reasoning_summary_format :: :none | :experimental

  @type model_info :: %{
          slug: String.t(),
          display_name: String.t(),
          description: String.t() | nil,
          default_reasoning_level: reasoning_effort(),
          supported_reasoning_levels: [reasoning_effort_preset()],
          shell_type: shell_tool_type(),
          visibility: model_visibility(),
          minimal_client_version: client_version(),
          supported_in_api: boolean(),
          priority: integer(),
          upgrade: String.t() | nil,
          base_instructions: String.t() | nil,
          supports_reasoning_summaries: boolean(),
          support_verbosity: boolean(),
          default_verbosity: verbosity() | nil,
          apply_patch_tool_type: apply_patch_tool_type() | nil,
          truncation_policy: truncation_policy(),
          supports_parallel_tool_calls: boolean(),
          context_window: non_neg_integer() | nil,
          reasoning_summary_format: reasoning_summary_format(),
          experimental_supported_tools: [String.t()]
        }

  @reasoning_efforts [:none, :minimal, :low, :medium, :high, :xhigh]

  @reasoning_effort_aliases %{
    "none" => :none,
    "extra_high" => :xhigh,
    "extra-high" => :xhigh,
    "minimal" => :minimal,
    "low" => :low,
    "medium" => :medium,
    "high" => :high,
    "xhigh" => :xhigh
  }

  @default_api_model Defaults.default_api_model()
  @default_chatgpt_model Defaults.default_chatgpt_model()
  @remote_models_cache_ttl_seconds Defaults.remote_models_cache_ttl_seconds()

  # -- Shared reasoning-effort preset templates --------------------------------
  # Each list is reused across multiple model presets to avoid duplication.

  @efforts_full [
    %{effort: :low, description: "Fast responses with lighter reasoning"},
    %{effort: :medium, description: "Balances speed and reasoning depth for everyday tasks"},
    %{effort: :high, description: "Greater reasoning depth for complex problems"},
    %{effort: :xhigh, description: "Extra high reasoning depth for complex problems"}
  ]

  @efforts_mini [
    %{effort: :medium, description: "Dynamically adjusts reasoning based on the task"},
    %{effort: :high, description: "Maximizes reasoning depth for complex or ambiguous problems"}
  ]

  @efforts_standard [
    %{effort: :low, description: "Fastest responses with limited reasoning"},
    %{effort: :medium, description: "Dynamically adjusts reasoning based on the task"},
    %{effort: :high, description: "Maximizes reasoning depth for complex or ambiguous problems"}
  ]

  @efforts_frontier [
    %{
      effort: :low,
      description:
        "Balances speed with some reasoning; useful for straightforward queries and short explanations"
    },
    %{
      effort: :medium,
      description:
        "Provides a solid balance of reasoning depth and latency for general-purpose tasks"
    },
    %{effort: :high, description: "Maximizes reasoning depth for complex or ambiguous problems"}
  ]

  @efforts_frontier_xhigh @efforts_frontier ++
                            [
                              %{
                                effort: :xhigh,
                                description: "Extra high reasoning for complex problems"
                              }
                            ]

  @efforts_gpt5 [
                  %{effort: :minimal, description: "Fastest responses with little reasoning"}
                ] ++ @efforts_frontier

  # -- Upgrade target ----------------------------------------------------------

  @gpt_53_codex_upgrade %{
    id: @default_api_model,
    reasoning_effort_mapping: nil,
    migration_config_key: @default_api_model,
    model_link: nil,
    upgrade_copy:
      "Codex is now powered by #{@default_api_model}, our latest frontier agentic coding model. " <>
        "It is smarter and faster than its predecessors and capable of long-running project-scale work."
  }

  # -- Local model presets -----------------------------------------------------
  # Each preset uses `id` as the single source of truth for `model` and
  # `display_name`, with a helper that expands them at compile time.

  @local_presets [
                   %{
                     id: @default_api_model,
                     description: "Latest frontier agentic coding model.",
                     supported_reasoning_efforts: @efforts_full,
                     is_default: true,
                     upgrade: nil,
                     show_in_picker: true,
                     supported_in_api: false,
                     shell_type: :shell_command
                   },
                   %{
                     id: "gpt-5.1-codex-max",
                     description: "Codex-optimized flagship for deep and fast reasoning.",
                     supported_reasoning_efforts: @efforts_full,
                     is_default: false,
                     upgrade: @gpt_53_codex_upgrade,
                     show_in_picker: true,
                     supported_in_api: true,
                     shell_type: :shell_command
                   },
                   %{
                     id: "gpt-5.1-codex-mini",
                     description: "Optimized for codex. Cheaper, faster, but less capable.",
                     supported_reasoning_efforts: @efforts_mini,
                     is_default: false,
                     upgrade: @gpt_53_codex_upgrade,
                     show_in_picker: true,
                     supported_in_api: true,
                     shell_type: :shell_command
                   },
                   %{
                     id: "gpt-5.2",
                     description:
                       "Latest frontier model with improvements across knowledge, reasoning and coding",
                     supported_reasoning_efforts: @efforts_frontier_xhigh,
                     is_default: false,
                     upgrade: @gpt_53_codex_upgrade,
                     show_in_picker: true,
                     supported_in_api: true,
                     shell_type: :shell_command
                   },
                   %{
                     id: "gpt-5-codex",
                     description: "Optimized for codex.",
                     supported_reasoning_efforts: @efforts_standard,
                     is_default: false,
                     upgrade: @gpt_53_codex_upgrade,
                     show_in_picker: false,
                     supported_in_api: true,
                     shell_type: :shell_command
                   },
                   %{
                     id: "gpt-5-codex-mini",
                     description: "Optimized for codex. Cheaper, faster, but less capable.",
                     supported_reasoning_efforts: @efforts_mini,
                     is_default: false,
                     upgrade: @gpt_53_codex_upgrade,
                     show_in_picker: false,
                     supported_in_api: true,
                     shell_type: :shell_command
                   },
                   %{
                     id: "gpt-5.1-codex",
                     description: "Optimized for codex.",
                     supported_reasoning_efforts: @efforts_standard,
                     is_default: false,
                     upgrade: @gpt_53_codex_upgrade,
                     show_in_picker: false,
                     supported_in_api: true,
                     shell_type: :shell_command
                   },
                   %{
                     id: "gpt-5",
                     description: "Broad world knowledge with strong general reasoning.",
                     supported_reasoning_efforts: @efforts_gpt5,
                     is_default: false,
                     upgrade: @gpt_53_codex_upgrade,
                     show_in_picker: false,
                     supported_in_api: true,
                     shell_type: :default
                   },
                   %{
                     id: "gpt-5.1",
                     description: "Broad world knowledge with strong general reasoning.",
                     supported_reasoning_efforts: @efforts_frontier,
                     is_default: false,
                     upgrade: @gpt_53_codex_upgrade,
                     show_in_picker: false,
                     supported_in_api: true,
                     shell_type: :shell_command
                   }
                 ]
                 |> Enum.map(fn preset ->
                   preset
                   |> Map.put_new(:model, preset.id)
                   |> Map.put_new(:display_name, preset.id)
                   |> Map.put_new(:default_reasoning_effort, :medium)
                 end)

  # Shell types are derived from the presets; the only non-preset entry is
  # gpt-5.2-codex which isn't in the preset list but needs a shell type.
  @local_shell_types @local_presets
                     |> Enum.map(fn preset -> {preset.id, preset.shell_type} end)
                     |> Map.new()
                     |> Map.put("gpt-5.2-codex", :shell_command)

  @doc """
  Returns the list of supported models visible for the inferred auth mode.
  """
  @spec list() :: nonempty_list(model_preset())
  def list do
    list_visible(Auth.infer_auth_mode())
  end

  @doc """
  Returns models visible in the model picker.

  If auth_mode is :api, only include supported_in_api models.
  """
  @spec list_visible() :: [model_preset()]
  @spec list_visible(:api | :chatgpt) :: [model_preset()]
  @spec list_visible(:api | :chatgpt, keyword()) :: [model_preset()]
  def list_visible(auth_mode \\ :api, opts \\ []) do
    cwd = config_cwd_from_opts(opts)
    auth_mode = normalize_auth_mode(auth_mode)

    auth_mode
    |> available_presets(cwd)
    |> filter_visible_models(auth_mode)
    |> ensure_default()
  end

  @doc """
  Returns the SDK default model, honoring environment overrides when present.
  """
  @spec default_model() :: String.t()
  @spec default_model(:api | :chatgpt) :: String.t()
  def default_model(auth_mode \\ Auth.infer_auth_mode()) do
    env_override() || default_model_for_auth(normalize_auth_mode(auth_mode))
  end

  @doc """
  Returns the default reasoning effort for the given model (or the default model).
  """
  @spec default_reasoning_effort(String.t() | atom() | nil) :: reasoning_effort() | nil
  def default_reasoning_effort(model \\ default_model()) do
    model
    |> normalize_model()
    |> case do
      nil -> nil
      normalized -> find_model(normalized) |> Map.get(:default_reasoning_effort)
    end
  end

  @doc """
  Parses a reasoning effort value into its canonical atom form.
  """
  @spec normalize_reasoning_effort(String.t() | atom() | nil) ::
          {:ok, reasoning_effort() | nil} | {:error, term()}
  def normalize_reasoning_effort(nil), do: {:ok, nil}

  def normalize_reasoning_effort(value) when is_atom(value) do
    if value in @reasoning_efforts do
      {:ok, value}
    else
      {:error, {:invalid_reasoning_effort, value}}
    end
  end

  def normalize_reasoning_effort(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()

    cond do
      normalized == "" ->
        {:ok, nil}

      Map.has_key?(@reasoning_effort_aliases, normalized) ->
        {:ok, Map.fetch!(@reasoning_effort_aliases, normalized)}

      true ->
        {:error, {:invalid_reasoning_effort, normalized}}
    end
  end

  def normalize_reasoning_effort(value), do: {:error, {:invalid_reasoning_effort, value}}

  @doc """
  Returns `true` when the given model supports tool execution.
  """
  @spec tool_enabled?(String.t() | atom() | nil) :: boolean()
  def tool_enabled?(model) do
    model
    |> normalize_model()
    |> case do
      nil -> false
      normalized -> tool_enabled_for_model(normalized)
    end
  end

  @doc """
  Lists the valid reasoning effort values understood by the SDK.
  """
  @spec reasoning_efforts() :: nonempty_list(reasoning_effort())
  def reasoning_efforts, do: @reasoning_efforts

  @doc """
  Renders a normalized reasoning effort as the CLI-friendly string value.
  """
  @spec reasoning_effort_to_string(reasoning_effort()) :: String.t()
  def reasoning_effort_to_string(effort) when effort in @reasoning_efforts do
    Atom.to_string(effort)
  end

  @doc """
  Returns the upgrade information for a model, if available.
  """
  @spec get_upgrade(String.t()) :: model_upgrade() | nil
  def get_upgrade(model_id) do
    case find_model(model_id) do
      %{upgrade: upgrade} -> upgrade
      _ -> nil
    end
  end

  @doc """
  Returns the supported reasoning efforts for a model.
  """
  @spec supported_reasoning_efforts(String.t()) :: [reasoning_effort_preset()]
  def supported_reasoning_efforts(model_id) do
    case find_model(model_id) do
      %{supported_reasoning_efforts: efforts} -> efforts
      _ -> []
    end
  end

  @doc """
  Coerces a reasoning effort to the nearest supported value for a model.

  Returns the input effort unchanged when the model is unknown or already supports it.
  """
  @spec coerce_reasoning_effort(String.t() | atom() | nil, reasoning_effort() | nil) ::
          reasoning_effort() | nil
  def coerce_reasoning_effort(_model, nil), do: nil
  def coerce_reasoning_effort(nil, effort), do: effort

  def coerce_reasoning_effort(model, effort) do
    model = normalize_model(model)
    supported = supported_reasoning_efforts(model) |> Enum.map(& &1.effort)

    cond do
      supported == [] -> effort
      effort in supported -> effort
      true -> nearest_effort(effort, supported)
    end
  end

  @doc """
  Returns true if a model is supported via API key authentication.
  """
  @spec supported_in_api?(String.t()) :: boolean()
  def supported_in_api?(model_id) do
    case find_model(model_id) do
      %{supported_in_api: supported} -> supported
      _ -> false
    end
  end

  @doc """
  Returns the display name for a model, if known.
  """
  @spec display_name(String.t() | atom()) :: String.t() | nil
  def display_name(model_id) do
    case find_model(model_id) do
      %{display_name: display_name} -> display_name
      _ -> nil
    end
  end

  @doc """
  Returns the description for a model, if known.
  """
  @spec description(String.t() | atom()) :: String.t() | nil
  def description(model_id) do
    case find_model(model_id) do
      %{description: description} -> description
      _ -> nil
    end
  end

  defp env_override do
    System.get_env("CODEX_MODEL") ||
      System.get_env("OPENAI_DEFAULT_MODEL") ||
      System.get_env("CODEX_MODEL_DEFAULT")
  end

  defp default_model_for_auth(:chatgpt), do: @default_chatgpt_model

  defp default_model_for_auth(:api), do: @default_api_model

  defp available_presets(auth_mode, cwd) do
    remote_models =
      auth_mode
      |> remote_models(cwd)
      |> Enum.sort_by(& &1.priority)
      |> Enum.map(&model_info_to_preset/1)

    merge_presets(remote_models, @local_presets)
  end

  defp filter_visible_models(models, auth_mode) do
    Enum.filter(models, fn model ->
      model.show_in_picker && (auth_mode == :chatgpt || model.supported_in_api)
    end)
  end

  defp ensure_default([]), do: []

  defp ensure_default(models) do
    if Enum.any?(models, & &1.is_default) do
      models
    else
      [first | rest] = models
      [%{first | is_default: true} | rest]
    end
  end

  defp merge_presets([], local_presets), do: local_presets

  defp merge_presets(remote_presets, local_presets) do
    remote_slugs =
      remote_presets
      |> Enum.map(& &1.model)
      |> MapSet.new()

    missing_locals =
      local_presets
      |> Enum.reject(&MapSet.member?(remote_slugs, &1.model))
      |> Enum.map(&%{&1 | is_default: false})

    remote_presets ++ missing_locals
  end

  defp find_model(model_id) do
    normalized = normalize_model(model_id)

    all_presets =
      Auth.infer_auth_mode()
      |> available_presets(default_cwd())

    Enum.find(all_presets, fn preset ->
      preset.id == normalized || preset.model == normalized
    end)
  end

  defp normalize_model(nil), do: nil
  defp normalize_model(model) when is_binary(model), do: model
  defp normalize_model(model), do: to_string(model)

  defp tool_enabled_for_model(model_id) do
    auth_mode = Auth.infer_auth_mode()
    shell_type = shell_type_for_model(model_id, auth_mode)

    case shell_type do
      :disabled -> false
      nil -> false
      _ -> true
    end
  end

  defp shell_type_for_model(model_id, auth_mode) do
    remote =
      auth_mode
      |> remote_models(default_cwd())
      |> Enum.find(&(&1.slug == model_id))

    case remote do
      %{shell_type: shell_type} -> shell_type
      _ -> Map.get(@local_shell_types, model_id)
    end
  end

  defp normalize_auth_mode(:api), do: :api
  defp normalize_auth_mode(:chatgpt), do: :chatgpt
  defp normalize_auth_mode("api"), do: :api
  defp normalize_auth_mode("chatgpt"), do: :chatgpt
  defp normalize_auth_mode(_), do: :api

  defp config_cwd_from_opts(opts) when is_list(opts) do
    Keyword.get(opts, :cwd) || Keyword.get(opts, :working_directory) || default_cwd()
  end

  defp config_cwd_from_opts(opts) when is_map(opts) do
    Map.get(opts, :cwd) ||
      Map.get(opts, "cwd") ||
      Map.get(opts, :working_directory) ||
      Map.get(opts, "working_directory") ||
      default_cwd()
  end

  defp config_cwd_from_opts(_), do: default_cwd()

  defp default_cwd do
    case File.cwd() do
      {:ok, cwd} -> cwd
      _ -> nil
    end
  end

  defp remote_models(:api, cwd) do
    if remote_models_enabled?(cwd) do
      load_models_json()
    else
      []
    end
  end

  defp remote_models(:chatgpt, cwd) do
    if remote_models_enabled?(cwd) do
      case load_models_cache() do
        {:ok, models} -> models
        :miss -> fetch_or_load_models()
      end
    else
      []
    end
  end

  defp fetch_or_load_models do
    case Auth.chatgpt_access_token() do
      nil -> load_models_json()
      token -> fetch_models_with_token(token)
    end
  end

  defp fetch_models_with_token(token) do
    case fetch_remote_models(token) do
      {:ok, models, etag} ->
        save_models_cache(models, etag)
        models

      {:error, _reason} ->
        load_models_json()
    end
  end

  defp remote_models_enabled?(cwd) do
    LayerStack.remote_models_enabled?(Auth.codex_home(), cwd)
  end

  defp load_models_json do
    case File.read(bundled_models_path()) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, decoded} -> decoded |> parse_models_response() |> elem(0)
          _ -> []
        end

      _ ->
        []
    end
  end

  defp load_models_cache do
    case File.read(models_cache_path()) do
      {:ok, contents} ->
        with {:ok, decoded} <- Jason.decode(contents),
             fetched_at when is_binary(fetched_at) <- Map.get(decoded, "fetched_at"),
             {:ok, fetched_at, _} <- DateTime.from_iso8601(fetched_at),
             true <- cache_fresh?(fetched_at) do
          {models, _etag} = parse_models_response(decoded)
          {:ok, models}
        else
          _ -> :miss
        end

      _ ->
        :miss
    end
  end

  defp cache_fresh?(fetched_at) do
    if @remote_models_cache_ttl_seconds <= 0 do
      false
    else
      DateTime.diff(DateTime.utc_now(), fetched_at, :second) <= @remote_models_cache_ttl_seconds
    end
  end

  defp save_models_cache(models, etag) do
    cache = %{
      "fetched_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "etag" => etag,
      "models" => models
    }

    path = models_cache_path()

    with {:ok, json} <- Jason.encode(cache) do
      path
      |> Path.dirname()
      |> File.mkdir_p()

      _ = File.write(path, json)
      :ok
    end
  end

  defp models_cache_path do
    Path.join(Auth.codex_home(), "models_cache.json")
  end

  defp bundled_models_path do
    case :code.priv_dir(:codex_sdk) do
      {:error, _} -> Path.join(File.cwd!(), "priv/models.json")
      path -> Path.join(List.to_string(path), "models.json")
    end
  end

  defp fetch_remote_models(token) do
    url = models_url()
    headers = [{~c"authorization", ~c"Bearer " ++ String.to_charlist(token)}]
    http_opts = [timeout: Defaults.remote_models_http_timeout_ms()]
    request_opts = [body_format: :binary]

    :inets.start()
    :ssl.start()

    case :httpc.request(:get, {String.to_charlist(url), headers}, http_opts, request_opts) do
      {:ok, {{_, 200, _}, response_headers, body}} ->
        with {:ok, decoded} <- Jason.decode(body) do
          {models, body_etag} = parse_models_response(decoded)
          etag = header_etag(response_headers) || body_etag
          {:ok, models, etag}
        end

      {:ok, {{_, status, _}, _headers, _body}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp models_url do
    base = BaseURL.resolve()
    base = String.trim_trailing(base, "/")
    client_version = client_version()

    "#{base}/models?client_version=#{client_version}"
  end

  defp header_etag(headers) do
    headers
    |> Enum.find_value(fn {key, value} ->
      if String.downcase(to_string(key)) == "etag" do
        to_string(value)
      end
    end)
  end

  defp client_version do
    version =
      case Application.spec(:codex_sdk, :vsn) do
        nil -> "0.0.0"
        vsn -> to_string(vsn)
      end

    normalized =
      version
      |> String.split("-", parts: 2)
      |> List.first()

    if normalized == "0.0.0", do: "99.99.99", else: normalized
  end

  defp parse_models_response(%{"models" => models} = decoded) when is_list(models) do
    parsed_models =
      models
      |> Enum.map(&parse_model_info/1)
      |> Enum.reject(&is_nil/1)

    {parsed_models, Map.get(decoded, "etag")}
  end

  defp parse_models_response(_), do: {[], nil}

  defp parse_model_info(%{} = data) do
    slug = Map.get(data, "slug")
    display_name = Map.get(data, "display_name")

    if is_binary(slug) and is_binary(display_name) do
      %{
        slug: slug,
        display_name: display_name,
        description: Map.get(data, "description"),
        default_reasoning_level:
          parse_reasoning_effort(Map.get(data, "default_reasoning_level")) || :medium,
        supported_reasoning_levels:
          parse_reasoning_presets(Map.get(data, "supported_reasoning_levels")),
        shell_type: parse_shell_type(Map.get(data, "shell_type")),
        visibility: parse_visibility(Map.get(data, "visibility")),
        minimal_client_version: parse_client_version(Map.get(data, "minimal_client_version")),
        supported_in_api: Map.get(data, "supported_in_api", false),
        priority: Map.get(data, "priority", 0),
        upgrade: Map.get(data, "upgrade"),
        base_instructions: Map.get(data, "base_instructions"),
        supports_reasoning_summaries: Map.get(data, "supports_reasoning_summaries", false),
        support_verbosity: Map.get(data, "support_verbosity", false),
        default_verbosity: parse_verbosity(Map.get(data, "default_verbosity")),
        apply_patch_tool_type:
          parse_apply_patch_tool_type(Map.get(data, "apply_patch_tool_type")),
        truncation_policy: parse_truncation_policy(Map.get(data, "truncation_policy")),
        supports_parallel_tool_calls: Map.get(data, "supports_parallel_tool_calls", false),
        context_window: parse_optional_integer(Map.get(data, "context_window")),
        reasoning_summary_format:
          parse_reasoning_summary_format(Map.get(data, "reasoning_summary_format")),
        experimental_supported_tools:
          parse_string_list(Map.get(data, "experimental_supported_tools"))
      }
    end
  end

  defp parse_model_info(_), do: nil

  defp parse_reasoning_presets(presets) when is_list(presets) do
    presets
    |> Enum.map(fn
      %{"effort" => effort, "description" => description} ->
        case parse_reasoning_effort(effort) do
          nil -> nil
          effort -> %{effort: effort, description: normalize_description(description)}
        end

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_reasoning_presets(_), do: []

  defp parse_reasoning_effort(value) do
    case normalize_reasoning_effort(value) do
      {:ok, effort} -> effort
      _ -> nil
    end
  end

  defp normalize_description(value) when is_binary(value), do: value
  defp normalize_description(_), do: ""

  defp parse_shell_type(value) when is_binary(value) do
    case String.downcase(value) do
      "default" -> :default
      "local" -> :local
      "unified_exec" -> :unified_exec
      "disabled" -> :disabled
      "shell_command" -> :shell_command
      _ -> :default
    end
  end

  defp parse_shell_type(_), do: :default

  defp parse_visibility(value) when is_binary(value) do
    case String.downcase(value) do
      "list" -> :list
      "hide" -> :hide
      "none" -> :none
      _ -> :none
    end
  end

  defp parse_visibility(_), do: :none

  @doc false
  @spec parse_client_version(term()) :: client_version()
  def parse_client_version([major, minor, patch])
      when is_integer(major) and is_integer(minor) and is_integer(patch) do
    {major, minor, patch}
  end

  def parse_client_version(value) when is_binary(value) do
    version =
      value
      |> String.split("-", parts: 2)
      |> List.first()

    case String.split(version, ".", parts: 3) do
      [major, minor, patch] ->
        with {major, ""} <- Integer.parse(major),
             {minor, ""} <- Integer.parse(minor),
             {patch, ""} <- Integer.parse(patch) do
          {major, minor, patch}
        else
          _ -> {0, 0, 0}
        end

      _ ->
        {0, 0, 0}
    end
  end

  def parse_client_version(_), do: {0, 0, 0}

  defp parse_verbosity(value) when is_binary(value) do
    case String.downcase(value) do
      "low" -> :low
      "medium" -> :medium
      "high" -> :high
      _ -> nil
    end
  end

  defp parse_verbosity(_), do: nil

  defp parse_apply_patch_tool_type(value) when is_binary(value) do
    case String.downcase(value) do
      "freeform" -> :freeform
      "function" -> :function
      _ -> nil
    end
  end

  defp parse_apply_patch_tool_type(_), do: nil

  defp parse_truncation_policy(%{"mode" => mode, "limit" => limit}) when is_integer(limit) do
    mode = parse_truncation_mode(mode)

    if mode do
      %{mode: mode, limit: limit}
    else
      %{mode: :bytes, limit: limit}
    end
  end

  defp parse_truncation_policy(_), do: %{mode: :bytes, limit: 0}

  defp parse_truncation_mode(value) when is_binary(value) do
    case String.downcase(value) do
      "bytes" -> :bytes
      "tokens" -> :tokens
      _ -> nil
    end
  end

  defp parse_truncation_mode(_), do: nil

  defp parse_optional_integer(value) when is_integer(value) and value >= 0, do: value
  defp parse_optional_integer(_), do: nil

  defp parse_reasoning_summary_format(value) when is_binary(value) do
    case String.downcase(value) do
      "experimental" -> :experimental
      "none" -> :none
      _ -> :none
    end
  end

  defp parse_reasoning_summary_format(_), do: :none

  defp parse_string_list(list) when is_list(list) do
    Enum.map(list, &to_string/1)
  end

  defp parse_string_list(_), do: []

  defp model_info_to_preset(%{
         slug: slug,
         display_name: display_name,
         description: description,
         default_reasoning_level: default_reasoning_level,
         supported_reasoning_levels: supported_reasoning_levels,
         visibility: visibility,
         supported_in_api: supported_in_api,
         upgrade: upgrade
       }) do
    %{
      id: slug,
      model: slug,
      display_name: display_name,
      description: description || "",
      default_reasoning_effort: default_reasoning_level,
      supported_reasoning_efforts: supported_reasoning_levels,
      is_default: false,
      upgrade: upgrade_from_info(slug, upgrade, supported_reasoning_levels),
      show_in_picker: visibility == :list,
      supported_in_api: supported_in_api
    }
  end

  defp upgrade_from_info(_slug, nil, _presets), do: nil

  defp upgrade_from_info(slug, upgrade_slug, presets) do
    %{
      id: upgrade_slug,
      reasoning_effort_mapping: reasoning_effort_mapping_from_presets(presets),
      migration_config_key: slug,
      model_link: nil,
      upgrade_copy: nil
    }
  end

  defp reasoning_effort_mapping_from_presets([]), do: nil

  defp reasoning_effort_mapping_from_presets(presets) do
    supported = Enum.map(presets, & &1.effort)

    @reasoning_efforts
    |> Enum.reduce(%{}, fn effort, acc ->
      Map.put(acc, effort, nearest_effort(effort, supported))
    end)
  end

  defp nearest_effort(target, supported) do
    target_rank = effort_rank(target)

    supported
    |> Enum.min_by(fn candidate -> abs(effort_rank(candidate) - target_rank) end, fn -> target end)
  end

  defp effort_rank(:none), do: 0
  defp effort_rank(:minimal), do: 1
  defp effort_rank(:low), do: 2
  defp effort_rank(:medium), do: 3
  defp effort_rank(:high), do: 4
  defp effort_rank(:xhigh), do: 5
end

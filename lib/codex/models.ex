defmodule Codex.Models do
  @moduledoc """
  Codex model metadata projected from `cli_subprocess_core`.
  """

  alias CliSubprocessCore.ModelRegistry
  alias CliSubprocessCore.ModelRegistry.Model, as: RegistryModel
  alias Codex.Auth
  alias Codex.Config.BaseURL
  alias Codex.Config.Defaults
  alias Codex.Config.LayerStack
  alias Codex.Net.CA

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
          supported_in_api: boolean(),
          family: String.t() | nil
        }

  @type client_version :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}

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

  @doc """
  Returns the list of supported models visible for the inferred auth mode.
  """
  @spec list() :: [model_preset()]
  def list, do: list_visible(Auth.infer_auth_mode())

  @doc """
  Returns models visible in the model picker.
  """
  @spec list_visible() :: [model_preset()]
  @spec list_visible(:api | :chatgpt) :: [model_preset()]
  @spec list_visible(:api | :chatgpt, keyword()) :: [model_preset()]
  def list_visible(_auth_mode \\ :api, opts \\ []) do
    family = Keyword.get(opts, :model_family) |> normalize_optional_binary()
    default_id = core_default_model!()

    :codex
    |> ModelRegistry.list_visible(visibility: :public)
    |> unwrap_registry!(:list_visible)
    |> Enum.map(&fetch_model!/1)
    |> Enum.map(&registry_model_to_preset(&1, default_id))
    |> Enum.filter(fn preset -> is_nil(family) or preset.family == family end)
  end

  @doc """
  Returns the SDK default model from the shared core registry.
  """
  @spec default_model() :: String.t()
  @spec default_model(:api | :chatgpt) :: String.t()
  def default_model(_auth_mode \\ Auth.infer_auth_mode()), do: core_default_model!()

  @doc """
  Returns the default reasoning effort for the given model (or the default model).
  """
  @spec default_reasoning_effort(String.t() | atom() | nil) :: reasoning_effort() | nil
  def default_reasoning_effort(model \\ default_model()) do
    case find_model(model) do
      %{default_reasoning_effort: effort} when is_atom(effort) -> effort
      _ -> :medium
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
    normalized = value |> String.trim() |> String.downcase()

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
  def tool_enabled?(model), do: not is_nil(find_model(model))

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
    supported = supported_reasoning_efforts(to_string(model)) |> Enum.map(& &1.effort)

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

  @doc false
  @spec remote_models_http_options() :: keyword()
  def remote_models_http_options do
    [timeout: Defaults.remote_models_http_timeout_ms()]
    |> CA.merge_httpc_options()
  end

  @doc false
  @spec remote_models_url(String.t() | nil) :: String.t()
  def remote_models_url(cwd \\ default_cwd()) do
    models_url(cwd)
  end

  @doc false
  @spec parse_client_version(term()) :: client_version()
  def parse_client_version([major, minor, patch])
      when is_integer(major) and is_integer(minor) and is_integer(patch) and
             major >= 0 and minor >= 0 and patch >= 0 do
    {major, minor, patch}
  end

  def parse_client_version(value) when is_binary(value) do
    value
    |> String.split("-", parts: 2)
    |> List.first()
    |> String.split(".")
    |> Enum.take(3)
    |> Enum.map(&Integer.parse/1)
    |> case do
      [{major, ""}, {minor, ""}, {patch, ""}] when major >= 0 and minor >= 0 and patch >= 0 ->
        {major, minor, patch}

      _ ->
        {0, 0, 0}
    end
  end

  def parse_client_version(_), do: {0, 0, 0}

  defp find_model(model_id) do
    case normalize_model(model_id) do
      nil -> nil
      normalized -> ModelRegistry.validate(:codex, normalized) |> normalize_model_result()
    end
  end

  defp normalize_model_result({:ok, %RegistryModel{} = model}) do
    registry_model_to_preset(model, core_default_model!())
  end

  defp normalize_model_result({:error, _reason}), do: nil

  defp fetch_model!(model_id) do
    model_id
    |> ModelRegistry.validate(:codex)
    |> unwrap_registry!(:validate)
  end

  defp registry_model_to_preset(%RegistryModel{} = model, default_id) do
    default_reasoning_effort =
      model.default_reasoning_effort
      |> normalize_reasoning_atom()
      |> Kernel.||(:medium)

    %{
      id: model.id,
      model: model.id,
      display_name: Map.get(model.metadata, "display_name", model.id),
      description: Map.get(model.metadata, "description", ""),
      default_reasoning_effort: default_reasoning_effort,
      supported_reasoning_efforts: reasoning_presets_from_model(model),
      is_default: model.id == default_id,
      upgrade: normalize_upgrade(model),
      show_in_picker: model.visibility == :public,
      supported_in_api: model.visibility == :public,
      family: model.family
    }
  end

  defp reasoning_presets_from_model(%RegistryModel{} = model) do
    @reasoning_efforts
    |> Enum.filter(&Map.has_key?(model.reasoning_efforts, Atom.to_string(&1)))
    |> Enum.map(fn effort ->
      %{effort: effort, description: reasoning_effort_description(effort)}
    end)
  end

  defp normalize_upgrade(%RegistryModel{metadata: %{"upgrade" => upgrade}})
       when is_map(upgrade) do
    id = Map.get(upgrade, "id") || Map.get(upgrade, :id)

    if is_binary(id) and String.trim(id) != "" do
      %{
        id: String.trim(id),
        reasoning_effort_mapping:
          Map.get(upgrade, "reasoning_effort_mapping") ||
            Map.get(upgrade, :reasoning_effort_mapping),
        migration_config_key:
          Map.get(upgrade, "migration_config_key") || Map.get(upgrade, :migration_config_key) ||
            String.trim(id),
        model_link: Map.get(upgrade, "model_link") || Map.get(upgrade, :model_link),
        upgrade_copy: Map.get(upgrade, "upgrade_copy") || Map.get(upgrade, :upgrade_copy)
      }
    end
  end

  defp normalize_upgrade(_model), do: nil

  defp normalize_reasoning_atom(nil), do: nil

  defp normalize_reasoning_atom(value) do
    case normalize_reasoning_effort(value) do
      {:ok, effort} -> effort
      {:error, _reason} -> nil
    end
  end

  defp reasoning_effort_description(effort) when effort in @reasoning_efforts do
    effort
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp core_default_model! do
    :codex
    |> ModelRegistry.default_model()
    |> unwrap_registry!(:default_model)
  end

  defp unwrap_registry!({:ok, value}, _operation), do: value

  defp unwrap_registry!({:error, reason}, operation) do
    raise ArgumentError, "codex model registry #{operation} failed: #{inspect(reason)}"
  end

  defp normalize_model(nil), do: nil
  defp normalize_model(model) when is_binary(model), do: String.trim(model)
  defp normalize_model(model), do: model |> to_string() |> String.trim()

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

  defp models_url(cwd) do
    base = resolve_models_base_url(cwd) |> String.trim_trailing("/")
    client_version = client_version()
    "#{base}/models?client_version=#{client_version}"
  end

  defp resolve_models_base_url(cwd) do
    case LayerStack.load(Auth.codex_home(), cwd) do
      {:ok, layers} ->
        layers
        |> LayerStack.effective_config()
        |> BaseURL.resolve()

      {:error, _reason} ->
        BaseURL.resolve()
    end
  end

  defp client_version do
    case Application.spec(:codex_sdk, :vsn) do
      nil -> "99.99.99"
      vsn -> vsn |> to_string() |> parse_client_version() |> format_client_version()
    end
  end

  defp format_client_version({major, minor, patch}), do: "#{major}.#{minor}.#{patch}"

  defp default_cwd do
    case File.cwd() do
      {:ok, cwd} -> cwd
      _ -> nil
    end
  end

  defp normalize_optional_binary(nil), do: nil

  defp normalize_optional_binary(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_binary(_other), do: nil
end

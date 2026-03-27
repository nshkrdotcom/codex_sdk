defmodule Codex.Protocol.Plugin.ListResponse do
  @moduledoc """
  Typed response for `plugin/list`.
  """

  use TypedStruct

  alias Codex.Protocol.Plugin.{Helpers, Marketplace, MarketplaceLoadError}

  @key_mapping %{
    "marketplace_load_errors" => "marketplaceLoadErrors",
    "remote_sync_error" => "remoteSyncError",
    "featured_plugin_ids" => "featuredPluginIds"
  }
  @known_fields ["marketplaces", "marketplaceLoadErrors", "remoteSyncError", "featuredPluginIds"]
  @schema Zoi.map(
            %{
              "marketplaces" => Helpers.default_array(Helpers.any_map()),
              "marketplaceLoadErrors" => Helpers.default_array(Helpers.any_map()),
              "remoteSyncError" => Helpers.optional_string(),
              "featuredPluginIds" => Helpers.default_string_list()
            },
            unrecognized_keys: :preserve
          )

  typedstruct do
    field(:marketplaces, [Marketplace.t()], default: [])
    field(:marketplace_load_errors, [MarketplaceLoadError.t()], default: [])
    field(:remote_sync_error, String.t() | nil)
    field(:featured_plugin_ids, [String.t()], default: [])
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error, {:invalid_plugin_list_response, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = value), do: {:ok, value}

  def parse(data),
    do: Helpers.parse(@schema, data, :invalid_plugin_list_response, @key_mapping, &build/1)

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = value), do: value

  def parse!(data),
    do: Helpers.parse!(@schema, data, :invalid_plugin_list_response, @key_mapping, &build/1)

  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{
      "marketplaces" => Helpers.encode_list(value.marketplaces, Marketplace),
      "marketplaceLoadErrors" =>
        Helpers.encode_list(value.marketplace_load_errors, MarketplaceLoadError),
      "featuredPluginIds" => value.featured_plugin_ids
    }
    |> Helpers.maybe_put("remoteSyncError", value.remote_sync_error)
    |> Map.merge(value.extra)
  end

  defp build(parsed) do
    {known, extra} = Helpers.split_extra(parsed, @known_fields)

    %__MODULE__{
      marketplaces: Helpers.parse_list(Map.get(known, "marketplaces"), Marketplace),
      marketplace_load_errors:
        Helpers.parse_list(Map.get(known, "marketplaceLoadErrors"), MarketplaceLoadError),
      remote_sync_error: Map.get(known, "remoteSyncError"),
      featured_plugin_ids: Map.get(known, "featuredPluginIds", []),
      extra: extra
    }
  end
end

defmodule Codex.Protocol.Plugin.ReadResponse do
  @moduledoc """
  Typed response for `plugin/read`.
  """

  use TypedStruct

  alias Codex.Protocol.Plugin.{Detail, Helpers}

  @known_fields ["plugin"]
  @schema Zoi.map(
            %{"plugin" => Helpers.any_map()},
            unrecognized_keys: :preserve
          )

  typedstruct do
    field(:plugin, Detail.t(), enforce: true)
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error, {:invalid_plugin_read_response, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = value), do: {:ok, value}
  def parse(data), do: Helpers.parse(@schema, data, :invalid_plugin_read_response, %{}, &build/1)

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = value), do: value

  def parse!(data),
    do: Helpers.parse!(@schema, data, :invalid_plugin_read_response, %{}, &build/1)

  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{"plugin" => Detail.to_map(value.plugin)}
    |> Map.merge(value.extra)
  end

  defp build(parsed) do
    {known, extra} = Helpers.split_extra(parsed, @known_fields)
    %__MODULE__{plugin: Helpers.parse_nested(Map.fetch!(known, "plugin"), Detail), extra: extra}
  end
end

defmodule Codex.Protocol.Plugin.InstallResponse do
  @moduledoc """
  Typed response for `plugin/install`.
  """

  use TypedStruct

  alias Codex.Protocol.Plugin.{AppSummary, AuthPolicy, Helpers}

  @key_mapping %{"auth_policy" => "authPolicy", "apps_needing_auth" => "appsNeedingAuth"}
  @known_fields ["authPolicy", "appsNeedingAuth"]
  @schema Zoi.map(
            %{
              "authPolicy" => AuthPolicy.schema(),
              "appsNeedingAuth" => Helpers.default_array(Helpers.any_map())
            },
            unrecognized_keys: :preserve
          )

  typedstruct do
    field(:auth_policy, AuthPolicy.t(), enforce: true)
    field(:apps_needing_auth, [AppSummary.t()], default: [])
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error, {:invalid_plugin_install_response, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = value), do: {:ok, value}

  def parse(data) do
    Helpers.parse(@schema, data, :invalid_plugin_install_response, @key_mapping, &build/1)
  end

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = value), do: value

  def parse!(data) do
    Helpers.parse!(@schema, data, :invalid_plugin_install_response, @key_mapping, &build/1)
  end

  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{
      "authPolicy" => AuthPolicy.to_wire(value.auth_policy),
      "appsNeedingAuth" => Helpers.encode_list(value.apps_needing_auth, AppSummary)
    }
    |> Map.merge(value.extra)
  end

  defp build(parsed) do
    {known, extra} = Helpers.split_extra(parsed, @known_fields)

    %__MODULE__{
      auth_policy: Map.fetch!(known, "authPolicy"),
      apps_needing_auth: Helpers.parse_list(Map.get(known, "appsNeedingAuth"), AppSummary),
      extra: extra
    }
  end
end

defmodule Codex.Protocol.Plugin.UninstallResponse do
  @moduledoc """
  Typed response for `plugin/uninstall`.
  """

  use TypedStruct

  alias Codex.Protocol.Plugin.Helpers

  @schema Zoi.map(%{}, unrecognized_keys: :preserve)

  typedstruct do
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error,
             {:invalid_plugin_uninstall_response, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = value), do: {:ok, value}

  def parse(data) do
    Helpers.parse(@schema, data, :invalid_plugin_uninstall_response, %{}, &build/1)
  end

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = value), do: value

  def parse!(data) do
    Helpers.parse!(@schema, data, :invalid_plugin_uninstall_response, %{}, &build/1)
  end

  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value), do: value.extra

  defp build(parsed), do: %__MODULE__{extra: parsed}
end

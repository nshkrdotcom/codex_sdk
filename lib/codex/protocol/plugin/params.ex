defmodule Codex.Protocol.Plugin.ListParams do
  @moduledoc """
  Typed params for `plugin/list`.
  """

  use TypedStruct

  alias Codex.Protocol.Plugin.Helpers

  @key_mapping %{
    "force_remote_sync" => "forceRemoteSync",
    "marketplace_kinds" => "marketplaceKinds"
  }
  @known_fields ["cwds", "forceRemoteSync", "marketplaceKinds"]
  @schema Zoi.map(
            %{
              "cwds" => Zoi.optional(Zoi.nullish(Zoi.array(Helpers.required_string()))),
              "forceRemoteSync" => Helpers.boolean_flag(),
              "marketplaceKinds" => Zoi.optional(Zoi.nullish(Zoi.array(Zoi.any())))
            },
            unrecognized_keys: :preserve
          )

  typedstruct do
    field(:cwds, [String.t()] | nil)
    field(:force_remote_sync, boolean(), default: false)
    field(:marketplace_kinds, [String.t()] | nil)
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t() | nil) ::
          {:ok, t()}
          | {:error, {:invalid_plugin_list_params, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = params), do: {:ok, params}
  def parse(nil), do: parse(%{})

  def parse(data),
    do: Helpers.parse(@schema, data, :invalid_plugin_list_params, @key_mapping, &build/1)

  @spec parse!(map() | keyword() | t() | nil) :: t()
  def parse!(%__MODULE__{} = params), do: params
  def parse!(nil), do: parse!(%{})

  def parse!(data),
    do: Helpers.parse!(@schema, data, :invalid_plugin_list_params, @key_mapping, &build/1)

  @spec from_map(map() | keyword() | t() | nil) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = params) do
    %{}
    |> Helpers.maybe_put("cwds", params.cwds)
    |> Helpers.maybe_put("marketplaceKinds", params.marketplace_kinds)
    |> Map.merge(params.extra)
  end

  defp build(parsed) do
    {known, extra} = Helpers.split_extra(parsed, @known_fields)

    %__MODULE__{
      cwds: Map.get(known, "cwds"),
      force_remote_sync: Map.get(known, "forceRemoteSync", false),
      marketplace_kinds:
        known
        |> Map.get("marketplaceKinds")
        |> normalize_marketplace_kinds(),
      extra: extra
    }
  end

  defp normalize_marketplace_kinds(nil), do: nil

  defp normalize_marketplace_kinds(kinds) when is_list(kinds) do
    Enum.map(kinds, &normalize_marketplace_kind/1)
  end

  defp normalize_marketplace_kind(:local), do: "local"
  defp normalize_marketplace_kind(:vertical), do: "vertical"
  defp normalize_marketplace_kind(:workspace_directory), do: "workspace-directory"
  defp normalize_marketplace_kind(:shared_with_me), do: "shared-with-me"
  defp normalize_marketplace_kind(:created_by_me_remote), do: "created-by-me-remote"
  defp normalize_marketplace_kind(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_marketplace_kind(value) when is_binary(value), do: value
  defp normalize_marketplace_kind(value), do: value
end

defmodule Codex.Protocol.Plugin.ReadParams do
  @moduledoc """
  Typed params for `plugin/read`.
  """

  use TypedStruct

  alias Codex.Protocol.Plugin.Helpers

  @key_mapping %{"marketplace_path" => "marketplacePath", "plugin_name" => "pluginName"}
  @known_fields ["marketplacePath", "pluginName"]
  @schema Zoi.map(
            %{
              "marketplacePath" => Helpers.required_string(),
              "pluginName" => Helpers.required_string()
            },
            unrecognized_keys: :preserve
          )

  typedstruct do
    field(:marketplace_path, String.t(), enforce: true)
    field(:plugin_name, String.t(), enforce: true)
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error, {:invalid_plugin_read_params, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = params), do: {:ok, params}

  def parse(data),
    do: Helpers.parse(@schema, data, :invalid_plugin_read_params, @key_mapping, &build/1)

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = params), do: params

  def parse!(data),
    do: Helpers.parse!(@schema, data, :invalid_plugin_read_params, @key_mapping, &build/1)

  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = params) do
    %{
      "marketplacePath" => params.marketplace_path,
      "pluginName" => params.plugin_name
    }
    |> Map.merge(params.extra)
  end

  defp build(parsed) do
    {known, extra} = Helpers.split_extra(parsed, @known_fields)

    %__MODULE__{
      marketplace_path: Map.fetch!(known, "marketplacePath"),
      plugin_name: Map.fetch!(known, "pluginName"),
      extra: extra
    }
  end
end

defmodule Codex.Protocol.Plugin.InstallParams do
  @moduledoc """
  Typed params for `plugin/install`.
  """

  use TypedStruct

  alias Codex.Protocol.Plugin.Helpers

  @key_mapping %{
    "marketplace_path" => "marketplacePath",
    "plugin_name" => "pluginName",
    "force_remote_sync" => "forceRemoteSync"
  }
  @known_fields ["marketplacePath", "pluginName", "forceRemoteSync"]
  @schema Zoi.map(
            %{
              "marketplacePath" => Helpers.required_string(),
              "pluginName" => Helpers.required_string(),
              "forceRemoteSync" => Helpers.boolean_flag()
            },
            unrecognized_keys: :preserve
          )

  typedstruct do
    field(:marketplace_path, String.t(), enforce: true)
    field(:plugin_name, String.t(), enforce: true)
    field(:force_remote_sync, boolean(), default: false)
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error, {:invalid_plugin_install_params, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = params), do: {:ok, params}

  def parse(data),
    do: Helpers.parse(@schema, data, :invalid_plugin_install_params, @key_mapping, &build/1)

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = params), do: params

  def parse!(data),
    do: Helpers.parse!(@schema, data, :invalid_plugin_install_params, @key_mapping, &build/1)

  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = params) do
    %{
      "marketplacePath" => params.marketplace_path,
      "pluginName" => params.plugin_name
    }
    |> maybe_put_force_remote_sync(params.force_remote_sync)
    |> Map.merge(params.extra)
  end

  defp build(parsed) do
    {known, extra} = Helpers.split_extra(parsed, @known_fields)

    %__MODULE__{
      marketplace_path: Map.fetch!(known, "marketplacePath"),
      plugin_name: Map.fetch!(known, "pluginName"),
      force_remote_sync: Map.get(known, "forceRemoteSync", false),
      extra: extra
    }
  end

  defp maybe_put_force_remote_sync(map, true), do: Map.put(map, "forceRemoteSync", true)
  defp maybe_put_force_remote_sync(map, _value), do: map
end

defmodule Codex.Protocol.Plugin.UninstallParams do
  @moduledoc """
  Typed params for `plugin/uninstall`.
  """

  use TypedStruct

  alias Codex.Protocol.Plugin.Helpers

  @key_mapping %{"plugin_id" => "pluginId", "force_remote_sync" => "forceRemoteSync"}
  @known_fields ["pluginId", "forceRemoteSync"]
  @schema Zoi.map(
            %{
              "pluginId" => Helpers.required_string(),
              "forceRemoteSync" => Helpers.boolean_flag()
            },
            unrecognized_keys: :preserve
          )

  typedstruct do
    field(:plugin_id, String.t(), enforce: true)
    field(:force_remote_sync, boolean(), default: false)
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error, {:invalid_plugin_uninstall_params, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = params), do: {:ok, params}

  def parse(data),
    do: Helpers.parse(@schema, data, :invalid_plugin_uninstall_params, @key_mapping, &build/1)

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = params), do: params

  def parse!(data),
    do: Helpers.parse!(@schema, data, :invalid_plugin_uninstall_params, @key_mapping, &build/1)

  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = params) do
    %{"pluginId" => params.plugin_id}
    |> maybe_put_force_remote_sync(params.force_remote_sync)
    |> Map.merge(params.extra)
  end

  defp build(parsed) do
    {known, extra} = Helpers.split_extra(parsed, @known_fields)

    %__MODULE__{
      plugin_id: Map.fetch!(known, "pluginId"),
      force_remote_sync: Map.get(known, "forceRemoteSync", false),
      extra: extra
    }
  end

  defp maybe_put_force_remote_sync(map, true), do: Map.put(map, "forceRemoteSync", true)
  defp maybe_put_force_remote_sync(map, _value), do: map
end

defmodule Codex.Protocol.Plugin.MarketplaceInterface do
  @moduledoc """
  Marketplace interface metadata surfaced by `plugin/list`.
  """

  use TypedStruct

  alias Codex.Protocol.Plugin.Helpers

  @key_mapping %{"display_name" => "displayName"}
  @known_fields ["displayName"]
  @schema Zoi.map(
            %{"displayName" => Helpers.optional_string()},
            unrecognized_keys: :preserve
          )

  typedstruct do
    field(:display_name, String.t() | nil)
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error,
             {:invalid_plugin_marketplace_interface, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = value), do: {:ok, value}

  def parse(data) do
    Helpers.parse(
      @schema,
      data,
      :invalid_plugin_marketplace_interface,
      @key_mapping,
      &build/1
    )
  end

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = value), do: value

  def parse!(data) do
    Helpers.parse!(
      @schema,
      data,
      :invalid_plugin_marketplace_interface,
      @key_mapping,
      &build/1
    )
  end

  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{}
    |> Helpers.maybe_put("displayName", value.display_name)
    |> Map.merge(value.extra)
  end

  defp build(parsed) do
    {known, extra} = Helpers.split_extra(parsed, @known_fields)
    %__MODULE__{display_name: Map.get(known, "displayName"), extra: extra}
  end
end

defmodule Codex.Protocol.Plugin.MarketplaceLoadError do
  @moduledoc """
  Marketplace load failure details returned by `plugin/list`.
  """

  use TypedStruct

  alias Codex.Protocol.Plugin.Helpers

  @key_mapping %{"marketplace_path" => "marketplacePath"}
  @known_fields ["marketplacePath", "message"]
  @schema Zoi.map(
            %{
              "marketplacePath" => Helpers.required_string(),
              "message" => Helpers.required_string()
            },
            unrecognized_keys: :preserve
          )

  typedstruct do
    field(:marketplace_path, String.t(), enforce: true)
    field(:message, String.t(), enforce: true)
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error,
             {:invalid_plugin_marketplace_load_error, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = value), do: {:ok, value}

  def parse(data) do
    Helpers.parse(
      @schema,
      data,
      :invalid_plugin_marketplace_load_error,
      @key_mapping,
      &build/1
    )
  end

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = value), do: value

  def parse!(data) do
    Helpers.parse!(
      @schema,
      data,
      :invalid_plugin_marketplace_load_error,
      @key_mapping,
      &build/1
    )
  end

  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{
      "marketplacePath" => value.marketplace_path,
      "message" => value.message
    }
    |> Map.merge(value.extra)
  end

  defp build(parsed) do
    {known, extra} = Helpers.split_extra(parsed, @known_fields)

    %__MODULE__{
      marketplace_path: Map.fetch!(known, "marketplacePath"),
      message: Map.fetch!(known, "message"),
      extra: extra
    }
  end
end

defmodule Codex.Protocol.Plugin.Source do
  @moduledoc """
  Plugin source metadata returned by the app-server plugin APIs.
  """

  use TypedStruct

  alias Codex.Protocol.Plugin.Helpers

  @known_fields ["type", "path"]
  @schema Zoi.map(
            %{
              "type" => Helpers.required_string(),
              "path" => Helpers.optional_string()
            },
            unrecognized_keys: :preserve
          )

  @type source_type :: :local | String.t()

  typedstruct do
    field(:type, source_type(), enforce: true)
    field(:path, String.t() | nil)
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()} | {:error, {:invalid_plugin_source, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = value), do: {:ok, value}

  def parse(data) do
    Helpers.parse(@schema, data, :invalid_plugin_source, %{}, &build/1)
  end

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = value), do: value
  def parse!(data), do: Helpers.parse!(@schema, data, :invalid_plugin_source, %{}, &build/1)

  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{"type" => encode_type(value.type)}
    |> Helpers.maybe_put("path", value.path)
    |> Map.merge(value.extra)
  end

  defp build(parsed) do
    {known, extra} = Helpers.split_extra(parsed, @known_fields)

    %__MODULE__{
      type: decode_type(Map.fetch!(known, "type")),
      path: Map.get(known, "path"),
      extra: extra
    }
  end

  defp decode_type("local"), do: :local
  defp decode_type(:local), do: :local
  defp decode_type(value), do: value

  defp encode_type(:local), do: "local"
  defp encode_type(value) when is_binary(value), do: value
  defp encode_type(value) when is_atom(value), do: Atom.to_string(value)
end

defmodule Codex.Protocol.Plugin.Interface do
  @moduledoc """
  Plugin presentation metadata returned on plugin summary/detail responses.
  """

  use TypedStruct

  alias Codex.Protocol.Plugin.Helpers

  @key_mapping %{
    "display_name" => "displayName",
    "short_description" => "shortDescription",
    "long_description" => "longDescription",
    "developer_name" => "developerName",
    "website_url" => "websiteUrl",
    "privacy_policy_url" => "privacyPolicyUrl",
    "terms_of_service_url" => "termsOfServiceUrl",
    "default_prompt" => "defaultPrompt",
    "brand_color" => "brandColor",
    "composer_icon" => "composerIcon"
  }
  @known_fields [
    "displayName",
    "shortDescription",
    "longDescription",
    "developerName",
    "category",
    "capabilities",
    "websiteUrl",
    "privacyPolicyUrl",
    "termsOfServiceUrl",
    "defaultPrompt",
    "brandColor",
    "composerIcon",
    "logo",
    "screenshots"
  ]
  @schema Zoi.map(
            %{
              "displayName" => Helpers.optional_string(),
              "shortDescription" => Helpers.optional_string(),
              "longDescription" => Helpers.optional_string(),
              "developerName" => Helpers.optional_string(),
              "category" => Helpers.optional_string(),
              "capabilities" => Helpers.default_string_list(),
              "websiteUrl" => Helpers.optional_string(),
              "privacyPolicyUrl" => Helpers.optional_string(),
              "termsOfServiceUrl" => Helpers.optional_string(),
              "defaultPrompt" => Zoi.optional(Zoi.nullish(Zoi.array(Helpers.required_string()))),
              "brandColor" => Helpers.optional_string(),
              "composerIcon" => Helpers.optional_string(),
              "logo" => Helpers.optional_string(),
              "screenshots" => Helpers.default_string_list()
            },
            unrecognized_keys: :preserve
          )

  typedstruct do
    field(:display_name, String.t() | nil)
    field(:short_description, String.t() | nil)
    field(:long_description, String.t() | nil)
    field(:developer_name, String.t() | nil)
    field(:category, String.t() | nil)
    field(:capabilities, [String.t()], default: [])
    field(:website_url, String.t() | nil)
    field(:privacy_policy_url, String.t() | nil)
    field(:terms_of_service_url, String.t() | nil)
    field(:default_prompt, [String.t()] | nil)
    field(:brand_color, String.t() | nil)
    field(:composer_icon, String.t() | nil)
    field(:logo, String.t() | nil)
    field(:screenshots, [String.t()], default: [])
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error, {:invalid_plugin_interface, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = value), do: {:ok, value}

  def parse(data) do
    Helpers.parse(@schema, data, :invalid_plugin_interface, @key_mapping, &build/1)
  end

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = value), do: value

  def parse!(data) do
    Helpers.parse!(@schema, data, :invalid_plugin_interface, @key_mapping, &build/1)
  end

  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{}
    |> Helpers.maybe_put("displayName", value.display_name)
    |> Helpers.maybe_put("shortDescription", value.short_description)
    |> Helpers.maybe_put("longDescription", value.long_description)
    |> Helpers.maybe_put("developerName", value.developer_name)
    |> Helpers.maybe_put("category", value.category)
    |> Map.put("capabilities", value.capabilities)
    |> Helpers.maybe_put("websiteUrl", value.website_url)
    |> Helpers.maybe_put("privacyPolicyUrl", value.privacy_policy_url)
    |> Helpers.maybe_put("termsOfServiceUrl", value.terms_of_service_url)
    |> Helpers.maybe_put("defaultPrompt", value.default_prompt)
    |> Helpers.maybe_put("brandColor", value.brand_color)
    |> Helpers.maybe_put("composerIcon", value.composer_icon)
    |> Helpers.maybe_put("logo", value.logo)
    |> Map.put("screenshots", value.screenshots)
    |> Map.merge(value.extra)
  end

  defp build(parsed) do
    {known, extra} = Helpers.split_extra(parsed, @known_fields)

    %__MODULE__{
      display_name: Map.get(known, "displayName"),
      short_description: Map.get(known, "shortDescription"),
      long_description: Map.get(known, "longDescription"),
      developer_name: Map.get(known, "developerName"),
      category: Map.get(known, "category"),
      capabilities: Map.get(known, "capabilities", []),
      website_url: Map.get(known, "websiteUrl"),
      privacy_policy_url: Map.get(known, "privacyPolicyUrl"),
      terms_of_service_url: Map.get(known, "termsOfServiceUrl"),
      default_prompt: Map.get(known, "defaultPrompt"),
      brand_color: Map.get(known, "brandColor"),
      composer_icon: Map.get(known, "composerIcon"),
      logo: Map.get(known, "logo"),
      screenshots: Map.get(known, "screenshots", []),
      extra: extra
    }
  end
end

defmodule Codex.Protocol.Plugin.SkillSummary do
  @moduledoc """
  Plugin skill metadata returned by `plugin/read`.
  """

  use TypedStruct

  alias Codex.Protocol.Plugin.Helpers

  @key_mapping %{"short_description" => "shortDescription"}
  @known_fields ["name", "description", "shortDescription", "interface", "path", "enabled"]
  @schema Zoi.map(
            %{
              "name" => Helpers.required_string(),
              "description" => Helpers.required_string(),
              "shortDescription" => Helpers.optional_string(),
              "interface" => Helpers.optional_map(),
              "path" => Helpers.required_string(),
              "enabled" => Zoi.boolean()
            },
            unrecognized_keys: :preserve
          )

  typedstruct do
    field(:name, String.t(), enforce: true)
    field(:description, String.t(), enforce: true)
    field(:short_description, String.t() | nil)
    field(:interface, map() | nil)
    field(:path, String.t(), enforce: true)
    field(:enabled, boolean(), enforce: true)
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error, {:invalid_plugin_skill_summary, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = value), do: {:ok, value}

  def parse(data) do
    Helpers.parse(@schema, data, :invalid_plugin_skill_summary, @key_mapping, &build/1)
  end

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = value), do: value

  def parse!(data) do
    Helpers.parse!(@schema, data, :invalid_plugin_skill_summary, @key_mapping, &build/1)
  end

  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{
      "name" => value.name,
      "description" => value.description,
      "path" => value.path,
      "enabled" => value.enabled
    }
    |> Helpers.maybe_put("shortDescription", value.short_description)
    |> Helpers.maybe_put("interface", value.interface)
    |> Map.merge(value.extra)
  end

  defp build(parsed) do
    {known, extra} = Helpers.split_extra(parsed, @known_fields)

    %__MODULE__{
      name: Map.fetch!(known, "name"),
      description: Map.fetch!(known, "description"),
      short_description: Map.get(known, "shortDescription"),
      interface: Map.get(known, "interface"),
      path: Map.fetch!(known, "path"),
      enabled: Map.fetch!(known, "enabled"),
      extra: extra
    }
  end
end

defmodule Codex.Protocol.Plugin.AppSummary do
  @moduledoc """
  Plugin app metadata returned by `plugin/read` and `plugin/install`.
  """

  use TypedStruct

  alias Codex.Protocol.Plugin.Helpers

  @key_mapping %{"install_url" => "installUrl", "needs_auth" => "needsAuth"}
  @known_fields ["id", "name", "description", "installUrl", "needsAuth"]
  @schema Zoi.map(
            %{
              "id" => Helpers.required_string(),
              "name" => Helpers.required_string(),
              "description" => Helpers.optional_string(),
              "installUrl" => Helpers.optional_string(),
              "needsAuth" => Helpers.boolean_flag()
            },
            unrecognized_keys: :preserve
          )

  typedstruct do
    field(:id, String.t(), enforce: true)
    field(:name, String.t(), enforce: true)
    field(:description, String.t() | nil)
    field(:install_url, String.t() | nil)
    field(:needs_auth, boolean(), default: false)
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error, {:invalid_plugin_app_summary, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = value), do: {:ok, value}

  def parse(data) do
    Helpers.parse(@schema, data, :invalid_plugin_app_summary, @key_mapping, &build/1)
  end

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = value), do: value

  def parse!(data),
    do: Helpers.parse!(@schema, data, :invalid_plugin_app_summary, @key_mapping, &build/1)

  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{
      "id" => value.id,
      "name" => value.name,
      "needsAuth" => value.needs_auth
    }
    |> Helpers.maybe_put("description", value.description)
    |> Helpers.maybe_put("installUrl", value.install_url)
    |> Map.merge(value.extra)
  end

  defp build(parsed) do
    {known, extra} = Helpers.split_extra(parsed, @known_fields)

    %__MODULE__{
      id: Map.fetch!(known, "id"),
      name: Map.fetch!(known, "name"),
      description: Map.get(known, "description"),
      install_url: Map.get(known, "installUrl"),
      needs_auth: Map.get(known, "needsAuth", false),
      extra: extra
    }
  end
end

defmodule Codex.Protocol.Plugin.Summary do
  @moduledoc """
  Plugin summary metadata returned by `plugin/list` and `plugin/read`.
  """

  use TypedStruct

  alias CliSubprocessCore.Schema.Conventions

  alias Codex.Protocol.Plugin.{
    AuthPolicy,
    Helpers,
    InstallPolicy,
    InstallPolicySource,
    Interface,
    Source
  }

  @key_mapping %{
    "install_policy" => "installPolicy",
    "install_policy_source" => "installPolicySource",
    "auth_policy" => "authPolicy"
  }
  @known_fields [
    "id",
    "name",
    "source",
    "installed",
    "enabled",
    "installPolicy",
    "installPolicySource",
    "authPolicy",
    "interface",
    "version"
  ]
  @schema Zoi.map(
            %{
              "id" => Helpers.required_string(),
              "name" => Helpers.required_string(),
              "source" => Conventions.any_map(),
              "installed" => Zoi.boolean(),
              "enabled" => Zoi.boolean(),
              "installPolicy" => InstallPolicy.schema(),
              "installPolicySource" => Zoi.optional(InstallPolicySource.schema()),
              "authPolicy" => AuthPolicy.schema(),
              "interface" => Helpers.optional_map(),
              "version" => Helpers.optional_string()
            },
            unrecognized_keys: :preserve
          )

  typedstruct do
    field(:id, String.t(), enforce: true)
    field(:name, String.t(), enforce: true)
    field(:source, Source.t(), enforce: true)
    field(:installed, boolean(), enforce: true)
    field(:enabled, boolean(), enforce: true)
    field(:install_policy, InstallPolicy.t(), enforce: true)
    field(:install_policy_source, InstallPolicySource.t() | nil)
    field(:auth_policy, AuthPolicy.t(), enforce: true)
    field(:interface, Interface.t() | nil)
    # Remote-marketplace advertised version, distinct from any locally
    # materialized package version that may ride along in `extra`.
    field(:version, String.t() | nil)
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error, {:invalid_plugin_summary, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = value), do: {:ok, value}

  def parse(data),
    do: Helpers.parse(@schema, data, :invalid_plugin_summary, @key_mapping, &build/1)

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = value), do: value

  def parse!(data),
    do: Helpers.parse!(@schema, data, :invalid_plugin_summary, @key_mapping, &build/1)

  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{
      "id" => value.id,
      "name" => value.name,
      "source" => Source.to_map(value.source),
      "installed" => value.installed,
      "enabled" => value.enabled,
      "installPolicy" => InstallPolicy.to_wire(value.install_policy),
      "authPolicy" => AuthPolicy.to_wire(value.auth_policy)
    }
    |> Helpers.maybe_put(
      "installPolicySource",
      encode_install_policy_source(value.install_policy_source)
    )
    |> Helpers.maybe_put("interface", Helpers.encode_nested(value.interface, Interface))
    |> Helpers.maybe_put("version", value.version)
    |> Map.merge(value.extra)
  end

  defp build(parsed) do
    {known, extra} = Helpers.split_extra(parsed, @known_fields)

    %__MODULE__{
      id: Map.fetch!(known, "id"),
      name: Map.fetch!(known, "name"),
      source: Helpers.parse_nested(Map.fetch!(known, "source"), Source),
      installed: Map.fetch!(known, "installed"),
      enabled: Map.fetch!(known, "enabled"),
      install_policy: Map.fetch!(known, "installPolicy"),
      install_policy_source: Map.get(known, "installPolicySource"),
      auth_policy: Map.fetch!(known, "authPolicy"),
      interface: Helpers.parse_nested(Map.get(known, "interface"), Interface),
      version: Map.get(known, "version"),
      extra: extra
    }
  end

  defp encode_install_policy_source(nil), do: nil
  defp encode_install_policy_source(value), do: InstallPolicySource.to_wire(value)
end

defmodule Codex.Protocol.Plugin.Marketplace do
  @moduledoc """
  Marketplace entries returned by `plugin/list`.
  """

  use TypedStruct

  alias Codex.Protocol.Plugin.{Helpers, MarketplaceInterface, Summary}

  @known_fields ["name", "path", "interface", "plugins"]
  @schema Zoi.map(
            %{
              "name" => Helpers.required_string(),
              "path" => Helpers.required_string(),
              "interface" => Helpers.optional_map(),
              "plugins" => Helpers.default_array(Helpers.any_map())
            },
            unrecognized_keys: :preserve
          )

  typedstruct do
    field(:name, String.t(), enforce: true)
    field(:path, String.t(), enforce: true)
    field(:interface, MarketplaceInterface.t() | nil)
    field(:plugins, [Summary.t()], default: [])
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error, {:invalid_plugin_marketplace, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = value), do: {:ok, value}
  def parse(data), do: Helpers.parse(@schema, data, :invalid_plugin_marketplace, %{}, &build/1)

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = value), do: value
  def parse!(data), do: Helpers.parse!(@schema, data, :invalid_plugin_marketplace, %{}, &build/1)

  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{
      "name" => value.name,
      "path" => value.path,
      "plugins" => Helpers.encode_list(value.plugins, Summary)
    }
    |> Helpers.maybe_put(
      "interface",
      Helpers.encode_nested(value.interface, MarketplaceInterface)
    )
    |> Map.merge(value.extra)
  end

  defp build(parsed) do
    {known, extra} = Helpers.split_extra(parsed, @known_fields)

    %__MODULE__{
      name: Map.fetch!(known, "name"),
      path: Map.fetch!(known, "path"),
      interface: Helpers.parse_nested(Map.get(known, "interface"), MarketplaceInterface),
      plugins: Helpers.parse_list(Map.get(known, "plugins"), Summary),
      extra: extra
    }
  end
end

defmodule Codex.Protocol.Plugin.ScheduledTaskSchedule do
  @moduledoc """
  Tagged schedule metadata for a plugin-provided scheduled task.

  Known tags are validated against the current hourly, daily, weekdays, and
  weekly shapes. Unknown string tags remain lossless for additive compatibility.
  Weekday values remain wire strings such as `"MO"` and `"WE"`.
  """

  use TypedStruct

  alias Codex.Protocol.Plugin.Helpers

  @key_mapping %{"interval_hours" => "intervalHours"}
  @known_fields ["type", "intervalHours", "days", "time"]
  @schema Zoi.map(
            %{
              "type" => Helpers.required_string(),
              "intervalHours" => Zoi.optional(Zoi.nullish(Zoi.integer())),
              "days" => Zoi.optional(Zoi.nullish(Zoi.array(Helpers.required_string()))),
              "time" => Helpers.optional_string()
            },
            unrecognized_keys: :preserve
          )
          |> Zoi.transform({__MODULE__, :validate_zoi, []})

  typedstruct do
    field(:type, String.t(), enforce: true)
    field(:interval_hours, non_neg_integer() | nil)
    field(:days, [String.t()] | nil)
    field(:time, String.t() | nil)
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error,
             {:invalid_plugin_scheduled_task_schedule, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = value), do: {:ok, value}

  def parse(data) do
    Helpers.parse(
      @schema,
      data,
      :invalid_plugin_scheduled_task_schedule,
      @key_mapping,
      &build/1
    )
  end

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = value), do: value

  def parse!(data) do
    Helpers.parse!(
      @schema,
      data,
      :invalid_plugin_scheduled_task_schedule,
      @key_mapping,
      &build/1
    )
  end

  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    value
    |> known_wire_fields()
    |> Map.merge(value.extra)
  end

  @doc false
  @spec validate_zoi(map(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def validate_zoi(%{"type" => "hourly", "intervalHours" => interval_hours} = value, _opts)
      when is_integer(interval_hours) and interval_hours >= 0,
      do: {:ok, value}

  def validate_zoi(%{"type" => type, "time" => time} = value, _opts)
      when type in ["daily", "weekdays"] and is_binary(time),
      do: {:ok, value}

  def validate_zoi(%{"type" => "weekly", "days" => days, "time" => time} = value, _opts)
      when is_list(days) and is_binary(time),
      do: {:ok, value}

  def validate_zoi(%{"type" => type} = value, _opts)
      when type not in ["hourly", "daily", "weekdays", "weekly"],
      do: {:ok, value}

  def validate_zoi(%{"type" => type}, _opts),
    do: {:error, "invalid fields for scheduled task schedule type #{inspect(type)}"}

  defp build(parsed) do
    {known, extra} = Helpers.split_extra(parsed, @known_fields)

    %__MODULE__{
      type: Map.fetch!(known, "type"),
      interval_hours: Map.get(known, "intervalHours"),
      days: Map.get(known, "days"),
      time: Map.get(known, "time"),
      extra: extra
    }
  end

  defp known_wire_fields(%__MODULE__{type: "hourly"} = value) do
    %{
      "type" => value.type,
      "intervalHours" => value.interval_hours,
      "days" => value.days
    }
  end

  defp known_wire_fields(%__MODULE__{type: type} = value)
       when type in ["daily", "weekdays"] do
    %{"type" => type, "time" => value.time}
  end

  defp known_wire_fields(%__MODULE__{type: "weekly"} = value) do
    %{"type" => value.type, "days" => value.days, "time" => value.time}
  end

  defp known_wire_fields(%__MODULE__{} = value) do
    %{"type" => value.type}
    |> Helpers.maybe_put("intervalHours", value.interval_hours)
    |> Helpers.maybe_put("days", value.days)
    |> Helpers.maybe_put("time", value.time)
  end
end

defmodule Codex.Protocol.Plugin.ScheduledTaskSummary do
  @moduledoc """
  A named plugin scheduled task and its typed schedule.
  """

  use TypedStruct

  alias Codex.Protocol.Plugin.{Helpers, ScheduledTaskSchedule}

  @known_fields ["key", "name", "prompt", "schedule"]
  @schema Zoi.map(
            %{
              "key" => Helpers.required_string(),
              "name" => Helpers.required_string(),
              "prompt" => Helpers.required_string(),
              "schedule" => Helpers.any_map()
            },
            unrecognized_keys: :preserve
          )

  typedstruct do
    field(:key, String.t(), enforce: true)
    field(:name, String.t(), enforce: true)
    field(:prompt, String.t(), enforce: true)
    field(:schedule, ScheduledTaskSchedule.t(), enforce: true)
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error,
             {:invalid_plugin_scheduled_task_summary, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = value), do: {:ok, value}

  def parse(data) do
    Helpers.parse(
      @schema,
      data,
      :invalid_plugin_scheduled_task_summary,
      %{},
      &build/1
    )
  end

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = value), do: value

  def parse!(data) do
    Helpers.parse!(
      @schema,
      data,
      :invalid_plugin_scheduled_task_summary,
      %{},
      &build/1
    )
  end

  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{
      "key" => value.key,
      "name" => value.name,
      "prompt" => value.prompt,
      "schedule" => ScheduledTaskSchedule.to_map(value.schedule)
    }
    |> Map.merge(value.extra)
  end

  defp build(parsed) do
    {known, extra} = Helpers.split_extra(parsed, @known_fields)

    %__MODULE__{
      key: Map.fetch!(known, "key"),
      name: Map.fetch!(known, "name"),
      prompt: Map.fetch!(known, "prompt"),
      schedule: Helpers.parse_nested(Map.fetch!(known, "schedule"), ScheduledTaskSchedule),
      extra: extra
    }
  end
end

defmodule Codex.Protocol.Plugin.Detail do
  @moduledoc """
  Plugin detail payload returned by `plugin/read`.
  """

  use TypedStruct

  alias Codex.Protocol.Plugin.{
    AppSummary,
    Helpers,
    ScheduledTaskSummary,
    SkillSummary,
    Summary
  }

  @key_mapping %{
    "marketplace_name" => "marketplaceName",
    "marketplace_path" => "marketplacePath",
    "mcp_servers" => "mcpServers",
    "scheduled_tasks" => "scheduledTasks"
  }
  @known_fields [
    "marketplaceName",
    "marketplacePath",
    "summary",
    "description",
    "skills",
    "apps",
    "mcpServers",
    "scheduledTasks"
  ]
  @schema Zoi.map(
            %{
              "marketplaceName" => Helpers.required_string(),
              "marketplacePath" => Helpers.required_string(),
              "summary" => Helpers.any_map(),
              "description" => Helpers.optional_string(),
              "skills" => Helpers.default_array(Helpers.any_map()),
              "apps" => Helpers.default_array(Helpers.any_map()),
              "mcpServers" => Helpers.default_string_list(),
              "scheduledTasks" => Zoi.optional(Zoi.nullish(Zoi.array(Helpers.any_map())))
            },
            unrecognized_keys: :preserve
          )

  typedstruct do
    field(:marketplace_name, String.t(), enforce: true)
    field(:marketplace_path, String.t(), enforce: true)
    field(:summary, Summary.t(), enforce: true)
    field(:description, String.t() | nil)
    field(:skills, [SkillSummary.t()], default: [])
    field(:apps, [AppSummary.t()], default: [])
    field(:mcp_servers, [String.t()], default: [])
    field(:scheduled_tasks, [ScheduledTaskSummary.t()] | nil)
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()} | {:error, {:invalid_plugin_detail, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = value), do: {:ok, value}

  def parse(data),
    do: Helpers.parse(@schema, data, :invalid_plugin_detail, @key_mapping, &build/1)

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = value), do: value

  def parse!(data),
    do: Helpers.parse!(@schema, data, :invalid_plugin_detail, @key_mapping, &build/1)

  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{
      "marketplaceName" => value.marketplace_name,
      "marketplacePath" => value.marketplace_path,
      "summary" => Summary.to_map(value.summary),
      "skills" => Helpers.encode_list(value.skills, SkillSummary),
      "apps" => Helpers.encode_list(value.apps, AppSummary),
      "mcpServers" => value.mcp_servers
    }
    |> Helpers.maybe_put("description", value.description)
    |> Helpers.maybe_put("scheduledTasks", encode_scheduled_tasks(value.scheduled_tasks))
    |> Map.merge(value.extra)
  end

  defp build(parsed) do
    {known, extra} = Helpers.split_extra(parsed, @known_fields)

    %__MODULE__{
      marketplace_name: Map.fetch!(known, "marketplaceName"),
      marketplace_path: Map.fetch!(known, "marketplacePath"),
      summary: Helpers.parse_nested(Map.fetch!(known, "summary"), Summary),
      description: Map.get(known, "description"),
      skills: Helpers.parse_list(Map.get(known, "skills"), SkillSummary),
      apps: Helpers.parse_list(Map.get(known, "apps"), AppSummary),
      mcp_servers: Map.get(known, "mcpServers", []),
      scheduled_tasks: parse_scheduled_tasks(Map.get(known, "scheduledTasks")),
      extra: extra
    }
  end

  defp parse_scheduled_tasks(nil), do: nil

  defp parse_scheduled_tasks(values),
    do: Helpers.parse_list(values, ScheduledTaskSummary)

  defp encode_scheduled_tasks(nil), do: nil

  defp encode_scheduled_tasks(values),
    do: Helpers.encode_list(values, ScheduledTaskSummary)
end

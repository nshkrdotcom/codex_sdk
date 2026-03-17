defmodule Codex.Protocol.RequestPermissions do
  @moduledoc """
  Types for app-server request-permissions approval requests and responses.
  """

  alias __MODULE__, as: RequestPermissions

  defmodule AdditionalNetworkPermissions do
    @moduledoc "Additional network permissions requested or granted for a turn or session."
    use TypedStruct

    typedstruct do
      field(:enabled, boolean() | nil)
    end

    @spec from_map(map() | keyword() | t() | nil) :: t() | nil
    def from_map(nil), do: nil
    def from_map(%__MODULE__{} = permissions), do: permissions
    def from_map(data) when is_list(data), do: data |> Map.new() |> from_map()

    def from_map(data) when is_map(data) do
      %__MODULE__{
        enabled: RequestPermissions.fetch_any(data, ["enabled", :enabled])
      }
    end

    @spec to_map(t() | nil) :: map() | nil
    def to_map(nil), do: nil

    def to_map(%__MODULE__{} = permissions) do
      %{}
      |> RequestPermissions.put_optional("enabled", permissions.enabled)
    end
  end

  defmodule AdditionalFileSystemPermissions do
    @moduledoc "Additional filesystem permissions requested or granted for a turn or session."
    use TypedStruct

    typedstruct do
      field(:read, [String.t()] | nil)
      field(:write, [String.t()] | nil)
    end

    @spec from_map(map() | keyword() | t() | nil) :: t() | nil
    def from_map(nil), do: nil
    def from_map(%__MODULE__{} = permissions), do: permissions
    def from_map(data) when is_list(data), do: data |> Map.new() |> from_map()

    def from_map(data) when is_map(data) do
      %__MODULE__{
        read: RequestPermissions.fetch_list(data, ["read", :read]),
        write: RequestPermissions.fetch_list(data, ["write", :write])
      }
    end

    @spec to_map(t() | nil) :: map() | nil
    def to_map(nil), do: nil

    def to_map(%__MODULE__{} = permissions) do
      %{}
      |> RequestPermissions.put_optional("read", permissions.read)
      |> RequestPermissions.put_optional("write", permissions.write)
    end
  end

  defmodule AdditionalMacOsPermissions do
    @moduledoc "Additional macOS permissions requested for a turn or session."
    use TypedStruct

    typedstruct do
      field(:preferences, String.t() | nil)
      field(:automations, String.t() | map() | nil)
      field(:launch_services, boolean() | nil)
      field(:accessibility, boolean() | nil)
      field(:calendar, boolean() | nil)
      field(:reminders, boolean() | nil)
      field(:contacts, String.t() | nil)
    end

    @spec from_map(map() | keyword() | t() | nil) :: t() | nil
    def from_map(nil), do: nil
    def from_map(%__MODULE__{} = permissions), do: permissions
    def from_map(data) when is_list(data), do: data |> Map.new() |> from_map()

    def from_map(data) when is_map(data) do
      %__MODULE__{
        preferences: RequestPermissions.fetch_any(data, ["preferences", :preferences]),
        automations:
          data
          |> RequestPermissions.fetch_any(["automations", :automations])
          |> RequestPermissions.normalize_union_value(),
        launch_services:
          RequestPermissions.fetch_any(data, [
            "launchServices",
            "launch_services",
            :launchServices,
            :launch_services
          ]),
        accessibility: RequestPermissions.fetch_any(data, ["accessibility", :accessibility]),
        calendar: RequestPermissions.fetch_any(data, ["calendar", :calendar]),
        reminders: RequestPermissions.fetch_any(data, ["reminders", :reminders]),
        contacts: RequestPermissions.fetch_any(data, ["contacts", :contacts])
      }
    end

    @spec to_map(t() | nil) :: map() | nil
    def to_map(nil), do: nil

    def to_map(%__MODULE__{} = permissions) do
      %{}
      |> RequestPermissions.put_optional("preferences", permissions.preferences)
      |> RequestPermissions.put_optional("automations", permissions.automations)
      |> RequestPermissions.put_optional("launchServices", permissions.launch_services)
      |> RequestPermissions.put_optional("accessibility", permissions.accessibility)
      |> RequestPermissions.put_optional("calendar", permissions.calendar)
      |> RequestPermissions.put_optional("reminders", permissions.reminders)
      |> RequestPermissions.put_optional("contacts", permissions.contacts)
    end
  end

  defmodule GrantedMacOsPermissions do
    @moduledoc "Additional macOS permissions granted for a turn or session."
    use TypedStruct

    typedstruct do
      field(:preferences, String.t() | nil)
      field(:automations, String.t() | map() | nil)
      field(:launch_services, boolean() | nil)
      field(:accessibility, boolean() | nil)
      field(:calendar, boolean() | nil)
      field(:reminders, boolean() | nil)
      field(:contacts, String.t() | nil)
    end

    @spec from_map(map() | keyword() | t() | nil) :: t() | nil
    def from_map(nil), do: nil
    def from_map(%__MODULE__{} = permissions), do: permissions
    def from_map(data) when is_list(data), do: data |> Map.new() |> from_map()

    def from_map(data) when is_map(data) do
      %__MODULE__{
        preferences: RequestPermissions.fetch_any(data, ["preferences", :preferences]),
        automations:
          data
          |> RequestPermissions.fetch_any(["automations", :automations])
          |> RequestPermissions.normalize_union_value(),
        launch_services:
          RequestPermissions.fetch_any(data, [
            "launchServices",
            "launch_services",
            :launchServices,
            :launch_services
          ]),
        accessibility: RequestPermissions.fetch_any(data, ["accessibility", :accessibility]),
        calendar: RequestPermissions.fetch_any(data, ["calendar", :calendar]),
        reminders: RequestPermissions.fetch_any(data, ["reminders", :reminders]),
        contacts: RequestPermissions.fetch_any(data, ["contacts", :contacts])
      }
    end

    @spec to_map(t() | nil) :: map() | nil
    def to_map(nil), do: nil

    def to_map(%__MODULE__{} = permissions) do
      %{}
      |> RequestPermissions.put_optional("preferences", permissions.preferences)
      |> RequestPermissions.put_optional("automations", permissions.automations)
      |> RequestPermissions.put_optional("launchServices", permissions.launch_services)
      |> RequestPermissions.put_optional("accessibility", permissions.accessibility)
      |> RequestPermissions.put_optional("calendar", permissions.calendar)
      |> RequestPermissions.put_optional("reminders", permissions.reminders)
      |> RequestPermissions.put_optional("contacts", permissions.contacts)
    end
  end

  defmodule RequestPermissionProfile do
    @moduledoc "Permission profile included in request-permissions approval requests."
    use TypedStruct

    typedstruct do
      field(:network, AdditionalNetworkPermissions.t() | nil)
      field(:file_system, AdditionalFileSystemPermissions.t() | nil)
      field(:macos, AdditionalMacOsPermissions.t() | nil)
    end

    @spec from_map(map() | keyword() | t() | nil) :: t()
    def from_map(nil), do: %__MODULE__{}
    def from_map(%__MODULE__{} = profile), do: profile
    def from_map(data) when is_list(data), do: data |> Map.new() |> from_map()

    def from_map(data) when is_map(data) do
      %__MODULE__{
        network:
          data
          |> RequestPermissions.fetch_any(["network", :network])
          |> AdditionalNetworkPermissions.from_map(),
        file_system:
          data
          |> RequestPermissions.fetch_any([
            "fileSystem",
            "file_system",
            :fileSystem,
            :file_system
          ])
          |> AdditionalFileSystemPermissions.from_map(),
        macos:
          data
          |> RequestPermissions.fetch_any(["macos", :macos])
          |> AdditionalMacOsPermissions.from_map()
      }
    end

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = profile) do
      %{}
      |> RequestPermissions.put_optional(
        "network",
        AdditionalNetworkPermissions.to_map(profile.network)
      )
      |> RequestPermissions.put_optional(
        "fileSystem",
        AdditionalFileSystemPermissions.to_map(profile.file_system)
      )
      |> RequestPermissions.put_optional(
        "macos",
        AdditionalMacOsPermissions.to_map(profile.macos)
      )
    end
  end

  defmodule GrantedPermissionProfile do
    @moduledoc "Permission profile included in request-permissions approval responses."
    use TypedStruct

    typedstruct do
      field(:network, AdditionalNetworkPermissions.t() | nil)
      field(:file_system, AdditionalFileSystemPermissions.t() | nil)
      field(:macos, GrantedMacOsPermissions.t() | nil)
    end

    @spec from_map(map() | keyword() | t() | nil) :: t()
    def from_map(nil), do: %__MODULE__{}
    def from_map(%__MODULE__{} = profile), do: profile
    def from_map(data) when is_list(data), do: data |> Map.new() |> from_map()

    def from_map(data) when is_map(data) do
      %__MODULE__{
        network:
          data
          |> RequestPermissions.fetch_any(["network", :network])
          |> AdditionalNetworkPermissions.from_map(),
        file_system:
          data
          |> RequestPermissions.fetch_any([
            "fileSystem",
            "file_system",
            :fileSystem,
            :file_system
          ])
          |> AdditionalFileSystemPermissions.from_map(),
        macos:
          data
          |> RequestPermissions.fetch_any(["macos", :macos])
          |> GrantedMacOsPermissions.from_map()
      }
    end

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = profile) do
      %{}
      |> RequestPermissions.put_optional(
        "network",
        AdditionalNetworkPermissions.to_map(profile.network)
      )
      |> RequestPermissions.put_optional(
        "fileSystem",
        AdditionalFileSystemPermissions.to_map(profile.file_system)
      )
      |> RequestPermissions.put_optional("macos", GrantedMacOsPermissions.to_map(profile.macos))
    end
  end

  defmodule PermissionGrantScope do
    @moduledoc "Scope applied to granted permissions in a permissions approval response."

    @type t :: :turn | :session

    @spec from_value(t() | String.t() | nil) :: t()
    def from_value(nil), do: :turn
    def from_value(:turn), do: :turn
    def from_value(:session), do: :session
    def from_value("turn"), do: :turn
    def from_value("session"), do: :session
    def from_value(_), do: :turn

    @spec to_value(t() | String.t() | nil) :: String.t()
    def to_value(value), do: value |> from_value() |> Atom.to_string()
  end

  defmodule Response do
    @moduledoc "Structured response for an app-server permissions approval request."
    use TypedStruct

    typedstruct do
      field(:permissions, GrantedPermissionProfile.t(), default: %GrantedPermissionProfile{})
      field(:scope, PermissionGrantScope.t(), default: :turn)
    end

    @spec from_map(map() | keyword() | t() | nil) :: t()
    def from_map(nil), do: %__MODULE__{}
    def from_map(%__MODULE__{} = response), do: response
    def from_map(data) when is_list(data), do: data |> Map.new() |> from_map()

    def from_map(data) when is_map(data) do
      %__MODULE__{
        permissions:
          data
          |> RequestPermissions.fetch_any(["permissions", :permissions])
          |> GrantedPermissionProfile.from_map(),
        scope:
          data
          |> RequestPermissions.fetch_any(["scope", :scope])
          |> PermissionGrantScope.from_value()
      }
    end

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = response) do
      %{
        "permissions" => GrantedPermissionProfile.to_map(response.permissions),
        "scope" => PermissionGrantScope.to_value(response.scope)
      }
    end
  end

  @doc false
  def fetch_any(map, keys) when is_map(map) do
    Enum.reduce_while(keys, nil, fn key, _acc ->
      if Map.has_key?(map, key) do
        {:halt, Map.get(map, key)}
      else
        {:cont, nil}
      end
    end)
  end

  @doc false
  def fetch_list(map, keys) when is_map(map) do
    case fetch_any(map, keys) do
      nil -> nil
      values when is_list(values) -> values
      value -> List.wrap(value)
    end
  end

  @doc false
  def normalize_union_value(nil), do: nil
  def normalize_union_value(%{} = value), do: value

  def normalize_union_value(value) when is_list(value),
    do: value |> Map.new() |> normalize_union_value()

  def normalize_union_value(value), do: to_string(value)

  @doc false
  def put_optional(map, _key, nil), do: map

  def put_optional(map, _key, value) when value == %{}, do: map
  def put_optional(map, key, value), do: Map.put(map, key, value)
end

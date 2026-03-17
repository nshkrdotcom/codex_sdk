defmodule Codex.AppServer.ApprovalDecision do
  @moduledoc false

  alias Codex.Protocol.RequestPermissions

  @type wire_decision :: String.t() | map()

  @spec from_hook(term()) :: wire_decision()
  def from_hook(:allow), do: "accept"

  def from_hook({:allow, opts}) when is_list(opts) do
    cond do
      Keyword.get(opts, :for_session, false) ->
        "acceptForSession"

      Keyword.get(opts, :grant_root) not in [nil, false] ->
        "acceptForSession"

      execpolicy_amendment = Keyword.get(opts, :execpolicy_amendment) ->
        %{
          "acceptWithExecpolicyAmendment" => %{
            "execpolicyAmendment" => List.wrap(execpolicy_amendment)
          }
        }

      true ->
        "accept"
    end
  end

  def from_hook({:deny, reason}) when reason in [:cancel, "cancel"], do: "cancel"
  def from_hook({:deny, _reason}), do: "decline"

  def from_hook(other) when other in [:decline, :cancel, "decline", "cancel"] do
    to_string(other)
  end

  def from_hook(_), do: "decline"

  @spec from_permissions_hook(
          term(),
          RequestPermissions.RequestPermissionProfile.t() | map() | nil
        ) :: map()
  def from_permissions_hook(decision, requested_permissions) do
    requested = RequestPermissions.RequestPermissionProfile.from_map(requested_permissions)

    case decision do
      :allow ->
        requested
        |> grant_all_requested()
        |> permissions_response(:turn)

      {:allow, opts} when is_list(opts) ->
        permissions =
          opts
          |> Keyword.get(:permissions, requested)
          |> intersect_requested_permissions(requested)

        scope = Keyword.get(opts, :scope, :turn)

        permissions_response(permissions, scope)

      {:deny, _reason} ->
        permissions_response(%RequestPermissions.GrantedPermissionProfile{}, :turn)

      _ ->
        permissions_response(%RequestPermissions.GrantedPermissionProfile{}, :turn)
    end
  end

  defp permissions_response(%RequestPermissions.GrantedPermissionProfile{} = permissions, scope) do
    %RequestPermissions.Response{permissions: permissions, scope: normalize_scope(scope)}
    |> RequestPermissions.Response.to_map()
  end

  defp normalize_scope(:session), do: :session
  defp normalize_scope("session"), do: :session
  defp normalize_scope(_), do: :turn

  defp grant_all_requested(%RequestPermissions.RequestPermissionProfile{} = requested) do
    %RequestPermissions.GrantedPermissionProfile{
      network: copy_network_permissions(requested.network),
      file_system: copy_file_system_permissions(requested.file_system),
      macos: copy_macos_permissions(requested.macos)
    }
  end

  defp intersect_requested_permissions(granted_permissions, requested_permissions) do
    granted = RequestPermissions.GrantedPermissionProfile.from_map(granted_permissions)

    %RequestPermissions.GrantedPermissionProfile{
      network: intersect_network_permissions(requested_permissions.network, granted.network),
      file_system:
        intersect_file_system_permissions(requested_permissions.file_system, granted.file_system),
      macos: intersect_macos_permissions(requested_permissions.macos, granted.macos)
    }
  end

  defp intersect_network_permissions(
         %RequestPermissions.AdditionalNetworkPermissions{enabled: true},
         %RequestPermissions.AdditionalNetworkPermissions{enabled: true}
       ) do
    %RequestPermissions.AdditionalNetworkPermissions{enabled: true}
  end

  defp intersect_network_permissions(_requested, _granted), do: nil

  defp intersect_file_system_permissions(
         %RequestPermissions.AdditionalFileSystemPermissions{} = requested,
         %RequestPermissions.AdditionalFileSystemPermissions{} = granted
       ) do
    %RequestPermissions.AdditionalFileSystemPermissions{
      read: intersect_path_lists(requested.read, granted.read),
      write: intersect_path_lists(requested.write, granted.write)
    }
    |> empty_file_system_permissions_to_nil()
  end

  defp intersect_file_system_permissions(_requested, _granted), do: nil

  defp intersect_macos_permissions(
         %RequestPermissions.AdditionalMacOsPermissions{} = requested,
         %RequestPermissions.GrantedMacOsPermissions{} = granted
       ) do
    %RequestPermissions.GrantedMacOsPermissions{
      preferences: intersect_permission_level(requested.preferences, granted.preferences),
      automations: intersect_automation_permissions(requested.automations, granted.automations),
      launch_services:
        intersect_boolean_permission(requested.launch_services, granted.launch_services),
      accessibility: intersect_boolean_permission(requested.accessibility, granted.accessibility),
      calendar: intersect_boolean_permission(requested.calendar, granted.calendar),
      reminders: intersect_boolean_permission(requested.reminders, granted.reminders),
      contacts: intersect_permission_level(requested.contacts, granted.contacts)
    }
    |> empty_macos_permissions_to_nil()
  end

  defp intersect_macos_permissions(_requested, _granted), do: nil

  defp intersect_path_lists(nil, _granted), do: nil
  defp intersect_path_lists(_requested, nil), do: nil

  defp intersect_path_lists(requested, granted) when is_list(requested) and is_list(granted) do
    allowed = MapSet.new(granted)
    values = Enum.filter(requested, &MapSet.member?(allowed, &1))
    if values == [], do: nil, else: values
  end

  defp copy_network_permissions(nil), do: nil

  defp copy_network_permissions(%RequestPermissions.AdditionalNetworkPermissions{} = permissions) do
    %RequestPermissions.AdditionalNetworkPermissions{enabled: permissions.enabled}
  end

  defp copy_file_system_permissions(nil), do: nil

  defp copy_file_system_permissions(
         %RequestPermissions.AdditionalFileSystemPermissions{} = permissions
       ) do
    %RequestPermissions.AdditionalFileSystemPermissions{
      read: permissions.read,
      write: permissions.write
    }
  end

  defp copy_macos_permissions(nil), do: nil

  defp copy_macos_permissions(%RequestPermissions.AdditionalMacOsPermissions{} = permissions) do
    %RequestPermissions.GrantedMacOsPermissions{
      preferences: normalize_permission_level(permissions.preferences),
      automations: copy_automation_permissions(permissions.automations),
      launch_services: permissions.launch_services,
      accessibility: permissions.accessibility,
      calendar: permissions.calendar,
      reminders: permissions.reminders,
      contacts: normalize_permission_level(permissions.contacts)
    }
    |> empty_macos_permissions_to_nil()
  end

  defp empty_file_system_permissions_to_nil(%RequestPermissions.AdditionalFileSystemPermissions{
         read: nil,
         write: nil
       }),
       do: nil

  defp empty_file_system_permissions_to_nil(permissions), do: permissions

  defp empty_macos_permissions_to_nil(%RequestPermissions.GrantedMacOsPermissions{} = permissions) do
    if Enum.all?(
         [
           permissions.preferences,
           permissions.automations,
           permissions.launch_services,
           permissions.accessibility,
           permissions.calendar,
           permissions.reminders,
           permissions.contacts
         ],
         &is_nil/1
       ) do
      nil
    else
      permissions
    end
  end

  defp intersect_boolean_permission(true, true), do: true
  defp intersect_boolean_permission(_, _), do: nil

  defp intersect_permission_level(requested, granted) do
    case {permission_level_rank(requested), permission_level_rank(granted)} do
      {req, grant} when is_integer(req) and is_integer(grant) and req > 0 and grant > 0 ->
        min(req, grant) |> permission_level_from_rank()

      _ ->
        nil
    end
  end

  defp copy_automation_permissions(nil), do: nil
  defp copy_automation_permissions(%{} = value), do: value

  defp copy_automation_permissions(value) when is_binary(value),
    do: normalize_automation_permission(value)

  defp intersect_automation_permissions(requested, granted) do
    requested = normalize_automation_permission(requested)
    granted = normalize_automation_permission(granted)
    do_intersect_automation_permissions(requested, granted)
  end

  defp do_intersect_automation_permissions("all", "all"), do: "all"

  defp do_intersect_automation_permissions("all", %{"bundle_ids" => bundle_ids})
       when is_list(bundle_ids) and bundle_ids != [] do
    %{"bundle_ids" => bundle_ids}
  end

  defp do_intersect_automation_permissions(%{"bundle_ids" => bundle_ids}, "all")
       when is_list(bundle_ids) and bundle_ids != [] do
    %{"bundle_ids" => bundle_ids}
  end

  defp do_intersect_automation_permissions(
         %{"bundle_ids" => requested_ids},
         %{"bundle_ids" => granted_ids}
       )
       when is_list(requested_ids) and is_list(granted_ids) do
    granted = MapSet.new(granted_ids)
    bundle_ids = Enum.filter(requested_ids, &MapSet.member?(granted, &1))
    if bundle_ids == [], do: nil, else: %{"bundle_ids" => bundle_ids}
  end

  defp do_intersect_automation_permissions(_requested, _granted), do: nil

  defp normalize_permission_level(nil), do: nil

  defp normalize_permission_level(value) when is_binary(value) do
    case value do
      "none" -> nil
      "read_only" -> "read_only"
      "read_write" -> "read_write"
      _ -> nil
    end
  end

  defp permission_level_rank(value) do
    case normalize_permission_level(value) do
      "read_only" -> 1
      "read_write" -> 2
      _ -> 0
    end
  end

  defp permission_level_from_rank(1), do: "read_only"
  defp permission_level_from_rank(2), do: "read_write"

  defp normalize_automation_permission(nil), do: nil
  defp normalize_automation_permission("none"), do: nil
  defp normalize_automation_permission("all"), do: "all"

  defp normalize_automation_permission(%{"bundle_ids" => bundle_ids}) when is_list(bundle_ids),
    do: %{"bundle_ids" => bundle_ids}

  defp normalize_automation_permission(%{bundle_ids: bundle_ids}) when is_list(bundle_ids),
    do: %{"bundle_ids" => bundle_ids}

  defp normalize_automation_permission(value) when is_binary(value), do: value

  defp normalize_automation_permission(value),
    do: value |> to_string() |> normalize_automation_permission()
end

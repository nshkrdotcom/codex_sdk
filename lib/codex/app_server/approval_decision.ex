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
      file_system: copy_file_system_permissions(requested.file_system)
    }
  end

  defp intersect_requested_permissions(granted_permissions, requested_permissions) do
    granted = RequestPermissions.GrantedPermissionProfile.from_map(granted_permissions)

    %RequestPermissions.GrantedPermissionProfile{
      network: intersect_network_permissions(requested_permissions.network, granted.network),
      file_system:
        intersect_file_system_permissions(requested_permissions.file_system, granted.file_system)
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

  defp empty_file_system_permissions_to_nil(%RequestPermissions.AdditionalFileSystemPermissions{
         read: nil,
         write: nil
       }),
       do: nil

  defp empty_file_system_permissions_to_nil(permissions), do: permissions
end

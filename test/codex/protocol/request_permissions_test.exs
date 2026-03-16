defmodule Codex.Protocol.RequestPermissionsTest do
  use ExUnit.Case, async: true

  alias Codex.Protocol.RequestPermissions

  test "request permission profile parses and serializes with camelCase keys" do
    data = %{
      "network" => %{"enabled" => true},
      "fileSystem" => %{
        "read" => ["/tmp/read-only"],
        "write" => ["/tmp/read-write"]
      }
    }

    assert %RequestPermissions.RequestPermissionProfile{
             network: %RequestPermissions.AdditionalNetworkPermissions{enabled: true},
             file_system: %RequestPermissions.AdditionalFileSystemPermissions{
               read: ["/tmp/read-only"],
               write: ["/tmp/read-write"]
             }
           } = RequestPermissions.RequestPermissionProfile.from_map(data)

    assert data ==
             data
             |> RequestPermissions.RequestPermissionProfile.from_map()
             |> RequestPermissions.RequestPermissionProfile.to_map()
  end

  test "granted permission profile accepts atom-key input and serializes with camelCase keys" do
    data = %{
      network: %{enabled: true},
      file_system: %{read: ["/tmp/read-only"], write: ["/tmp/read-write"]}
    }

    assert %RequestPermissions.GrantedPermissionProfile{
             network: %RequestPermissions.AdditionalNetworkPermissions{enabled: true},
             file_system: %RequestPermissions.AdditionalFileSystemPermissions{
               read: ["/tmp/read-only"],
               write: ["/tmp/read-write"]
             }
           } = RequestPermissions.GrantedPermissionProfile.from_map(data)

    assert %{
             "network" => %{"enabled" => true},
             "fileSystem" => %{
               "read" => ["/tmp/read-only"],
               "write" => ["/tmp/read-write"]
             }
           } =
             data
             |> RequestPermissions.GrantedPermissionProfile.from_map()
             |> RequestPermissions.GrantedPermissionProfile.to_map()
  end

  test "permission grant scope parses and serializes" do
    assert :turn == RequestPermissions.PermissionGrantScope.from_value("turn")
    assert :session == RequestPermissions.PermissionGrantScope.from_value(:session)
    assert "turn" == RequestPermissions.PermissionGrantScope.to_value(:turn)
    assert "session" == RequestPermissions.PermissionGrantScope.to_value("session")
  end

  test "permissions approval response parses and serializes" do
    data = %{
      "permissions" => %{
        "network" => %{"enabled" => true},
        "fileSystem" => %{"write" => ["/tmp/project"]}
      },
      "scope" => "session"
    }

    assert %RequestPermissions.Response{
             permissions: %RequestPermissions.GrantedPermissionProfile{
               network: %RequestPermissions.AdditionalNetworkPermissions{enabled: true},
               file_system: %RequestPermissions.AdditionalFileSystemPermissions{
                 write: ["/tmp/project"]
               }
             },
             scope: :session
           } = RequestPermissions.Response.from_map(data)

    assert data ==
             data
             |> RequestPermissions.Response.from_map()
             |> RequestPermissions.Response.to_map()
  end

  test "empty grants serialize as an empty permissions profile" do
    response = %RequestPermissions.Response{
      permissions: %RequestPermissions.GrantedPermissionProfile{},
      scope: :turn
    }

    assert %{"permissions" => %{}, "scope" => "turn"} ==
             RequestPermissions.Response.to_map(response)
  end
end

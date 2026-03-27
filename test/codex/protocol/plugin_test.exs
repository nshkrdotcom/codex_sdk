defmodule Codex.Protocol.PluginTest do
  use ExUnit.Case, async: true

  alias Codex.Protocol.Plugin

  test "list response parses minimal payload and preserves unknown fields" do
    payload = %{
      "marketplaces" => [
        %{
          "name" => "codex-curated",
          "path" => "/tmp/marketplace.json",
          "interface" => %{"displayName" => "Codex Curated", "theme" => "blue"},
          "plugins" => [
            %{
              "id" => "demo-plugin@codex-curated",
              "name" => "demo-plugin",
              "source" => %{"type" => "local", "path" => "/tmp/plugins/demo-plugin"},
              "installed" => false,
              "enabled" => false,
              "installPolicy" => "AVAILABLE",
              "authPolicy" => "ON_INSTALL",
              "interface" => %{"displayName" => "Demo Plugin", "betaBadge" => true},
              "futureSummaryField" => "kept"
            }
          ],
          "extraMarketplaceField" => 1
        }
      ],
      "marketplaceLoadErrors" => [
        %{
          "marketplacePath" => "/tmp/bad-marketplace.json",
          "message" => "invalid marketplace file",
          "retryable" => true
        }
      ],
      "remoteSyncError" => "remote sync failed",
      "featuredPluginIds" => ["demo-plugin@codex-curated"],
      "serverRevision" => "2026-03-27"
    }

    assert {:ok,
            %Plugin.ListResponse{
              remote_sync_error: "remote sync failed",
              featured_plugin_ids: ["demo-plugin@codex-curated"],
              extra: %{"serverRevision" => "2026-03-27"},
              marketplaces: [
                %Plugin.Marketplace{
                  name: "codex-curated",
                  path: "/tmp/marketplace.json",
                  extra: %{"extraMarketplaceField" => 1},
                  interface: %Plugin.MarketplaceInterface{
                    display_name: "Codex Curated",
                    extra: %{"theme" => "blue"}
                  },
                  plugins: [
                    %Plugin.Summary{
                      id: "demo-plugin@codex-curated",
                      name: "demo-plugin",
                      install_policy: :available,
                      auth_policy: :on_install,
                      extra: %{"futureSummaryField" => "kept"},
                      source: %Plugin.Source{
                        type: :local,
                        path: "/tmp/plugins/demo-plugin"
                      },
                      interface: %Plugin.Interface{
                        display_name: "Demo Plugin",
                        extra: %{"betaBadge" => true}
                      }
                    }
                  ]
                }
              ],
              marketplace_load_errors: [
                %Plugin.MarketplaceLoadError{
                  marketplace_path: "/tmp/bad-marketplace.json",
                  message: "invalid marketplace file",
                  extra: %{"retryable" => true}
                }
              ]
            }} = Plugin.ListResponse.parse(payload)

    assert %{
             "serverRevision" => "2026-03-27",
             "remoteSyncError" => "remote sync failed",
             "featuredPluginIds" => ["demo-plugin@codex-curated"],
             "marketplaceLoadErrors" => [
               %{
                 "marketplacePath" => "/tmp/bad-marketplace.json",
                 "message" => "invalid marketplace file",
                 "retryable" => true
               }
             ]
           } = Plugin.ListResponse.to_map(Plugin.ListResponse.from_map(payload))
  end

  test "read response parses app needsAuth and preserves unknown plugin metadata" do
    payload = %{
      "plugin" => %{
        "marketplaceName" => "codex-curated",
        "marketplacePath" => "/tmp/marketplace.json",
        "summary" => %{
          "id" => "demo-plugin@codex-curated",
          "name" => "demo-plugin",
          "source" => %{"type" => "local", "path" => "/tmp/plugins/demo-plugin"},
          "installed" => true,
          "enabled" => true,
          "installPolicy" => "AVAILABLE",
          "authPolicy" => "ON_INSTALL"
        },
        "description" => "Demo plugin",
        "skills" => [],
        "apps" => [
          %{
            "id" => "gmail",
            "name" => "Gmail",
            "installUrl" => "https://chatgpt.com/apps/gmail/gmail",
            "needsAuth" => true,
            "reviewStatus" => "pending"
          }
        ],
        "mcpServers" => ["demo"],
        "futurePluginField" => %{"status" => "beta"}
      }
    }

    assert {:ok,
            %Plugin.ReadResponse{
              plugin: %Plugin.Detail{
                marketplace_name: "codex-curated",
                marketplace_path: "/tmp/marketplace.json",
                description: "Demo plugin",
                mcp_servers: ["demo"],
                extra: %{"futurePluginField" => %{"status" => "beta"}},
                apps: [
                  %Plugin.AppSummary{
                    id: "gmail",
                    name: "Gmail",
                    install_url: "https://chatgpt.com/apps/gmail/gmail",
                    needs_auth: true,
                    extra: %{"reviewStatus" => "pending"}
                  }
                ]
              }
            }} = Plugin.ReadResponse.parse(payload)
  end

  test "install response parses apps needing auth" do
    payload = %{
      "authPolicy" => "ON_USE",
      "appsNeedingAuth" => [
        %{
          "id" => "gmail",
          "name" => "Gmail",
          "description" => "Mail",
          "installUrl" => "https://chatgpt.com/apps/gmail/gmail",
          "needsAuth" => true
        }
      ],
      "futureInstallField" => "kept"
    }

    assert {:ok,
            %Plugin.InstallResponse{
              auth_policy: :on_use,
              extra: %{"futureInstallField" => "kept"},
              apps_needing_auth: [
                %Plugin.AppSummary{
                  id: "gmail",
                  name: "Gmail",
                  description: "Mail",
                  install_url: "https://chatgpt.com/apps/gmail/gmail",
                  needs_auth: true
                }
              ]
            }} = Plugin.InstallResponse.parse(payload)
  end

  test "uninstall response handles intentionally minimal payload" do
    assert {:ok, %Plugin.UninstallResponse{extra: %{}}} = Plugin.UninstallResponse.parse(%{})
    assert %{} = Plugin.UninstallResponse.to_map(%Plugin.UninstallResponse{})
  end

  test "param modules encode app-server wire casing" do
    assert %{
             "cwds" => ["/tmp/project"],
             "forceRemoteSync" => true,
             "futureListField" => "kept"
           } =
             Plugin.ListParams.to_map(
               Plugin.ListParams.from_map(
                 cwds: ["/tmp/project"],
                 force_remote_sync: true,
                 futureListField: "kept"
               )
             )

    assert %{
             "marketplacePath" => "/tmp/marketplace.json",
             "pluginName" => "demo-plugin",
             "futureReadField" => "kept"
           } =
             Plugin.ReadParams.to_map(
               Plugin.ReadParams.from_map(
                 marketplace_path: "/tmp/marketplace.json",
                 plugin_name: "demo-plugin",
                 futureReadField: "kept"
               )
             )

    assert %{
             "marketplacePath" => "/tmp/marketplace.json",
             "pluginName" => "demo-plugin",
             "forceRemoteSync" => true,
             "futureInstallField" => "kept"
           } =
             Plugin.InstallParams.to_map(
               Plugin.InstallParams.from_map(
                 marketplace_path: "/tmp/marketplace.json",
                 plugin_name: "demo-plugin",
                 force_remote_sync: true,
                 futureInstallField: "kept"
               )
             )

    assert %{
             "pluginId" => "demo-plugin@codex-curated",
             "forceRemoteSync" => true,
             "futureUninstallField" => "kept"
           } =
             Plugin.UninstallParams.to_map(
               Plugin.UninstallParams.from_map(
                 plugin_id: "demo-plugin@codex-curated",
                 force_remote_sync: true,
                 futureUninstallField: "kept"
               )
             )
  end

  test "unknown enum values are preserved while known values normalize" do
    assert {:ok, :available} = Plugin.InstallPolicy.parse("AVAILABLE")
    assert {:ok, :on_install} = Plugin.AuthPolicy.parse("ON_INSTALL")
    assert {:ok, "SOMETHING_NEW"} = Plugin.InstallPolicy.parse("SOMETHING_NEW")
    assert {:ok, "LATER"} = Plugin.AuthPolicy.parse("LATER")

    assert "AVAILABLE" == Plugin.InstallPolicy.to_wire(:available)
    assert "ON_INSTALL" == Plugin.AuthPolicy.to_wire(:on_install)
    assert "SOMETHING_NEW" == Plugin.InstallPolicy.to_wire("SOMETHING_NEW")
    assert "LATER" == Plugin.AuthPolicy.to_wire("LATER")
  end

  test "invalid typed responses return adapted parse errors" do
    assert {:error, {:invalid_plugin_list_response, details}} =
             Plugin.ListResponse.parse(%{"marketplaces" => "bad"})

    assert is_binary(details.message)
    assert is_map(details.errors)
    assert is_list(details.issues)
  end

  test "nested invalid typed responses return adapted outer parse errors" do
    payload = %{
      "marketplaces" => [
        %{
          "name" => "codex-curated",
          "path" => "/tmp/marketplace.json",
          "plugins" => [
            %{
              "id" => "demo-plugin@codex-curated",
              "name" => "demo-plugin",
              "source" => %{"type" => "local", "path" => "/tmp/plugins/demo-plugin"},
              "installed" => "yes",
              "enabled" => true,
              "installPolicy" => "AVAILABLE",
              "authPolicy" => "ON_INSTALL"
            }
          ]
        }
      ]
    }

    assert {:error, {:invalid_plugin_list_response, details}} =
             Plugin.ListResponse.parse(payload)

    assert is_binary(details.message)
    assert is_map(details.errors)
    assert is_list(details.issues)
  end
end

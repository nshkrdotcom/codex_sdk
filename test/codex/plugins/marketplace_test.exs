defmodule Codex.Plugins.MarketplaceTest do
  use ExUnit.Case, async: true

  alias Codex.Plugins
  alias Codex.Plugins.Marketplace

  test "minimal valid marketplace parses nested policy fields and preserves unknown fields" do
    payload = %{
      "name" => "repo-marketplace",
      "interface" => %{"displayName" => "Repo Plugins", "theme" => "blue"},
      "plugins" => [
        %{
          "name" => "demo-plugin",
          "source" => %{
            "source" => "local",
            "path" => "./plugins/demo-plugin",
            "futureSourceField" => "kept"
          },
          "policy" => %{
            "installation" => "AVAILABLE",
            "authentication" => "ON_INSTALL",
            "products" => ["CODEx", "CHATGPT"],
            "futurePolicyField" => true
          },
          "category" => "Productivity",
          "futurePluginField" => 1
        }
      ],
      "futureMarketplaceField" => "kept"
    }

    assert {:ok,
            %Marketplace{
              name: "repo-marketplace",
              extra: %{"futureMarketplaceField" => "kept"},
              interface: %{display_name: "Repo Plugins", extra: %{"theme" => "blue"}},
              plugins: [
                %{
                  name: "demo-plugin",
                  category: "Productivity",
                  extra: %{"futurePluginField" => 1},
                  source: %{
                    source: :local,
                    path: "./plugins/demo-plugin",
                    extra: %{"futureSourceField" => "kept"}
                  },
                  policy: %{
                    installation: :available,
                    authentication: :on_install,
                    products: ["CODEx", "CHATGPT"],
                    extra: %{"futurePolicyField" => true}
                  }
                }
              ]
            }} = Marketplace.parse(payload)

    assert %{
             "name" => "repo-marketplace",
             "futureMarketplaceField" => "kept",
             "interface" => %{"displayName" => "Repo Plugins", "theme" => "blue"},
             "plugins" => [
               %{
                 "name" => "demo-plugin",
                 "category" => "Productivity",
                 "futurePluginField" => 1,
                 "source" => %{
                   "source" => "local",
                   "path" => "./plugins/demo-plugin",
                   "futureSourceField" => "kept"
                 },
                 "policy" => %{
                   "installation" => "AVAILABLE",
                   "authentication" => "ON_INSTALL",
                   "products" => ["CODEx", "CHATGPT"],
                   "futurePolicyField" => true
                 }
               }
             ]
           } = Marketplace.to_map(Marketplace.from_map(payload))
  end

  test "legacy top-level installPolicy and authPolicy do not pass as canonical output" do
    payload = %{
      "name" => "repo-marketplace",
      "plugins" => [
        %{
          "name" => "demo-plugin",
          "source" => %{"source" => "local", "path" => "./plugins/demo-plugin"},
          "installPolicy" => "AVAILABLE",
          "authPolicy" => "ON_INSTALL",
          "category" => "Productivity"
        }
      ]
    }

    assert {:error, {:invalid_plugin_marketplace, details}} = Marketplace.parse(payload)
    assert Enum.any?(details.issues, &(&1.path == ["plugins", 0, "policy"]))
  end

  test "marketplace source paths must stay inside the marketplace root" do
    temp_root = temp_root("marketplace_containment")
    marketplace_path = Path.join([temp_root, "repo", ".agents", "plugins", "marketplace.json"])

    File.mkdir_p!(Path.dirname(marketplace_path))

    File.write!(
      marketplace_path,
      """
      {
        "name": "repo-marketplace",
        "plugins": [
          {
            "name": "escape-plugin",
            "source": {
              "source": "local",
              "path": "./../outside"
            },
            "policy": {
              "installation": "AVAILABLE",
              "authentication": "ON_INSTALL"
            },
            "category": "Productivity"
          }
        ]
      }
      """
    )

    assert {:error,
            {:invalid_marketplace_source_path,
             %{source_path: "./../outside", path: ^marketplace_path}}} =
             Plugins.read_marketplace(marketplace_path)
  end

  test "marketplace source paths reject traversal segments even when they remain under the root" do
    temp_root = temp_root("marketplace_traversal")
    marketplace_path = Path.join([temp_root, "repo", ".agents", "plugins", "marketplace.json"])

    File.mkdir_p!(Path.dirname(marketplace_path))

    File.write!(
      marketplace_path,
      """
      {
        "name": "repo-marketplace",
        "plugins": [
          {
            "name": "demo-plugin",
            "source": {
              "source": "local",
              "path": "./plugins/demo-plugin/../other-plugin"
            },
            "policy": {
              "installation": "AVAILABLE",
              "authentication": "ON_INSTALL"
            },
            "category": "Productivity"
          }
        ]
      }
      """
    )

    assert {:error,
            {:invalid_marketplace_source_path,
             %{source_path: "./plugins/demo-plugin/../other-plugin", path: ^marketplace_path}}} =
             Plugins.read_marketplace(marketplace_path)
  end

  defp temp_root(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
  end
end

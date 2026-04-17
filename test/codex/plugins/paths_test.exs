defmodule Codex.Plugins.PathsTest do
  use ExUnit.Case, async: true

  alias Codex.Plugins
  alias Codex.Plugins.Paths
  alias Codex.TestSupport.TempDir

  test "repo and personal scopes resolve the correct roots and canonical file paths" do
    temp_root =
      TempDir.create!("plugin_paths")
      |> tap(&on_exit(fn -> File.rm_rf!(&1) end))

    repo_root = Path.join(temp_root, "repo")
    nested = Path.join(repo_root, "apps/demo")
    home_root = Path.join(temp_root, "home")

    File.mkdir_p!(Path.join(repo_root, ".git"))
    File.mkdir_p!(nested)
    File.mkdir_p!(home_root)

    assert {:ok, ^repo_root} = Paths.scope_root(:repo, cwd: nested)
    expected_repo_plugin_root = Path.join(repo_root, "plugins/demo-plugin")
    expected_repo_marketplace_path = Path.join(repo_root, ".agents/plugins/marketplace.json")
    expected_personal_plugin_root = Path.join(home_root, "plugins/demo-plugin")
    expected_personal_marketplace_path = Path.join(home_root, ".agents/plugins/marketplace.json")

    assert {:ok, ^expected_repo_plugin_root} =
             Paths.plugin_root(:repo, "demo-plugin", cwd: nested)

    assert {:ok, ^expected_repo_marketplace_path} =
             Paths.marketplace_path(:repo, cwd: nested)

    assert {:ok, ^home_root} = Paths.scope_root(:personal, home: home_root)

    assert {:ok, ^expected_personal_plugin_root} =
             Paths.plugin_root(:personal, "demo-plugin", home: home_root)

    assert {:ok, ^expected_personal_marketplace_path} =
             Paths.marketplace_path(:personal, home: home_root)
  end

  test "alternate claude-compatible manifest and marketplace paths are discoverable" do
    temp_root =
      TempDir.create!("plugin_paths_alternate")
      |> tap(&on_exit(fn -> File.rm_rf!(&1) end))

    plugin_root = Path.join(temp_root, "plugins/demo-plugin")
    manifest_path = Path.join(plugin_root, ".claude-plugin/plugin.json")
    marketplace_path = Path.join(temp_root, ".claude-plugin/marketplace.json")

    File.mkdir_p!(Path.dirname(manifest_path))
    File.mkdir_p!(Path.dirname(marketplace_path))

    File.write!(
      manifest_path,
      """
      {
        "name": "demo-plugin"
      }
      """
    )

    File.write!(
      marketplace_path,
      """
      {
        "name": "claude-marketplace",
        "plugins": [
          {
            "name": "demo-plugin",
            "source": {
              "source": "local",
              "path": "./plugins/demo-plugin"
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

    assert Paths.manifest_path(plugin_root) == Path.expand(manifest_path)
    assert Paths.manifest_path(manifest_path) == Path.expand(manifest_path)
    assert {:ok, ^temp_root} = Paths.marketplace_root(marketplace_path)
    assert {:ok, manifest} = Plugins.read_manifest(manifest_path)
    assert manifest.name == "demo-plugin"
    assert {:ok, marketplace} = Plugins.read_marketplace(marketplace_path)
    assert Enum.map(marketplace.plugins, & &1.name) == ["demo-plugin"]
  end
end

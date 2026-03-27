defmodule Codex.Plugins.WriterTest do
  use ExUnit.Case, async: true

  alias Codex.Plugins

  test "manifest writes are deterministic, pretty, and newline terminated" do
    temp_root = temp_root("plugin_writer_manifest")
    manifest_path = Path.join([temp_root, "demo-plugin", ".codex-plugin", "plugin.json"])

    {:ok, manifest} =
      Plugins.new_manifest(
        name: "demo-plugin",
        description: "Demo plugin",
        skills: "./skills/",
        interface: [display_name: "Demo Plugin", composer_icon: "./assets/icon.png"]
      )

    assert :ok = Plugins.write_manifest(manifest_path, manifest, create_parents: true)
    first = File.read!(manifest_path)

    assert :ok = Plugins.write_manifest(manifest_path, manifest, overwrite: true)
    second = File.read!(manifest_path)

    assert first == second
    assert String.ends_with?(first, "\n")
    assert String.contains?(first, "\n  \"")
  end

  test "overwrite protection prevents silent clobbering" do
    temp_root = temp_root("plugin_writer_overwrite")
    manifest_path = Path.join([temp_root, "demo-plugin", ".codex-plugin", "plugin.json"])

    File.mkdir_p!(Path.dirname(manifest_path))
    File.write!(manifest_path, "{}\n")

    {:ok, manifest} = Plugins.new_manifest(name: "demo-plugin")

    assert {:error, {:plugin_file_exists, %{path: ^manifest_path}}} =
             Plugins.write_manifest(manifest_path, manifest)
  end

  test "marketplace updates merge new plugins without erasing unrelated entries" do
    temp_root = temp_root("plugin_writer_marketplace")
    repo_root = Path.join(temp_root, "repo")
    marketplace_path = Path.join(repo_root, ".agents/plugins/marketplace.json")

    File.mkdir_p!(Path.dirname(marketplace_path))

    File.write!(
      marketplace_path,
      """
      {
        "name": "repo-marketplace",
        "futureRootField": true,
        "plugins": [
          {
            "name": "alpha",
            "source": {
              "source": "local",
              "path": "./plugins/alpha"
            },
            "policy": {
              "installation": "AVAILABLE",
              "authentication": "ON_INSTALL"
            },
            "category": "Productivity",
            "futurePluginField": "kept"
          }
        ]
      }
      """
    )

    assert {:ok, _metadata} =
             Plugins.add_marketplace_plugin(
               marketplace_path,
               name: "beta",
               source: [source: :local, path: "./plugins/beta"],
               policy: [installation: :available, authentication: :on_install],
               category: "Productivity"
             )

    assert {:ok, marketplace} = Plugins.read_marketplace(marketplace_path)
    assert marketplace.extra["futureRootField"] == true
    assert Enum.map(marketplace.plugins, & &1.name) == ["alpha", "beta"]

    alpha = Enum.find(marketplace.plugins, &(&1.name == "alpha"))
    assert alpha.extra["futurePluginField"] == "kept"
  end

  defp temp_root(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
  end
end

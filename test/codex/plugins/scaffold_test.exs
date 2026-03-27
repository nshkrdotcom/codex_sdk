defmodule Codex.Plugins.ScaffoldTest do
  use ExUnit.Case, async: true

  alias Codex.Plugins

  test "repo-scope scaffold creates the minimal plugin tree and optional marketplace entry" do
    temp_root = temp_root("plugin_scaffold_repo")
    repo_root = Path.join(temp_root, "repo")

    File.mkdir_p!(Path.join(repo_root, ".git"))

    assert {:ok, result} =
             Plugins.scaffold(
               cwd: repo_root,
               plugin_name: "demo-plugin",
               with_marketplace: true,
               skill: [name: "hello-world", description: "Greets the user"]
             )

    assert result.plugin_root == Path.join(repo_root, "plugins/demo-plugin")

    assert result.manifest_path ==
             Path.join(repo_root, "plugins/demo-plugin/.codex-plugin/plugin.json")

    assert result.marketplace_path == Path.join(repo_root, ".agents/plugins/marketplace.json")

    assert File.regular?(result.manifest_path)
    assert File.regular?(Path.join(result.plugin_root, "skills/hello-world/SKILL.md"))
    assert File.regular?(result.marketplace_path)
    refute File.exists?(Path.join(result.plugin_root, "mix.exs"))
    refute File.exists?(Path.join(result.plugin_root, ".formatter.exs"))
    refute File.exists?(Path.join(result.plugin_root, "build_support"))

    assert {:ok, manifest} = Plugins.read_manifest(result.manifest_path)
    assert manifest.name == "demo-plugin"
    assert manifest.skills == "./skills"

    assert {:ok, marketplace} = Plugins.read_marketplace(result.marketplace_path)
    assert Enum.map(marketplace.plugins, & &1.name) == ["demo-plugin"]
    assert hd(marketplace.plugins).source.path == "./plugins/demo-plugin"
  end

  test "personal-scope scaffold resolves to the home-local plugin and marketplace roots" do
    temp_root = temp_root("plugin_scaffold_personal")
    home_root = Path.join(temp_root, "home")
    File.mkdir_p!(home_root)

    assert {:ok, result} =
             Plugins.scaffold(
               scope: :personal,
               home: home_root,
               plugin_name: "personal-plugin",
               with_marketplace: true
             )

    assert result.plugin_root == Path.join(home_root, "plugins/personal-plugin")
    assert result.marketplace_path == Path.join(home_root, ".agents/plugins/marketplace.json")
    assert File.regular?(result.manifest_path)
    assert File.regular?(result.marketplace_path)
  end

  defp temp_root(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
  end
end

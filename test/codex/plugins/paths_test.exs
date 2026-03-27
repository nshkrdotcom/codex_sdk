defmodule Codex.Plugins.PathsTest do
  use ExUnit.Case, async: true

  alias Codex.Plugins.Paths

  test "repo and personal scopes resolve the correct roots and canonical file paths" do
    temp_root = temp_root("plugin_paths")
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

  defp temp_root(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
  end
end

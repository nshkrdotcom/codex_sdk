defmodule Codex.Config.LayerStackTest do
  use ExUnit.Case, async: false

  alias Codex.Config.LayerStack

  setup do
    tmp_root =
      Path.join(System.tmp_dir!(), "codex_layer_stack_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_root)

    original_system_path = Application.get_env(:codex_sdk, :system_config_path)
    system_path = Path.join(tmp_root, "system/config.toml")
    Application.put_env(:codex_sdk, :system_config_path, system_path)

    on_exit(fn ->
      case original_system_path do
        nil -> Application.delete_env(:codex_sdk, :system_config_path)
        value -> Application.put_env(:codex_sdk, :system_config_path, value)
      end

      File.rm_rf(tmp_root)
    end)

    {:ok, tmp_root: tmp_root, system_path: system_path}
  end

  test "loads system config and sibling requirements", %{
    tmp_root: tmp_root,
    system_path: system_path
  } do
    codex_home = Path.join(tmp_root, "home")
    cwd = Path.join(tmp_root, "workspace")
    File.mkdir_p!(codex_home)
    File.mkdir_p!(cwd)

    write_config!(system_path, """
    [features]
    remote_models = true
    """)

    write_config!(Path.join(Path.dirname(system_path), "requirements.toml"), """
    allowed_approval_policies = ["granular"]

    [network]
    disabled = true
    """)

    assert {:ok, layers} = LayerStack.load(codex_home, cwd)
    config = LayerStack.effective_config(layers)

    assert get_in(config, ["features", "remote_models"]) == true
    assert get_in(config, ["requirements", "allowed_approval_policies"]) == ["granular"]
    assert get_in(config, ["requirements", "network", "disabled"]) == true
  end

  test "trusted project layers override user config and repo .codex beats cwd config", %{
    tmp_root: tmp_root
  } do
    codex_home = Path.join(tmp_root, "home")
    project = Path.join(tmp_root, "workspace/project")
    cwd = Path.join(project, "apps/mobile")
    File.mkdir_p!(codex_home)
    File.mkdir_p!(cwd)
    File.mkdir_p!(Path.join(project, ".git"))
    File.mkdir_p!(Path.join(project, ".codex"))

    trusted_project = Path.expand(project)

    write_config!(Path.join(codex_home, "config.toml"), """
    model = "user-model"

    [projects."#{trusted_project}"]
    trust_level = "trusted"
    """)

    write_config!(Path.join(cwd, "config.toml"), """
    model = "cwd-model"
    allow_login_shell = false
    """)

    write_config!(Path.join(project, ".codex/config.toml"), """
    model = "repo-model"

    [apps]
    disable = true
    """)

    assert {:ok, layers} = LayerStack.load(codex_home, cwd)
    config = LayerStack.effective_config(layers)

    assert config["model"] == "repo-model"
    assert config["allow_login_shell"] == false
    assert get_in(config, ["apps", "disable"]) == true
    assert Enum.any?(layers, &(&1.path == Path.join(cwd, "config.toml") and &1.enabled))

    assert Enum.any?(
             layers,
             &(&1.path == Path.join(project, ".codex/config.toml") and &1.enabled)
           )
  end

  test "missing trust disables cwd and project layers", %{tmp_root: tmp_root} do
    codex_home = Path.join(tmp_root, "home")
    project = Path.join(tmp_root, "workspace/project")
    cwd = Path.join(project, "apps/mobile")
    File.mkdir_p!(codex_home)
    File.mkdir_p!(cwd)
    File.mkdir_p!(Path.join(project, ".git"))
    File.mkdir_p!(Path.join(project, ".codex"))

    write_config!(Path.join(codex_home, "config.toml"), """
    model = "user-model"
    """)

    write_config!(Path.join(cwd, "config.toml"), """
    model = "cwd-model"
    """)

    write_config!(Path.join(project, ".codex/config.toml"), """
    [features]
    remote_models = true
    """)

    assert {:ok, layers} = LayerStack.load(codex_home, cwd)
    config = LayerStack.effective_config(layers)

    assert config["model"] == "user-model"
    assert get_in(config, ["features", "remote_models"]) != true

    assert Enum.any?(
             layers,
             &(String.ends_with?(&1.path, "/config.toml") and &1.enabled == false)
           )
  end

  test "project_root_markers empty limits discovery to cwd", %{tmp_root: tmp_root} do
    codex_home = Path.join(tmp_root, "home")
    parent = Path.join(tmp_root, "workspace/parent")
    child = Path.join(parent, "child")
    File.mkdir_p!(codex_home)
    File.mkdir_p!(child)
    File.mkdir_p!(Path.join(parent, ".git"))
    File.mkdir_p!(Path.join(parent, ".codex"))

    write_config!(Path.join(codex_home, "config.toml"), """
    project_root_markers = []

    [projects."#{Path.expand(child)}"]
    trust_level = "trusted"
    """)

    write_config!(Path.join(parent, ".codex/config.toml"), """
    [features]
    remote_models = true
    """)

    assert {:ok, layers} = LayerStack.load(codex_home, child)
    config = LayerStack.effective_config(layers)

    refute get_in(config, ["features", "remote_models"])
  end

  test "parses allow_login_shell, apps, memories, and shell environment policy", %{
    tmp_root: tmp_root
  } do
    codex_home = Path.join(tmp_root, "home")
    File.mkdir_p!(codex_home)

    write_config!(Path.join(codex_home, "config.toml"), """
    allow_login_shell = false

    [apps]
    disable = true

    [memories]
    disable = true

    [shell_environment_policy]
    inherit = "core"
    ignore_default_excludes = false
    exclude = ["AWS_*"]
    include_only = ["PATH"]
    set = { FOO = "bar" }
    """)

    assert {:ok, layers} = LayerStack.load(codex_home, nil)
    config = LayerStack.effective_config(layers)

    assert config["allow_login_shell"] == false
    assert get_in(config, ["apps", "disable"]) == true
    assert get_in(config, ["memories", "disable"]) == true
    assert get_in(config, ["shell_environment_policy", "inherit"]) == "core"
    assert get_in(config, ["shell_environment_policy", "ignore_default_excludes"]) == false
    assert get_in(config, ["shell_environment_policy", "exclude"]) == ["AWS_*"]
    assert get_in(config, ["shell_environment_policy", "include_only"]) == ["PATH"]
    assert get_in(config, ["shell_environment_policy", "set"]) == %{"FOO" => "bar"}
  end

  defp write_config!(path, contents) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, contents)
  end
end

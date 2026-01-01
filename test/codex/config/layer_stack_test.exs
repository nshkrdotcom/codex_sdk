defmodule Codex.Config.LayerStackTest do
  use ExUnit.Case, async: false

  alias Codex.Config.LayerStack

  setup do
    tmp_root =
      Path.join(System.tmp_dir!(), "codex_layer_stack_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_root)

    original_system_path = Application.get_env(:codex_sdk, :system_config_path)
    system_path = Path.join(tmp_root, "system_config.toml")
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

  test "uses system config for remote models when present", %{
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

    assert LayerStack.remote_models_enabled?(codex_home, cwd) == true
  end

  test "project layer overrides user config", %{tmp_root: tmp_root} do
    codex_home = Path.join(tmp_root, "home")
    workspace = Path.join(tmp_root, "workspace")
    project = Path.join(workspace, "project")
    File.mkdir_p!(codex_home)
    File.mkdir_p!(project)
    File.mkdir_p!(Path.join(project, ".git"))

    write_config!(Path.join(codex_home, "config.toml"), """
    [features]
    remote_models = false
    """)

    project_codex = Path.join(project, ".codex")
    File.mkdir_p!(project_codex)

    write_config!(Path.join(project_codex, "config.toml"), """
    [features]
    remote_models = true
    """)

    assert LayerStack.remote_models_enabled?(codex_home, project) == true
  end

  test "project_root_markers empty disables parent discovery", %{tmp_root: tmp_root} do
    codex_home = Path.join(tmp_root, "home")
    workspace = Path.join(tmp_root, "workspace")
    parent = Path.join(workspace, "parent")
    child = Path.join(parent, "child")
    File.mkdir_p!(codex_home)
    File.mkdir_p!(child)
    File.mkdir_p!(Path.join(parent, ".git"))

    write_config!(Path.join(codex_home, "config.toml"), """
    project_root_markers = []
    """)

    parent_codex = Path.join(parent, ".codex")
    File.mkdir_p!(parent_codex)

    write_config!(Path.join(parent_codex, "config.toml"), """
    [features]
    remote_models = true
    """)

    child_codex = Path.join(child, ".codex")
    File.mkdir_p!(child_codex)

    write_config!(Path.join(child_codex, "config.toml"), """
    [features]
    remote_models = false
    """)

    assert LayerStack.remote_models_enabled?(codex_home, child) == false
  end

  test "parses history and shell environment policy config", %{tmp_root: tmp_root} do
    codex_home = Path.join(tmp_root, "home")
    File.mkdir_p!(codex_home)

    write_config!(Path.join(codex_home, "config.toml"), """
    [history]
    persistence = "none"
    max_bytes = 12345

    [shell_environment_policy]
    inherit = "core"
    ignore_default_excludes = false
    exclude = ["AWS_*"]
    include_only = ["PATH"]
    set = { FOO = "bar" }
    """)

    assert {:ok, layers} = LayerStack.load(codex_home, nil)

    config = LayerStack.effective_config(layers)

    assert get_in(config, ["history", "persistence"]) == "none"
    assert get_in(config, ["history", "max_bytes"]) == 12_345
    assert get_in(config, ["shell_environment_policy", "inherit"]) == "core"
    assert get_in(config, ["shell_environment_policy", "ignore_default_excludes"]) == false
    assert get_in(config, ["shell_environment_policy", "exclude"]) == ["AWS_*"]
    assert get_in(config, ["shell_environment_policy", "include_only"]) == ["PATH"]
    assert get_in(config, ["shell_environment_policy", "set"]) == %{"FOO" => "bar"}
  end

  test "parses dotted core keys and model provider", %{tmp_root: tmp_root} do
    codex_home = Path.join(tmp_root, "home")
    File.mkdir_p!(codex_home)

    write_config!(Path.join(codex_home, "config.toml"), """
    model_provider = "mistral"
    features.remote_models = true
    history.persistence = "local"
    history.max_bytes = 2048
    shell_environment_policy.inherit = "none"
    shell_environment_policy.exclude = ["AWS_*"]
    """)

    assert {:ok, layers} = LayerStack.load(codex_home, nil)

    config = LayerStack.effective_config(layers)

    assert config["model_provider"] == "mistral"
    assert get_in(config, ["features", "remote_models"]) == true
    assert get_in(config, ["history", "persistence"]) == "local"
    assert get_in(config, ["history", "max_bytes"]) == 2048
    assert get_in(config, ["shell_environment_policy", "inherit"]) == "none"
    assert get_in(config, ["shell_environment_policy", "exclude"]) == ["AWS_*"]
  end

  test "rejects invalid cli_auth_credentials_store values", %{tmp_root: tmp_root} do
    codex_home = Path.join(tmp_root, "home")
    File.mkdir_p!(codex_home)

    write_config!(Path.join(codex_home, "config.toml"), """
    cli_auth_credentials_store = "unsupported"
    """)

    assert {:error, {:invalid_toml, _path, {:invalid_cli_auth_credentials_store, "unsupported"}}} =
             LayerStack.load(codex_home, nil)
  end

  defp write_config!(path, contents) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, contents)
  end
end

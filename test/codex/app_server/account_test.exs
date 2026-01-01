defmodule Codex.AppServer.AccountTest do
  use ExUnit.Case, async: false

  alias Codex.AppServer.Account

  setup do
    tmp_root =
      Path.join(System.tmp_dir!(), "codex_account_#{System.unique_integer([:positive])}")

    codex_home = Path.join(tmp_root, "home")
    system_path = Path.join(tmp_root, "system_config.toml")

    File.mkdir_p!(codex_home)

    original_home = System.get_env("CODEX_HOME")
    original_system_path = Application.get_env(:codex_sdk, :system_config_path)

    System.put_env("CODEX_HOME", codex_home)
    Application.put_env(:codex_sdk, :system_config_path, system_path)

    on_exit(fn ->
      case original_home do
        nil -> System.delete_env("CODEX_HOME")
        value -> System.put_env("CODEX_HOME", value)
      end

      case original_system_path do
        nil -> Application.delete_env(:codex_sdk, :system_config_path)
        value -> Application.put_env(:codex_sdk, :system_config_path, value)
      end

      File.rm_rf(tmp_root)
    end)

    {:ok, codex_home: codex_home}
  end

  test "rejects login when forced method mismatches", %{codex_home: codex_home} do
    File.write!(Path.join(codex_home, "config.toml"), """
    forced_login_method = "chatgpt"
    """)

    assert {:error, {:forced_login_method, "chatgpt", :api_key}} =
             Account.login_start(self(), {:api_key, "sk-test"})
  end

  test "rejects chatgpt workspace mismatch", %{codex_home: codex_home} do
    File.write!(Path.join(codex_home, "config.toml"), """
    forced_login_method = "chatgpt"
    forced_chatgpt_workspace_id = "workspace-1"
    """)

    assert {:error, {:forced_chatgpt_workspace_id, "workspace-1", "workspace-2"}} =
             Account.login_start(self(), %{
               "type" => "chatgpt",
               "workspaceId" => "workspace-2"
             })
  end
end

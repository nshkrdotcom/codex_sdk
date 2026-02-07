defmodule Codex.AuthTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Codex.Auth

  setup do
    tmp_root =
      Path.join(System.tmp_dir!(), "codex_auth_#{System.unique_integer([:positive])}")

    codex_home = Path.join(tmp_root, "home")
    system_path = Path.join(tmp_root, "system_config.toml")

    File.mkdir_p!(codex_home)

    original_home = System.get_env("CODEX_HOME")
    original_api_key = System.get_env("CODEX_API_KEY")
    original_openai_api_key = System.get_env("OPENAI_API_KEY")
    original_system_path = Application.get_env(:codex_sdk, :system_config_path)

    System.put_env("CODEX_HOME", codex_home)
    System.delete_env("CODEX_API_KEY")
    System.delete_env("OPENAI_API_KEY")
    Application.put_env(:codex_sdk, :system_config_path, system_path)

    :persistent_term.erase({Codex.Auth, :keyring_warning_emitted})

    on_exit(fn ->
      case original_home do
        nil -> System.delete_env("CODEX_HOME")
        value -> System.put_env("CODEX_HOME", value)
      end

      case original_api_key do
        nil -> System.delete_env("CODEX_API_KEY")
        value -> System.put_env("CODEX_API_KEY", value)
      end

      case original_openai_api_key do
        nil -> System.delete_env("OPENAI_API_KEY")
        value -> System.put_env("OPENAI_API_KEY", value)
      end

      case original_system_path do
        nil -> Application.delete_env(:codex_sdk, :system_config_path)
        value -> Application.put_env(:codex_sdk, :system_config_path, value)
      end

      File.rm_rf(tmp_root)
    end)

    {:ok, codex_home: codex_home}
  end

  test "warns and ignores api key files when keyring is configured", %{codex_home: codex_home} do
    File.write!(Path.join(codex_home, "config.toml"), """
    cli_auth_credentials_store = "keyring"
    """)

    File.write!(Path.join(codex_home, "auth.json"), ~s({"OPENAI_API_KEY":"sk-test"}))

    log =
      capture_log(fn ->
        assert Auth.api_key() == nil
      end)

    assert log =~ "keyring auth"
  end

  test "warns and ignores chatgpt tokens when keyring is configured", %{codex_home: codex_home} do
    File.write!(Path.join(codex_home, "config.toml"), """
    cli_auth_credentials_store = "keyring"
    """)

    File.write!(Path.join(codex_home, "auth.json"), ~s({"tokens":{"access_token":"token"}}))

    log =
      capture_log(fn ->
        assert Auth.chatgpt_access_token() == nil
      end)

    assert log =~ "keyring auth"
  end

  test "direct_api_key/0 falls back to OPENAI_API_KEY when Codex key sources are absent" do
    System.put_env("OPENAI_API_KEY", "sk-openai-env")
    assert Auth.api_key() == nil
    assert Auth.direct_api_key() == "sk-openai-env"
  end

  test "direct_api_key/0 preserves Codex precedence over OPENAI_API_KEY", %{
    codex_home: codex_home
  } do
    System.put_env("CODEX_API_KEY", "sk-codex-priority")
    System.put_env("OPENAI_API_KEY", "sk-openai-secondary")
    File.write!(Path.join(codex_home, "auth.json"), ~s({"OPENAI_API_KEY":"sk-auth-file"}))

    assert Auth.api_key() == "sk-codex-priority"
    assert Auth.direct_api_key() == "sk-codex-priority"
  end
end

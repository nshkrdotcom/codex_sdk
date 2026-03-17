defmodule Codex.AuthTest do
  use ExUnit.Case, async: false
  use Codex.TestSupport.AuthEnv

  import ExUnit.CaptureLog

  alias Codex.Auth

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

  test "chatgpt auth_mode prevents stale auth file api keys from overriding chatgpt mode", %{
    codex_home: codex_home
  } do
    File.write!(
      Path.join(codex_home, "auth.json"),
      Jason.encode!(%{
        "auth_mode" => "chatgpt",
        "OPENAI_API_KEY" => "sk-stale",
        "tokens" => %{"access_token" => "chatgpt-token"}
      })
    )

    assert Auth.infer_auth_mode() == :chatgpt
    assert Auth.api_key() == nil
    assert Auth.chatgpt_access_token() == "chatgpt-token"
  end
end

defmodule Codex.OAuth.ContextTest do
  use ExUnit.Case, async: false

  alias Codex.OAuth.Context
  alias Codex.TestSupport.GovernedAuthority

  setup do
    tmp_root =
      Path.join(System.tmp_dir!(), "codex_oauth_context_#{System.unique_integer([:positive])}")

    child_home = Path.join(tmp_root, "child-home")
    cwd = Path.join(tmp_root, "workspace")
    File.mkdir_p!(child_home)
    File.mkdir_p!(cwd)

    File.write!(
      Path.join(child_home, "config.toml"),
      """
      openai_base_url = "https://config.example.com/v1"
      auth_issuer = "https://issuer.example.com"
      cli_auth_credentials_store = "file"
      """
    )

    on_exit(fn -> File.rm_rf(tmp_root) end)

    {:ok, tmp_root: tmp_root, child_home: child_home, cwd: cwd}
  end

  test "resolve/1 honors child cwd and process_env when deriving oauth context", %{
    child_home: child_home,
    cwd: cwd
  } do
    context =
      Context.resolve!(
        cwd: cwd,
        process_env: %{
          "CODEX_HOME" => child_home,
          "CODEX_CA_CERTIFICATE" => "/tmp/oauth-ca.pem",
          "OPENAI_BASE_URL" => "https://env.example.com/v1"
        },
        interactive?: false,
        os: :linux
      )

    assert context.cwd == cwd
    assert context.codex_home == child_home
    assert context.child_process_env["CODEX_HOME"] == child_home
    assert context.api_base_url == "https://config.example.com/v1"
    assert context.auth_issuer == "https://issuer.example.com"
    assert context.ca_bundle_path == "/tmp/oauth-ca.pem"
    assert context.credentials_store_mode == :file
    refute context.interactive?
  end

  test "resolve/1 rejects ambient CODEX_HOME as governed OAuth authority", %{
    child_home: child_home
  } do
    previous = System.get_env("CODEX_HOME")
    System.put_env("CODEX_HOME", child_home)

    on_exit(fn ->
      case previous do
        nil -> System.delete_env("CODEX_HOME")
        value -> System.put_env("CODEX_HOME", value)
      end
    end)

    assert {:error, {:unmanaged_governed_env, "CODEX_HOME"}} =
             Context.resolve(governed_authority: GovernedAuthority.refs(), interactive?: false)
  end

  test "resolve/1 accepts governed OAuth context from materialized child env only", %{
    child_home: child_home,
    cwd: cwd
  } do
    GovernedAuthority.with_clean_ambient(fn ->
      assert {:ok, context} =
               Context.resolve(
                 governed_authority: GovernedAuthority.refs(),
                 cwd: cwd,
                 process_env: %{
                   "CODEX_HOME" => child_home,
                   "CODEX_CA_CERTIFICATE" => "/tmp/oauth-ca.pem",
                   "OPENAI_BASE_URL" => "https://env.example.com/v1"
                 },
                 interactive?: false,
                 os: :linux
               )

      assert context.codex_home == child_home
      assert context.child_process_env["CODEX_HOME"] == child_home
      assert context.child_process_env["OPENAI_BASE_URL"] == "https://env.example.com/v1"
      assert context.api_base_url == "https://config.example.com/v1"
      refute Map.has_key?(context.child_process_env, "OPENAI_API_KEY")
    end)
  end
end

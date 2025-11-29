defmodule Codex.OptionsTest do
  use ExUnit.Case, async: true

  alias Codex.Options

  describe "new/1" do
    test "builds options from map" do
      {:ok, opts} =
        Options.new(%{
          api_key: "test",
          base_url: "https://example.com",
          telemetry_prefix: [:codex, :test]
        })

      assert opts.api_key == "test"
      assert opts.base_url == "https://example.com"
      assert opts.telemetry_prefix == [:codex, :test]
    end

    test "allows API key to be omitted" do
      assert {:ok, opts} = Options.new(%{})
      assert opts.api_key == nil
      assert opts.model == nil
    end

    test "loads API key from CLI auth file when env is absent" do
      tmp_home = Path.join(System.tmp_dir!(), "codex_home_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_home)

      auth_path = Path.join(tmp_home, "auth.json")
      File.write!(auth_path, ~s({"tokens":{"access_token":"cli_token"}}))

      original_env = System.get_env("CODEX_HOME")
      System.put_env("CODEX_HOME", tmp_home)
      System.delete_env("CODEX_API_KEY")

      on_exit(fn ->
        if original_env,
          do: System.put_env("CODEX_HOME", original_env),
          else: System.delete_env("CODEX_HOME")

        System.delete_env("CODEX_API_KEY")
        File.rm_rf(tmp_home)
      end)

      assert {:ok, opts} = Options.new(%{})
      assert opts.api_key == "cli_token"
    end
  end
end

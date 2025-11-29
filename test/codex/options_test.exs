defmodule Codex.OptionsTest do
  use ExUnit.Case, async: true

  alias Codex.Options

  setup do
    original_model = System.get_env("CODEX_MODEL")
    original_default = System.get_env("CODEX_MODEL_DEFAULT")

    System.delete_env("CODEX_MODEL")
    System.delete_env("CODEX_MODEL_DEFAULT")

    on_exit(fn ->
      case original_model do
        nil -> System.delete_env("CODEX_MODEL")
        value -> System.put_env("CODEX_MODEL", value)
      end

      case original_default do
        nil -> System.delete_env("CODEX_MODEL_DEFAULT")
        value -> System.put_env("CODEX_MODEL_DEFAULT", value)
      end
    end)

    :ok
  end

  describe "new/1" do
    test "builds options from map" do
      {:ok, opts} =
        Options.new(%{
          api_key: "test",
          base_url: "https://example.com",
          telemetry_prefix: [:codex, :test],
          reasoning_effort: :high
        })

      assert opts.api_key == "test"
      assert opts.base_url == "https://example.com"
      assert opts.telemetry_prefix == [:codex, :test]
      assert opts.model == "gpt-5.1-codex-max"
      assert opts.reasoning_effort == :high
    end

    test "allows API key to be omitted" do
      assert {:ok, opts} = Options.new(%{})
      assert opts.api_key == nil
      assert opts.model == "gpt-5.1-codex-max"
      assert opts.reasoning_effort == :medium
    end

    test "falls back to model-specific reasoning defaults" do
      {:ok, opts} = Options.new(%{model: "gpt-5.1-codex-mini"})

      assert opts.model == "gpt-5.1-codex-mini"
      assert opts.reasoning_effort == :medium
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

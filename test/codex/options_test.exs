defmodule Codex.OptionsTest do
  use ExUnit.Case, async: false

  alias Codex.Options

  setup do
    env_keys = ~w(CODEX_MODEL CODEX_MODEL_DEFAULT CODEX_API_KEY CODEX_HOME)

    original_env =
      env_keys
      |> Enum.map(&{&1, System.get_env(&1)})
      |> Map.new()

    Enum.each(env_keys, &System.delete_env/1)

    tmp_home = Path.join(System.tmp_dir!(), "codex_home_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_home)
    System.put_env("CODEX_HOME", tmp_home)

    on_exit(fn ->
      Enum.each(env_keys, fn key ->
        case Map.fetch!(original_env, key) do
          nil -> System.delete_env(key)
          value -> System.put_env(key, value)
        end
      end)

      File.rm_rf(tmp_home)
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
      assert opts.model == "gpt-5.2-codex"
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
      File.write!(auth_path, ~s({"OPENAI_API_KEY":"sk-test"}))

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
      assert opts.api_key == "sk-test"
    end

    test "does not treat chatgpt tokens as api keys" do
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
      assert opts.api_key == nil
    end
  end
end

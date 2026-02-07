defmodule Codex.OptionsTest do
  use ExUnit.Case, async: false

  alias Codex.Options

  setup do
    env_keys = ~w(CODEX_MODEL CODEX_MODEL_DEFAULT CODEX_API_KEY CODEX_HOME OPENAI_BASE_URL)

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
      assert opts.model == "gpt-5.3-codex"
      assert opts.reasoning_effort == :high
    end

    test "uses OPENAI_BASE_URL when base_url is not provided" do
      System.put_env("OPENAI_BASE_URL", "https://gateway.example.com/v1")

      assert {:ok, opts} = Options.new(%{})
      assert opts.base_url == "https://gateway.example.com/v1"
    end

    test "explicit base_url overrides OPENAI_BASE_URL" do
      System.put_env("OPENAI_BASE_URL", "https://gateway.example.com/v1")

      assert {:ok, opts} = Options.new(%{base_url: "https://explicit.example.com/v1"})
      assert opts.base_url == "https://explicit.example.com/v1"
    end

    test "allows API key to be omitted" do
      assert {:ok, opts} = Options.new(%{})
      assert opts.api_key == nil
      assert opts.model == "gpt-5.3-codex"
      assert opts.reasoning_effort == :medium
    end

    test "falls back to model-specific reasoning defaults" do
      {:ok, opts} = Options.new(%{model: "gpt-5.1-codex-mini"})

      assert opts.model == "gpt-5.1-codex-mini"
      assert opts.reasoning_effort == :medium
    end

    test "coerces unsupported reasoning effort values" do
      {:ok, opts} =
        Options.new(%{
          model: "gpt-5.1-codex-mini",
          reasoning_effort: :xhigh
        })

      assert opts.model == "gpt-5.1-codex-mini"
      assert opts.reasoning_effort == :high
    end

    test "accepts reasoning summary and verbosity options" do
      {:ok, opts} =
        Options.new(%{
          model_reasoning_summary: :concise,
          model_verbosity: "high",
          model_context_window: 8192,
          model_supports_reasoning_summaries: true
        })

      assert opts.model_reasoning_summary == "concise"
      assert opts.model_verbosity == "high"
      assert opts.model_context_window == 8192
      assert opts.model_supports_reasoning_summaries == true
    end

    test "accepts history persistence overrides" do
      {:ok, opts} =
        Options.new(%{
          history_persistence: :local,
          history_max_bytes: 12_000
        })

      assert opts.history_persistence == "local"
      assert opts.history_max_bytes == 12_000

      {:ok, opts_from_map} =
        Options.new(%{
          history: %{
            persistence: "remote",
            max_bytes: 24_000
          }
        })

      assert opts_from_map.history_persistence == "remote"
      assert opts_from_map.history_max_bytes == 24_000
    end

    test "accepts none personality" do
      assert {:ok, opts} = Options.new(%{model_personality: :none})
      assert opts.model_personality == :none

      assert {:ok, opts} = Options.new(%{model_personality: "none"})
      assert opts.model_personality == :none
    end

    test "accepts model personality and agent limits" do
      {:ok, opts} =
        Options.new(%{
          model_personality: :friendly,
          model_auto_compact_token_limit: 512,
          review_model: "gpt-5.2",
          hide_agent_reasoning: true,
          tool_output_token_limit: 256,
          agent_max_threads: 3
        })

      assert opts.model_personality == :friendly
      assert opts.model_auto_compact_token_limit == 512
      assert opts.review_model == "gpt-5.2"
      assert opts.hide_agent_reasoning == true
      assert opts.tool_output_token_limit == 256
      assert opts.agent_max_threads == 3
    end

    test "accepts options-level config overrides and flattens nested maps" do
      {:ok, opts} =
        Options.new(%{
          config: %{
            "approval_policy" => "never",
            "sandbox_workspace_write" => %{"network_access" => true}
          }
        })

      assert {"approval_policy", "never"} in opts.config_overrides
      assert {"sandbox_workspace_write.network_access", true} in opts.config_overrides
    end

    test "rejects invalid options-level config override values" do
      assert {:error, {:invalid_config_override_value, "features.web_search_request", nil}} =
               Options.new(%{
                 config: %{"features" => %{"web_search_request" => nil}}
               })
    end

    test "rejects invalid reasoning summary" do
      assert {:error, {:invalid_model_reasoning_summary, "loud"}} =
               Options.new(%{model_reasoning_summary: "loud"})
    end

    test "rejects invalid tool output token limit" do
      assert {:error, {:invalid_tool_output_token_limit, 0}} =
               Options.new(%{tool_output_token_limit: 0})
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

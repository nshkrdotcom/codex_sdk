defmodule Codex.ModelsTest do
  use ExUnit.Case, async: false

  alias Codex.Models

  setup do
    env_keys = ~w(CODEX_MODEL OPENAI_DEFAULT_MODEL CODEX_MODEL_DEFAULT CODEX_API_KEY CODEX_HOME)

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

  test "list_visible/1 returns api defaults when remote models are disabled" do
    with_temp_codex_home(fn _home ->
      models = Models.list_visible(:api)

      assert Enum.map(models, & &1.id) == [
               "gpt-5.1-codex-max",
               "gpt-5.1-codex-mini",
               "gpt-5.2"
             ]

      assert Enum.any?(models, &(&1.id == "gpt-5.1-codex-max" && &1.is_default))
    end)
  end

  test "list_visible/1 returns chatgpt defaults when remote models are disabled" do
    with_temp_codex_home(fn _home ->
      models = Models.list_visible(:chatgpt)

      assert Enum.map(models, & &1.id) == [
               "gpt-5.2-codex",
               "gpt-5.1-codex-max",
               "gpt-5.1-codex-mini",
               "gpt-5.2"
             ]

      assert Enum.any?(models, &(&1.id == "gpt-5.2-codex" && &1.is_default))
    end)
  end

  test "auth-aware defaults prefer api keys when present" do
    with_temp_codex_home(fn home ->
      assert Models.default_model() == "gpt-5.2-codex"

      System.put_env("CODEX_API_KEY", "sk-test")
      assert Models.default_model() == "gpt-5.1-codex-max"
      System.delete_env("CODEX_API_KEY")

      write_auth_json!(home, %{"OPENAI_API_KEY" => "sk-auth"})
      assert Models.default_model() == "gpt-5.1-codex-max"
    end)
  end

  test "honors OPENAI_DEFAULT_MODEL override" do
    System.put_env("OPENAI_DEFAULT_MODEL", "custom-model")
    assert Models.default_model() == "custom-model"
  end

  test "remote models are gated behind features.remote_models" do
    with_temp_codex_home(fn home ->
      models = Models.list_visible(:api)
      refute Enum.any?(models, &(&1.id == "gpt-5.1-codex"))

      write_config!(home, true)
      models = Models.list_visible(:api)
      assert Enum.any?(models, &(&1.id == "gpt-5.1-codex"))
      assert Enum.any?(models, &(&1.id == "gpt-5.1-codex-max" && &1.is_default))
    end)
  end

  test "prefers codex-auto-balanced when available for chatgpt auth" do
    with_temp_codex_home(fn home ->
      write_config!(home, true)

      write_models_cache!(home, [
        remote_model_info("codex-auto-balanced", 0,
          visibility: "list",
          supported_in_api: false
        )
      ])

      assert Models.default_model() == "codex-auto-balanced"
    end)
  end

  test "upgrade metadata includes reasoning effort mapping for remote models" do
    with_temp_codex_home(fn home ->
      write_config!(home, true)

      upgrade = Models.get_upgrade("gpt-5.1")

      assert upgrade.id == "gpt-5.1-codex-max"
      assert upgrade.migration_config_key == "gpt-5.1"
      assert upgrade.reasoning_effort_mapping[:none] == :low
      assert upgrade.reasoning_effort_mapping[:minimal] == :low
      assert upgrade.reasoning_effort_mapping[:xhigh] == :high
    end)
  end

  test "normalizes reasoning effort and preserves model helpers" do
    assert Models.normalize_reasoning_effort("none") == {:ok, :none}
    assert Models.normalize_reasoning_effort(:none) == {:ok, :none}
    assert Models.reasoning_effort_to_string(:none) == "none"
    assert Models.supported_in_api?("gpt-5.2-codex") == false
    assert Models.tool_enabled?("gpt-5.1")
  end

  defp with_temp_codex_home(fun) when is_function(fun, 1) do
    tmp_home = Path.join(System.tmp_dir!(), "codex_home_#{System.unique_integer([:positive])}")
    original_home = System.get_env("CODEX_HOME")
    File.mkdir_p!(tmp_home)
    System.put_env("CODEX_HOME", tmp_home)

    try do
      fun.(tmp_home)
    after
      case original_home do
        nil -> System.delete_env("CODEX_HOME")
        value -> System.put_env("CODEX_HOME", value)
      end

      File.rm_rf(tmp_home)
    end
  end

  defp write_auth_json!(home, data) do
    path = Path.join(home, "auth.json")
    File.write!(path, Jason.encode!(data))
  end

  defp write_config!(home, remote_models?) do
    config = """
    [features]
    remote_models = #{remote_models?}
    """

    File.write!(Path.join(home, "config.toml"), config)
  end

  defp write_models_cache!(home, models) do
    cache = %{
      "fetched_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "etag" => "test-etag",
      "models" => models
    }

    File.write!(Path.join(home, "models_cache.json"), Jason.encode!(cache))
  end

  defp remote_model_info(slug, priority, opts) do
    visibility = Keyword.get(opts, :visibility, "list")
    supported_in_api = Keyword.get(opts, :supported_in_api, true)

    %{
      "slug" => slug,
      "display_name" => slug,
      "description" => "#{slug} description",
      "default_reasoning_level" => "medium",
      "supported_reasoning_levels" => [
        %{"effort" => "low", "description" => "low"},
        %{"effort" => "medium", "description" => "medium"}
      ],
      "shell_type" => "shell_command",
      "visibility" => visibility,
      "minimal_client_version" => [0, 1, 0],
      "supported_in_api" => supported_in_api,
      "priority" => priority,
      "upgrade" => nil,
      "base_instructions" => nil,
      "supports_reasoning_summaries" => false,
      "support_verbosity" => false,
      "default_verbosity" => nil,
      "apply_patch_tool_type" => nil,
      "truncation_policy" => %{"mode" => "bytes", "limit" => 10_000},
      "supports_parallel_tool_calls" => false,
      "context_window" => nil,
      "reasoning_summary_format" => "none",
      "experimental_supported_tools" => []
    }
  end
end

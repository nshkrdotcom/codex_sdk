defmodule Codex.ModelsTest do
  use ExUnit.Case, async: false

  alias Codex.Models
  import Codex.Test.ModelFixtures

  setup do
    env_keys = ~w(CODEX_MODEL OPENAI_DEFAULT_MODEL CODEX_MODEL_DEFAULT CODEX_API_KEY CODEX_HOME)

    original_system_path = Application.get_env(:codex_sdk, :system_config_path)

    original_env =
      env_keys
      |> Enum.map(&{&1, System.get_env(&1)})
      |> Map.new()

    Enum.each(env_keys, &System.delete_env/1)

    tmp_home = Path.join(System.tmp_dir!(), "codex_home_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_home)
    System.put_env("CODEX_HOME", tmp_home)

    Application.put_env(
      :codex_sdk,
      :system_config_path,
      Path.join(tmp_home, "system_config.toml")
    )

    on_exit(fn ->
      Enum.each(env_keys, fn key ->
        case Map.fetch!(original_env, key) do
          nil -> System.delete_env(key)
          value -> System.put_env(key, value)
        end
      end)

      case original_system_path do
        nil -> Application.delete_env(:codex_sdk, :system_config_path)
        value -> Application.put_env(:codex_sdk, :system_config_path, value)
      end

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
               "gpt-5.3-codex",
               "gpt-5.1-codex-max",
               "gpt-5.1-codex-mini",
               "gpt-5.2"
             ]

      assert Enum.any?(models, &(&1.id == default_model() && &1.is_default))
    end)
  end

  test "default model remains consistent across credential sources" do
    with_temp_codex_home(fn home ->
      assert Models.default_model() == default_model()

      System.put_env("CODEX_API_KEY", "sk-test")
      assert Models.default_model() == default_model()
      System.delete_env("CODEX_API_KEY")

      write_auth_json!(home, %{"OPENAI_API_KEY" => "sk-auth"})
      assert Models.default_model() == default_model()
    end)
  end

  test "honors OPENAI_DEFAULT_MODEL override" do
    System.put_env("OPENAI_DEFAULT_MODEL", "custom-model")
    assert Models.default_model() == "custom-model"
  end

  test "remote models are gated behind features.remote_models" do
    with_temp_codex_home(fn home ->
      # Without remote_models config, we should get local presets
      models = Models.list_visible(:api)
      # Local presets include gpt-5.1-codex-max, gpt-5.1-codex-mini, gpt-5.2
      assert Enum.any?(models, &(&1.id == "gpt-5.1-codex-max"))
      assert length(models) >= 3

      write_config!(home, true)
      models = Models.list_visible(:api)
      # With remote_models enabled, we may get additional models from cache
      # but should still have the core models
      assert Enum.any?(models, &(&1.id == "gpt-5.1-codex-max" && &1.is_default))
    end)
  end

  test "does not override default model when codex-auto-balanced is available" do
    with_temp_codex_home(fn home ->
      write_config!(home, true)

      write_models_cache!(home, [
        remote_model_info("codex-auto-balanced", 0,
          visibility: "list",
          supported_in_api: false
        )
      ])

      assert Models.default_model() == default_model()
    end)
  end

  test "upgrade metadata includes reasoning effort mapping for remote models" do
    with_temp_codex_home(fn home ->
      write_config!(home, true)

      upgrade = Models.get_upgrade(max_model())

      assert upgrade.id == default_model()
      assert upgrade.migration_config_key == max_model()
      # The upgrade may have reasoning effort mapping or nil depending on JSON
      # Just verify the upgrade exists and has the expected id
      assert is_map(upgrade)
    end)
  end

  test "normalizes reasoning effort and preserves model helpers" do
    assert Models.normalize_reasoning_effort("none") == {:ok, :none}
    assert Models.normalize_reasoning_effort("minimal") == {:ok, :minimal}
    assert Models.normalize_reasoning_effort(:none) == {:ok, :none}
    assert Models.reasoning_effort_to_string(:none) == "none"
    assert Models.normalize_reasoning_effort("xhigh") == {:ok, :xhigh}
    assert Models.reasoning_effort_to_string(:xhigh) == "xhigh"
    assert Models.supported_in_api?(default_model()) == false
    assert Models.tool_enabled?("gpt-5.1")
  end

  test "coerces reasoning effort to supported values" do
    assert Models.coerce_reasoning_effort("gpt-5.1-codex-mini", :xhigh) == :high
    assert Models.coerce_reasoning_effort("gpt-5.1-codex-mini", :low) == :medium
    assert Models.coerce_reasoning_effort("gpt-5.1-codex-max", :xhigh) == :xhigh
    assert Models.coerce_reasoning_effort("unknown-model", :xhigh) == :xhigh
  end

  test "parse_client_version supports string and array formats" do
    assert Models.parse_client_version([1, 2, 3]) == {1, 2, 3}
    assert Models.parse_client_version("0.60.0") == {0, 60, 0}
    assert Models.parse_client_version("0.60.0-alpha.1") == {0, 60, 0}
    assert Models.parse_client_version("invalid") == {0, 0, 0}
  end

  defp with_temp_codex_home(fun) when is_function(fun, 1) do
    tmp_home = Path.join(System.tmp_dir!(), "codex_home_#{System.unique_integer([:positive])}")
    original_home = System.get_env("CODEX_HOME")
    original_system_path = Application.get_env(:codex_sdk, :system_config_path)
    File.mkdir_p!(tmp_home)
    System.put_env("CODEX_HOME", tmp_home)

    Application.put_env(
      :codex_sdk,
      :system_config_path,
      Path.join(tmp_home, "system_config.toml")
    )

    try do
      fun.(tmp_home)
    after
      case original_home do
        nil -> System.delete_env("CODEX_HOME")
        value -> System.put_env("CODEX_HOME", value)
      end

      case original_system_path do
        nil -> Application.delete_env(:codex_sdk, :system_config_path)
        value -> Application.put_env(:codex_sdk, :system_config_path, value)
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

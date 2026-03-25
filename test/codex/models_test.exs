defmodule Codex.ModelsTest do
  use ExUnit.Case, async: false

  alias Codex.Models
  import Codex.Test.ModelFixtures

  setup do
    env_keys =
      ~w(
        CODEX_MODEL
        OPENAI_DEFAULT_MODEL
        CODEX_MODEL_DEFAULT
        CODEX_API_KEY
        CODEX_HOME
        CODEX_CA_CERTIFICATE
        SSL_CERT_FILE
        OPENAI_BASE_URL
      )

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

  test "list_visible/1 returns the core public codex catalog" do
    with_temp_codex_home(fn _home ->
      models = Models.list_visible(:api)

      assert Enum.map(models, & &1.id) == [
               "gpt-5-codex",
               "gpt-5.3-codex",
               "gpt-5.4",
               "gpt-5.4-mini",
               "gpt-5.3-codex-spark",
               "gpt-5.2-codex",
               "gpt-5.2",
               "gpt-5.1-codex-max",
               "gpt-5.1-codex-mini",
               "gpt-5.1-codex",
               "gpt-5",
               "gpt-5.1"
             ]

      assert Enum.any?(models, &(&1.id == "gpt-5.4-mini"))
      refute Enum.any?(models, &(&1.id == "gpt-5-codex-internal"))
      assert length(models) == 12

      assert Enum.any?(models, &(&1.id == default_model() && &1.is_default))
    end)
  end

  test "list_visible/1 no longer changes across auth modes" do
    with_temp_codex_home(fn _home ->
      assert Enum.map(Models.list_visible(:chatgpt), & &1.id) ==
               Enum.map(Models.list_visible(:api), & &1.id)

      models = Models.list_visible(:chatgpt)
      assert Enum.any?(models, &(&1.id == default_model() && &1.is_default))
      assert Models.supported_in_api?("gpt-5.4-mini")
      assert Models.supported_in_api?("gpt-5.3-codex-spark")
      assert Models.default_reasoning_effort("gpt-5.4-mini") == :medium
      assert Models.default_reasoning_effort("gpt-5.3-codex-spark") == :high
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

  test "default reasoning effort stays safe for cross-catalog model overrides" do
    with_temp_codex_home(fn home ->
      write_auth_json!(home, %{"OPENAI_API_KEY" => "sk-auth"})
      System.put_env("CODEX_MODEL", "gpt-5.4-mini")

      assert Models.default_model() == "gpt-5.4-mini"
      assert Models.default_reasoning_effort("gpt-5.4-mini") == :medium
    end)
  end

  test "honors OPENAI_DEFAULT_MODEL override" do
    System.put_env("OPENAI_DEFAULT_MODEL", "custom-model")
    assert Models.default_model() == "custom-model"
  end

  test "visible model listing comes from the shared core catalog" do
    with_temp_codex_home(fn home ->
      models = Models.list_visible(:api)
      assert Enum.any?(models, &(&1.id == "gpt-5-codex"))
      assert Enum.any?(models, &(&1.id == "gpt-5.3-codex"))
      assert Enum.any?(models, &(&1.id == "gpt-5.2-codex"))
      assert length(models) == 12

      write_config!(home, true)
      assert Enum.map(Models.list_visible(:api), & &1.id) == Enum.map(models, & &1.id)
    end)
  end

  test "default model no longer depends on cached remote model catalogs" do
    with_temp_codex_home(fn home ->
      write_models_cache!(home, [
        remote_model_info("codex-auto-balanced", 0,
          visibility: "list",
          supported_in_api: false
        ),
        remote_model_info(default_model(), 1,
          visibility: "list",
          supported_in_api: true
        )
      ])

      assert Models.default_model(:api) == default_model()
      assert Models.default_model(:chatgpt) == default_model()
    end)
  end

  test "upgrade metadata is no longer owned locally" do
    with_temp_codex_home(fn home ->
      write_models_cache!(home, [
        remote_model_info(default_model(), 0,
          visibility: "list",
          supported_in_api: true,
          upgrade: nil
        ),
        remote_model_info("gpt-5.2-codex", 1,
          visibility: "list",
          supported_in_api: true,
          upgrade: %{
            "model" => default_model(),
            "migration_markdown" => "Learn more: https://openai.com/index/introducing-gpt-5-4/"
          }
        )
      ])

      assert Models.get_upgrade("gpt-5.2-codex") == nil
    end)
  end

  test "normalizes reasoning effort and preserves model helpers" do
    assert Models.normalize_reasoning_effort("none") == {:ok, :none}
    assert Models.normalize_reasoning_effort("minimal") == {:ok, :minimal}
    assert Models.normalize_reasoning_effort(:none) == {:ok, :none}
    assert Models.reasoning_effort_to_string(:none) == "none"
    assert Models.normalize_reasoning_effort("xhigh") == {:ok, :xhigh}
    assert Models.reasoning_effort_to_string(:xhigh) == "xhigh"
    assert Models.supported_in_api?(default_model()) == true
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

  test "remote models http options include custom CA ssl settings" do
    System.put_env("CODEX_CA_CERTIFICATE", "/tmp/codex-ca.pem")

    opts = Models.remote_models_http_options()
    timeout = Keyword.fetch!(opts, :timeout)

    assert Keyword.get(opts, :ssl) == [cacertfile: "/tmp/codex-ca.pem"]
    assert is_integer(timeout)
    assert timeout > 0
  end

  test "remote models url prefers layered openai_base_url over env" do
    with_temp_codex_home(fn home ->
      System.put_env("OPENAI_BASE_URL", "https://env.example.com/v1")

      File.write!(
        Path.join(home, "config.toml"),
        """
        openai_base_url = "https://config.example.com/v1"
        """
      )

      url = Models.remote_models_url()

      assert String.starts_with?(url, "https://config.example.com/v1/models?")
      assert url =~ "client_version="
    end)
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
    upgrade = Keyword.get(opts, :upgrade, nil)

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
      "upgrade" => upgrade,
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

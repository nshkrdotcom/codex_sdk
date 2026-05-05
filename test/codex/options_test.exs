defmodule Codex.OptionsTest do
  use ExUnit.Case, async: false

  alias CliSubprocessCore.ExecutionSurface
  alias CliSubprocessCore.ModelRegistry.Selection
  alias Codex.Config.BaseURL
  alias Codex.Options
  alias Codex.TestSupport.GovernedAuthority
  import Codex.Test.ModelFixtures

  setup do
    env_keys =
      ~w(
        CODEX_MODEL
        CODEX_MODEL_DEFAULT
        CODEX_PROVIDER_BACKEND
        CODEX_OSS_PROVIDER
        CODEX_OLLAMA_BASE_URL
        CODEX_API_KEY
        CODEX_HOME
        OPENAI_BASE_URL
      )

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
      assert opts.model == default_model()
      assert opts.reasoning_effort == :high
    end

    test "normalizes execution_surface from public attrs" do
      assert {:ok, %Options{execution_surface: %ExecutionSurface{} = execution_surface}} =
               Options.new(%{
                 execution_surface: %{
                   surface_kind: :ssh_exec,
                   transport_options: [destination: "options.test.example", port: 2222]
                 }
               })

      assert execution_surface.surface_kind == :ssh_exec
      assert execution_surface.transport_options[:destination] == "options.test.example"
      assert execution_surface.transport_options[:port] == 2222
    end

    test "defaults execution_surface to local_subprocess" do
      assert {:ok, %Options{execution_surface: %ExecutionSurface{} = execution_surface}} =
               Options.new(%{})

      assert execution_surface.surface_kind == :local_subprocess
      assert execution_surface.transport_options == []
    end

    test "codex_command_spec/2 falls back to the remote provider command instead of leaking local CODEX_PATH" do
      dir =
        Path.join(System.tmp_dir!(), "codex_options_remote_#{System.unique_integer([:positive])}")

      File.mkdir_p!(dir)
      local_path = Path.join(dir, "codex")
      File.write!(local_path, "#!/usr/bin/env bash\nexit 0\n")
      File.chmod!(local_path, 0o755)
      previous = System.get_env("CODEX_PATH")

      System.put_env("CODEX_PATH", local_path)

      on_exit(fn ->
        case previous do
          nil -> System.delete_env("CODEX_PATH")
          value -> System.put_env("CODEX_PATH", value)
        end

        File.rm_rf(dir)
      end)

      assert {:ok, opts} = Options.new(%{})

      assert {:ok, %CliSubprocessCore.CommandSpec{program: "codex", argv_prefix: []}} =
               Options.codex_command_spec(
                 opts,
                 surface_kind: :ssh_exec,
                 transport_options: [destination: "ssh.example"]
               )
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

    test "governed authority ignores ambient auth, base URL, auth file, and model env" do
      System.put_env("CODEX_API_KEY", "ambient-codex-key")
      System.put_env("OPENAI_BASE_URL", "https://ambient.example.com/v1")
      System.put_env("CODEX_MODEL", alt_model())

      File.write!(
        Path.join(System.get_env("CODEX_HOME"), "auth.json"),
        ~s({"OPENAI_API_KEY":"sk-auth-file"})
      )

      assert {:ok, opts} = Options.new(%{governed_authority: GovernedAuthority.refs()})

      assert opts.governed_authority["authority_ref"] == "authz-codex-test"
      assert opts.api_key == nil
      assert opts.base_url == BaseURL.default()
      assert opts.model == default_model()
    end

    test "governed authority accepts explicit materialized auth and command refs" do
      assert {:ok, opts} =
               Options.new(%{
                 governed_authority: GovernedAuthority.command_refs(),
                 api_key: "materialized-key",
                 base_url: "https://materialized.example.com/v1",
                 codex_path_override: "/opt/materialized/codex",
                 model: alt_model()
               })

      assert opts.api_key == "materialized-key"
      assert opts.base_url == "https://materialized.example.com/v1"
      assert opts.codex_path_override == "/opt/materialized/codex"
      assert opts.model == alt_model()
    end

    test "governed authority keeps two native auth roots distinct" do
      assert {:ok, root_a} =
               Options.new(%{
                 governed_authority:
                   GovernedAuthority.refs(
                     native_auth_assertion_ref: "native-codex-root-a",
                     provider_account_ref: "provider-account-codex-root-a",
                     materialization_ref: "materialization-codex-root-a"
                   )
               })

      assert {:ok, root_b} =
               Options.new(%{
                 governed_authority:
                   GovernedAuthority.refs(
                     native_auth_assertion_ref: "native-codex-root-b",
                     provider_account_ref: "provider-account-codex-root-b",
                     materialization_ref: "materialization-codex-root-b"
                   )
               })

      assert root_a.governed_authority["provider_account_ref"] ==
               "provider-account-codex-root-a"

      assert root_b.governed_authority["provider_account_ref"] ==
               "provider-account-codex-root-b"

      refute root_a.governed_authority["native_auth_assertion_ref"] ==
               root_b.governed_authority["native_auth_assertion_ref"]
    end

    test "governed authority rejects incomplete authority refs" do
      assert {:error, {:missing_governed_authority_refs, missing}} =
               Options.new(%{governed_authority: %{authority_ref: "authz-only"}})

      assert "credential_lease_ref" in missing
      assert "connector_instance_ref" in missing
      assert "operation_policy_ref" in missing
      assert "materialization_ref" in missing
    end

    test "governed authority rejects raw secret-shaped fields" do
      authority = Map.put(GovernedAuthority.refs(), :api_key, "sk-raw")

      assert {:error, {:raw_secret_field_in_governed_authority, "api_key"}} =
               Options.new(%{governed_authority: authority})
    end

    test "governed authority rejects secret config overrides" do
      assert {:error, {:governed_secret_config_override, :options, "api_key"}} =
               Options.new(%{
                 governed_authority: GovernedAuthority.refs(),
                 config: %{"api_key" => "raw"}
               })
    end

    test "governed authority rejects command override without command ref" do
      assert {:error, {:governed_command_ref_required, :options}} =
               Options.new(%{
                 governed_authority: GovernedAuthority.refs(),
                 codex_path_override: "/opt/materialized/codex"
               })
    end

    test "allows API key to be omitted" do
      assert {:ok, opts} = Options.new(%{})
      assert opts.api_key == nil
      assert opts.model == default_model()
      assert opts.reasoning_effort == :medium
    end

    test "execution_model/1 omits implicit shared-core defaults" do
      assert {:ok, opts} = Options.new(%{})
      assert Options.execution_model(opts) == nil
    end

    test "execution_model/1 preserves explicit and environment model overrides" do
      assert {:ok, explicit_opts} = Options.new(%{model: alt_model()})
      assert Options.execution_model(explicit_opts) == alt_model()

      System.put_env("CODEX_MODEL", alt_model())
      assert {:ok, env_opts} = Options.new(%{})
      assert Options.execution_model(env_opts) == alt_model()
    end

    test "falls back to model-specific reasoning defaults" do
      {:ok, opts} = Options.new(%{model: alt_model()})

      assert opts.model == alt_model()
      assert opts.reasoning_effort == :medium
    end

    test "treats an explicit model_payload as authoritative" do
      payload =
        Selection.new(%{
          provider: :codex,
          requested_model: "gpt-oss:20b",
          resolved_model: "gpt-oss:20b",
          resolution_source: :explicit,
          reasoning: "high",
          reasoning_effort: nil,
          normalized_reasoning_effort: nil,
          model_family: "gpt-oss",
          catalog_version: nil,
          visibility: :public,
          provider_backend: :oss,
          model_source: :external,
          env_overrides: %{},
          settings_patch: %{},
          backend_metadata: %{
            "provider_backend" => "oss",
            "oss_provider" => "ollama",
            "external_model" => "gpt-oss:20b"
          },
          errors: []
        })

      assert {:ok, opts} =
               Options.new(%{
                 model_payload: payload,
                 model: "gpt-oss:20b",
                 provider_backend: :oss,
                 oss_provider: "ollama"
               })

      assert opts.model_payload == payload
      assert opts.model == "gpt-oss:20b"
      assert opts.reasoning_effort == :high
    end

    test "accepts authoritative payloads for runtime-validated local Ollama models" do
      payload =
        Selection.new(%{
          provider: :codex,
          requested_model: "llama3.2",
          resolved_model: "llama3.2",
          resolution_source: :explicit,
          reasoning: "high",
          reasoning_effort: nil,
          normalized_reasoning_effort: nil,
          model_family: "llama",
          catalog_version: nil,
          visibility: :public,
          provider_backend: :oss,
          model_source: :external,
          env_overrides: %{},
          settings_patch: %{},
          backend_metadata: %{
            "provider_backend" => "oss",
            "oss_provider" => "ollama",
            "external_model" => "llama3.2",
            "support_tier" => "runtime_validated_only"
          },
          errors: []
        })

      assert {:ok, opts} =
               Options.new(%{
                 model_payload: payload,
                 model: "llama3.2",
                 provider_backend: :oss,
                 oss_provider: "ollama"
               })

      assert opts.model_payload == payload
      assert opts.model == "llama3.2"
      assert opts.reasoning_effort == :high
    end

    test "rejects raw attrs that conflict with an explicit model_payload" do
      payload =
        Selection.new(%{
          provider: :codex,
          requested_model: "gpt-oss:20b",
          resolved_model: "gpt-oss:20b",
          resolution_source: :explicit,
          reasoning: "high",
          reasoning_effort: nil,
          normalized_reasoning_effort: nil,
          model_family: "gpt-oss",
          catalog_version: nil,
          visibility: :public,
          provider_backend: :oss,
          model_source: :external,
          env_overrides: %{},
          settings_patch: %{},
          backend_metadata: %{
            "provider_backend" => "oss",
            "oss_provider" => "ollama",
            "external_model" => "gpt-oss:20b"
          },
          errors: []
        })

      assert {:error, {:model_payload_conflict, :model, "gpt-oss:20b", "gpt-5.4"}} =
               Options.new(%{
                 model_payload: payload,
                 model: "gpt-5.4"
               })

      assert {:error, {:model_payload_conflict, :provider_backend, :oss, :openai}} =
               Options.new(%{
                 model_payload: payload,
                 provider_backend: :openai
               })
    end

    test "does not treat env defaults as active config when model_payload is explicit" do
      payload =
        Selection.new(%{
          provider: :codex,
          requested_model: "llama3.2",
          resolved_model: "llama3.2",
          resolution_source: :explicit,
          reasoning: "high",
          reasoning_effort: nil,
          normalized_reasoning_effort: nil,
          model_family: "llama",
          catalog_version: nil,
          visibility: :public,
          provider_backend: :oss,
          model_source: :external,
          env_overrides: %{"CODEX_OSS_BASE_URL" => "http://127.0.0.1:22434"},
          settings_patch: %{},
          backend_metadata: %{
            "provider_backend" => "oss",
            "oss_provider" => "ollama",
            "external_model" => "llama3.2",
            "support_tier" => "runtime_validated_only"
          },
          errors: []
        })

      System.put_env("CODEX_MODEL", "gpt-5.4")
      System.put_env("CODEX_PROVIDER_BACKEND", "openai")
      System.put_env("CODEX_OSS_PROVIDER", "other")
      System.put_env("CODEX_OLLAMA_BASE_URL", "http://127.0.0.1:11434")

      assert {:ok, opts} = Options.new(%{model_payload: payload})
      assert opts.model_payload == payload
      assert opts.model == "llama3.2"
      assert opts.reasoning_effort == :high
    end

    test "does not crash when CODEX_MODEL points at a cross-catalog model under api auth" do
      auth_path = Path.join(System.get_env("CODEX_HOME"), "auth.json")
      File.write!(auth_path, ~s({"OPENAI_API_KEY":"sk-test"}))
      System.put_env("CODEX_MODEL", "gpt-5.4-mini")

      assert {:ok, opts} = Options.new(%{})
      assert opts.api_key == "sk-test"
      assert opts.model == "gpt-5.4-mini"
      assert opts.reasoning_effort == :medium
    end

    test "rejects unsupported reasoning effort values" do
      assert {:error,
              {:invalid_reasoning_effort, :minimal, ["high", "low", "medium", "xhigh"], :codex}} =
               Options.new(%{
                 model: alt_model(),
                 reasoning_effort: :minimal
               })
    end

    test "accepts low reasoning for gpt-5.4-mini" do
      assert {:ok, %Options{} = opts} =
               Options.new(%{
                 model: "gpt-5.4-mini",
                 reasoning_effort: :low
               })

      assert opts.model == "gpt-5.4-mini"
      assert opts.reasoning_effort == :low
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

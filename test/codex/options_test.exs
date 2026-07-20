defmodule Codex.OptionsTest do
  use ExUnit.Case, async: false

  alias Codex.TestSupport.Env

  alias CliSubprocessCore.ExecutionSurface
  alias CliSubprocessCore.GovernedAuthority, as: CoreGovernedAuthority
  alias CliSubprocessCore.ModelRegistry.Selection
  alias Codex.GovernedAuthority, as: CodexAuthority
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

    Enum.each(env_keys, &Env.delete/1)

    tmp_home = Path.join(System.tmp_dir!(), "codex_home_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_home)
    Env.put("CODEX_HOME", tmp_home)

    on_exit(fn ->
      Enum.each(env_keys, fn key ->
        case Map.fetch!(original_env, key) do
          nil -> Env.delete(key)
          value -> Env.put(key, value)
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

      Env.put("CODEX_PATH", local_path)

      on_exit(fn ->
        case previous do
          nil -> Env.delete("CODEX_PATH")
          value -> Env.put("CODEX_PATH", value)
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
      Env.put("OPENAI_BASE_URL", "https://gateway.example.com/v1")

      assert {:ok, opts} = Options.new(%{})
      assert opts.base_url == "https://gateway.example.com/v1"
    end

    test "explicit base_url overrides OPENAI_BASE_URL" do
      Env.put("OPENAI_BASE_URL", "https://gateway.example.com/v1")

      assert {:ok, opts} = Options.new(%{base_url: "https://explicit.example.com/v1"})
      assert opts.base_url == "https://explicit.example.com/v1"
    end

    test "governed authority ignores ambient auth, base URL, auth file, and model env" do
      Env.put("CODEX_API_KEY", "ambient-codex-key")
      Env.put("OPENAI_BASE_URL", "https://ambient.example.com/v1")
      Env.put("CODEX_MODEL", alt_model())

      File.write!(
        Path.join(System.get_env("CODEX_HOME"), "auth.json"),
        ~s({"OPENAI_API_KEY":"sk-auth-file"})
      )

      assert {:ok, opts} = Options.new(%{governed_authority: GovernedAuthority.refs()})

      assert opts.governed_authority.authority_ref == "authz-codex-test"
      assert opts.api_key == nil
      assert opts.base_url == "https://materialized.example.com/v1"
      assert opts.model == default_model()
    end

    test "governed authority rejects supplemental auth, routing, and command options" do
      for {key, value} <- [
            api_key: "supplemental-key",
            base_url: "https://supplemental.example.com/v1",
            codex_path_override: "/opt/supplemental/codex"
          ] do
        assert {:error, {:governed_option_supplementation, :options, ^key}} =
                 Options.new(
                   Map.put(%{governed_authority: GovernedAuthority.command_refs()}, key, value)
                 )
      end

      assert {:ok, opts} =
               Options.new(%{
                 governed_authority: GovernedAuthority.command_refs(),
                 model: alt_model()
               })

      assert opts.api_key == nil
      assert opts.base_url == "https://materialized.example.com/v1"
      assert opts.codex_path_override == "/bin/true"
      assert opts.model == alt_model()
    end

    test "governed authority keeps two native auth roots distinct" do
      assert {:ok, root_a} =
               Options.new(%{
                 governed_authority:
                   GovernedAuthority.refs(
                     native_auth_assertion_ref: "native-codex-root-a",
                     provider_account_ref: "provider-account-codex-root-a",
                     materialization_ref: "materialization-codex-root-a",
                     config_root: "/tmp/codex-root-a",
                     auth_root: "/tmp/codex-root-a",
                     env: %{
                       "CODEX_HOME" => "/tmp/codex-root-a",
                       "OPENAI_BASE_URL" => "https://materialized.example.com/v1"
                     }
                   )
               })

      assert {:ok, root_b} =
               Options.new(%{
                 governed_authority:
                   GovernedAuthority.refs(
                     native_auth_assertion_ref: "native-codex-root-b",
                     provider_account_ref: "provider-account-codex-root-b",
                     materialization_ref: "materialization-codex-root-b",
                     config_root: "/tmp/codex-root-b",
                     auth_root: "/tmp/codex-root-b",
                     env: %{
                       "CODEX_HOME" => "/tmp/codex-root-b",
                       "OPENAI_BASE_URL" => "https://materialized.example.com/v1"
                     }
                   )
               })

      assert root_a.governed_authority.provider_account_ref ==
               "provider-account-codex-root-a"

      assert root_b.governed_authority.provider_account_ref ==
               "provider-account-codex-root-b"

      refute root_a.governed_authority.native_auth_assertion_ref ==
               root_b.governed_authority.native_auth_assertion_ref

      refute root_a.governed_authority.config_root == root_b.governed_authority.config_root
    end

    test "governed authority rejects incomplete authority refs" do
      assert {:error, {:missing_governed_materialization_fields, missing}} =
               Options.new(%{governed_authority: %{authority_ref: "authz-only"}})

      assert :credential_lease_ref in missing
      assert :connector_instance_ref in missing
      assert :operation_policy_ref in missing
      assert :materialization_ref in missing
    end

    test "governed authority rejects raw secret-shaped fields" do
      authority = Map.put(GovernedAuthority.refs(), :api_key, "sk-raw")

      assert {:error, :invalid_governed_materialization} =
               Options.new(%{governed_authority: authority})
    end

    test "Codex authority projects explicitly into the narrower CLI runtime contract" do
      assert {:ok, opts} =
               Options.new(%{governed_authority: GovernedAuthority.command_refs()})

      codex_authority = opts.governed_authority

      assert {:error, {:invalid_governed_authority_field, :unknown_fields, rejected_fields}} =
               CoreGovernedAuthority.new(codex_authority)

      assert "__struct__" in rejected_fields
      assert "materialization_ref" in rejected_fields
      assert "operation_ref" in rejected_fields

      assert {:ok, %CoreGovernedAuthority{} = core_authority} =
               CodexAuthority.to_cli_core(codex_authority)

      assert core_authority.authority_ref == codex_authority.authority_ref
      assert core_authority.credential_lease_ref == codex_authority.credential_lease_ref
      assert core_authority.command == codex_authority.command
      assert core_authority.cwd == codex_authority.cwd
      assert core_authority.env == codex_authority.env
      assert core_authority.clear_env? == true

      projected_fields = core_authority |> Map.from_struct() |> Map.keys()
      refute :materialization_ref in projected_fields
      refute :operation_ref in projected_fields
      refute :generation in projected_fields
      refute :expires_at in projected_fields

      assert {:error, :invalid_governed_materialization} =
               CodexAuthority.to_cli_core(Map.from_struct(codex_authority))

      assert {:error,
              {:invalid_governed_authority_field, :unknown_fields, ["materialization_ref"]}} =
               core_authority
               |> Map.from_struct()
               |> Map.put(:materialization_ref, "smuggled-materialization")
               |> CoreGovernedAuthority.new()
    end

    test "governed authority rejects secret config overrides" do
      assert {:error, {:governed_config_override_forbidden, :options, "api_key"}} =
               Options.new(%{
                 governed_authority: GovernedAuthority.refs(),
                 config: %{"api_key" => "raw"}
               })
    end

    test "governed authority rejects command override" do
      assert {:error, {:governed_option_supplementation, :options, :codex_path_override}} =
               Options.new(%{
                 governed_authority: GovernedAuthority.refs(),
                 codex_path_override: "/opt/materialized/codex"
               })
    end

    test "governed authority rejects direct remote execution routing" do
      assert {:error, {:governed_execution_surface_mismatch, :surface_kind}} =
               Options.new(%{
                 governed_authority: GovernedAuthority.refs(),
                 execution_surface: %{
                   surface_kind: :ssh_exec,
                   transport_options: [destination: "smuggled.example"],
                   target_id: "target-codex-test",
                   lease_ref: "lease-codex-test"
                 }
               })
    end

    test "builds exact Codex materialization from frozen Jido contract maps" do
      now = DateTime.utc_now()

      request = %{
        materialization_ref: "materialization-1",
        lease_id: "lease-1",
        account: %{
          provider_family: "codex",
          account_ref: "account-1",
          endpoint_ref: "endpoint-1",
          generation: 7,
          fence: 3
        },
        authority_ref: "authority-1",
        endpoint_ref: "endpoint-1",
        target_ref: "target-1",
        operation_ref: "operation-1",
        issued_at: now,
        expires_at: DateTime.add(now, 300, :second)
      }

      secret = %{
        materialization_ref: "materialization-1",
        provider_family: "codex",
        account_ref: "account-1",
        generation: 7,
        payload: %{api_key: "EXACT-MATERIALIZED-SECRET"}
      }

      launch = %{
        native_auth_assertion_ref: "native-1",
        connector_instance_ref: "connector-1",
        connector_binding_ref: "binding-1",
        operation_policy_ref: "policy-1",
        command: "/opt/codex/bin/codex",
        cwd: "/tmp/workspace-1",
        config_root: "/tmp/codex-home-1",
        auth_root: "/tmp/codex-home-1",
        base_url: "https://codex.example/v1",
        env: %{
          "CODEX_HOME" => "/tmp/codex-home-1",
          "OPENAI_BASE_URL" => "https://codex.example/v1"
        }
      }

      assert {:ok, authority} = CodexAuthority.new(request, secret, launch)
      assert authority.provider_account_ref == "account-1"
      assert authority.account_namespace == "account-1"
      assert authority.credential_lease_ref == "lease-1"
      assert authority.generation == 7
      assert authority.fence == 3
      assert authority.env["CODEX_API_KEY"] == "EXACT-MATERIALIZED-SECRET"
      assert authority.env["OPENAI_API_KEY"] == "EXACT-MATERIALIZED-SECRET"
    end

    test "rejects cross-account and non-Codex contract materialization" do
      now = DateTime.utc_now()

      request = %{
        materialization_ref: "materialization-1",
        lease_id: "lease-1",
        account: %{
          provider_family: "codex",
          account_ref: "account-1",
          endpoint_ref: "endpoint-1",
          generation: 1,
          fence: 0
        },
        authority_ref: "authority-1",
        endpoint_ref: "endpoint-1",
        target_ref: "target-1",
        operation_ref: "operation-1",
        issued_at: now,
        expires_at: DateTime.add(now, 300, :second)
      }

      secret = %{
        materialization_ref: "materialization-1",
        provider_family: "codex",
        account_ref: "account-2",
        generation: 1,
        payload: %{api_key: "SECRET"}
      }

      assert {:error, :materialization_account_mismatch} =
               CodexAuthority.new(request, secret, %{})

      gemini_request = put_in(request, [:account, :provider_family], "gemini")
      gemini_secret = %{secret | provider_family: "gemini", account_ref: "account-1"}

      assert {:error, :invalid_codex_provider_family} =
               CodexAuthority.new(gemini_request, gemini_secret, %{})
    end

    test "allows API key to be omitted" do
      assert {:ok, opts} = Options.new(%{})
      assert opts.api_key == nil
      assert opts.model == default_model()
      assert opts.reasoning_effort == :low
    end

    test "execution_model/1 omits implicit shared-core defaults" do
      assert {:ok, opts} = Options.new(%{})
      assert Options.execution_model(opts) == nil
    end

    test "execution_model/1 preserves explicit and environment model overrides" do
      assert {:ok, explicit_opts} = Options.new(%{model: alt_model()})
      assert Options.execution_model(explicit_opts) == alt_model()

      Env.put("CODEX_MODEL", alt_model())
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

      Env.put("CODEX_MODEL", "gpt-5.4")
      Env.put("CODEX_PROVIDER_BACKEND", "openai")
      Env.put("CODEX_OSS_PROVIDER", "other")
      Env.put("CODEX_OLLAMA_BASE_URL", "http://127.0.0.1:11434")

      assert {:ok, opts} = Options.new(%{model_payload: payload})
      assert opts.model_payload == payload
      assert opts.model == "llama3.2"
      assert opts.reasoning_effort == :high
    end

    test "does not crash when CODEX_MODEL points at a cross-catalog model under api auth" do
      auth_path = Path.join(System.get_env("CODEX_HOME"), "auth.json")
      File.write!(auth_path, ~s({"OPENAI_API_KEY":"sk-test"}))
      Env.put("CODEX_MODEL", "gpt-5.4-mini")

      assert {:ok, opts} = Options.new(%{})
      assert opts.api_key == "sk-test"
      assert opts.model == "gpt-5.4-mini"
      assert opts.reasoning_effort == :medium
    end

    test "passes through a model newer than the bundled registry by default" do
      assert {:ok, %Options{} = opts} =
               Options.new(%{model: "gpt-5.9-not-yet-released"})

      assert opts.model == "gpt-5.9-not-yet-released"
      assert opts.model_payload.extra["unregistered"] == true
    end

    test "passes through an env-derived model newer than the bundled registry by default" do
      Env.put("CODEX_MODEL", "gpt-5.9-not-yet-released")

      assert {:ok, %Options{} = opts} = Options.new(%{})
      assert opts.model == "gpt-5.9-not-yet-released"
      assert opts.model_payload.extra["unregistered"] == true
    end

    test "allow_unknown_model: false restores strict rejection of unlisted models" do
      assert {:error, {:unknown_model, "gpt-5.9-not-yet-released", known, :codex}} =
               Options.new(%{model: "gpt-5.9-not-yet-released", allow_unknown_model: false})

      assert is_list(known)
    end

    test "allow_unknown_model: false still resolves known models normally" do
      assert {:ok, %Options{} = opts} =
               Options.new(%{model: alt_model(), allow_unknown_model: false})

      assert opts.model == alt_model()
      refute Map.get(opts.model_payload.extra, "unregistered")
    end

    test "allow_unknown_model: false recognizes the Spark preview" do
      assert {:ok, %Options{} = opts} =
               Options.new(%{
                 model: "gpt-5.3-codex-spark",
                 allow_unknown_model: false
               })

      assert opts.model == "gpt-5.3-codex-spark"
      assert opts.reasoning_effort == :high
      refute Map.get(opts.model_payload.extra, "unregistered")
    end

    test "rejects a non-boolean allow_unknown_model value" do
      assert {:error, {:invalid_allow_unknown_model, "yes"}} =
               Options.new(%{model: alt_model(), allow_unknown_model: "yes"})
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

    test "accepts current GPT-5.6 max and ultra reasoning boundaries" do
      assert {:ok, %Options{model: "gpt-5.6-sol", reasoning_effort: :max}} =
               Options.new(%{model: "gpt-5.6-sol", reasoning_effort: :max})

      assert {:ok, %Options{model: "gpt-5.6-terra", reasoning_effort: :ultra}} =
               Options.new(%{model: "gpt-5.6-terra", reasoning_effort: :ultra})

      assert {:ok, %Options{model: "gpt-5.6-luna", reasoning_effort: :max}} =
               Options.new(%{model: "gpt-5.6-luna", reasoning_effort: :max})

      assert {:error,
              {:invalid_reasoning_effort, :ultra, ["high", "low", "max", "medium", "xhigh"],
               :codex}} =
               Options.new(%{model: "gpt-5.6-luna", reasoning_effort: :ultra})

      for effort <- [:max, :ultra] do
        assert {:error,
                {:invalid_reasoning_effort, ^effort, ["high", "low", "medium", "xhigh"], :codex}} =
                 Options.new(%{model: "gpt-5.3-codex-spark", reasoning_effort: effort})
      end
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
      Env.put("CODEX_HOME", tmp_home)
      Env.delete("CODEX_API_KEY")

      on_exit(fn ->
        if original_env,
          do: Env.put("CODEX_HOME", original_env),
          else: Env.delete("CODEX_HOME")

        Env.delete("CODEX_API_KEY")
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
      Env.put("CODEX_HOME", tmp_home)
      Env.delete("CODEX_API_KEY")

      on_exit(fn ->
        if original_env,
          do: Env.put("CODEX_HOME", original_env),
          else: Env.delete("CODEX_HOME")

        Env.delete("CODEX_API_KEY")
        File.rm_rf(tmp_home)
      end)

      assert {:ok, opts} = Options.new(%{})
      assert opts.api_key == nil
    end
  end
end

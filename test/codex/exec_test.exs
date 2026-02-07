defmodule Codex.ExecTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Codex.{Events, Exec, Items, Options, Thread}
  alias Codex.TestSupport.FixtureScripts
  alias Codex.Thread.Options, as: ThreadOptions

  @moduletag :capture_log

  test "injects custom env into codex exec processes" do
    script_path =
      temp_script("""
      #!/usr/bin/env bash
      echo "{\\"type\\":\\"turn.completed\\",\\"turn_id\\":\\"turn_env\\",\\"thread_id\\":\\"thread_env\\",\\"final_response\\":{\\"type\\":\\"text\\",\\"text\\":\\"${CUSTOM_ENV}\\"}}"
      """)
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    exec_opts = %{
      codex_opts: codex_opts,
      env: %{"CUSTOM_ENV" => "injected-value"}
    }

    assert {:ok, %{events: events}} = Exec.run("hi", exec_opts)

    assert Enum.any?(events, fn
             %Events.TurnCompleted{final_response: response} ->
               final_text(response) == "injected-value"

             _ ->
               false
           end)
  end

  test "forwards cancellation token flag to codex exec" do
    capture_path =
      Path.join(System.tmp_dir!(), "codex_exec_args_#{System.unique_integer([:positive])}")

    script_path =
      "thread_basic.jsonl"
      |> FixtureScripts.capture_args(capture_path)
      |> tap(fn path ->
        on_exit(fn ->
          File.rm_rf(path)
          File.rm_rf(capture_path)
        end)
      end)

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    exec_opts = %{codex_opts: codex_opts, cancellation_token: "cancel-me"}

    assert {:ok, _} = Exec.run("cancel", exec_opts)

    args =
      capture_path
      |> File.read!()
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    idx = Enum.find_index(args, &(&1 == "--cancellation-token"))
    assert idx
    assert Enum.at(args, idx + 1) == "cancel-me"
  end

  test "forwards exec CLI flags and config overrides" do
    capture_path =
      Path.join(System.tmp_dir!(), "codex_exec_flags_#{System.unique_integer([:positive])}")

    script_path =
      "thread_basic.jsonl"
      |> FixtureScripts.capture_args(capture_path)
      |> tap(fn path ->
        on_exit(fn ->
          File.rm_rf(path)
          File.rm_rf(capture_path)
        end)
      end)

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    {:ok, thread_opts} =
      ThreadOptions.new(%{
        profile: "team",
        oss: true,
        local_provider: "ollama",
        full_auto: true,
        output_last_message: "/tmp/last_message.txt",
        color: :always,
        config_overrides: %{
          "features.web_search_request" => true,
          "model" => "o3"
        }
      })

    thread = Thread.build(codex_opts, thread_opts)

    assert {:ok, _} = Thread.run(thread, "flags")

    args =
      capture_path
      |> File.read!()
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    assert fetch_flag_value(args, "--profile") == "team"

    assert Enum.any?(args, &(&1 == "--oss"))

    assert fetch_flag_value(args, "--local-provider") == "ollama"

    assert Enum.any?(args, &(&1 == "--full-auto"))

    assert fetch_flag_value(args, "--output-last-message") == "/tmp/last_message.txt"

    assert fetch_flag_value(args, "--color") == "always"

    assert "features.web_search_request=true" in flag_values(args, "--config")
    assert ~s(model="o3") in flag_values(args, "--config")
  end

  test "uses --json and omits sandbox and approval policy defaults" do
    capture_path =
      Path.join(System.tmp_dir!(), "codex_exec_json_args_#{System.unique_integer([:positive])}")

    script_path =
      "thread_basic.jsonl"
      |> FixtureScripts.capture_args(capture_path)
      |> tap(fn path ->
        on_exit(fn ->
          File.rm_rf(path)
          File.rm_rf(capture_path)
        end)
      end)

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    {:ok, thread_opts} = ThreadOptions.new(%{})
    thread = Thread.build(codex_opts, thread_opts)

    assert {:ok, _} = Thread.run(thread, "json flags")

    args =
      capture_path
      |> File.read!()
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    assert "--json" in args
    refute "--experimental-json" in args
    refute "--sandbox" in args

    refute Enum.any?(flag_values(args, "--config"), fn value ->
             String.starts_with?(value, "approval_policy=")
           end)
  end

  test "forwards model provider and instruction overrides via config" do
    capture_path =
      Path.join(
        System.tmp_dir!(),
        "codex_exec_override_args_#{System.unique_integer([:positive])}"
      )

    script_path =
      "thread_basic.jsonl"
      |> FixtureScripts.capture_args(capture_path)
      |> tap(fn path ->
        on_exit(fn ->
          File.rm_rf(path)
          File.rm_rf(capture_path)
        end)
      end)

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    {:ok, thread_opts} =
      ThreadOptions.new(%{
        model_provider: "mistral",
        base_instructions: "base",
        developer_instructions: "dev",
        model_reasoning_summary: :concise,
        model_verbosity: :high,
        model_context_window: 8192,
        model_supports_reasoning_summaries: true,
        history_persistence: "local",
        history_max_bytes: 128_000
      })

    thread = Thread.build(codex_opts, thread_opts)

    assert {:ok, _} = Thread.run(thread, "overrides")

    args =
      capture_path
      |> File.read!()
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    configs = flag_values(args, "--config")

    assert ~s(model_provider="mistral") in configs
    assert ~s(base_instructions="base") in configs
    assert ~s(developer_instructions="dev") in configs
    assert ~s(model_reasoning_summary="concise") in configs
    assert ~s(model_verbosity="high") in configs
    assert "model_context_window=8192" in configs
    assert "model_supports_reasoning_summaries=true" in configs
    assert ~s(history.persistence="local") in configs
    assert "history.max_bytes=128000" in configs
  end

  test "forwards provider tuning overrides for model provider" do
    capture_path =
      Path.join(
        System.tmp_dir!(),
        "codex_exec_tuning_args_#{System.unique_integer([:positive])}"
      )

    script_path =
      "thread_basic.jsonl"
      |> FixtureScripts.capture_args(capture_path)
      |> tap(fn path ->
        on_exit(fn ->
          File.rm_rf(path)
          File.rm_rf(capture_path)
        end)
      end)

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    {:ok, thread_opts} =
      ThreadOptions.new(%{
        model_provider: "mistral",
        request_max_retries: 7,
        stream_max_retries: 11,
        stream_idle_timeout_ms: 123_000
      })

    thread = Thread.build(codex_opts, thread_opts)

    assert {:ok, _} = Thread.run(thread, "tuning")

    args =
      capture_path
      |> File.read!()
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    configs = flag_values(args, "--config")

    assert "model_providers.mistral.request_max_retries=7" in configs
    assert "model_providers.mistral.stream_max_retries=11" in configs
    assert "model_providers.mistral.stream_idle_timeout_ms=123000" in configs
  end

  test "forwards sandbox and shell environment policy overrides via config" do
    capture_path =
      Path.join(
        System.tmp_dir!(),
        "codex_exec_policy_args_#{System.unique_integer([:positive])}"
      )

    script_path =
      "thread_basic.jsonl"
      |> FixtureScripts.capture_args(capture_path)
      |> tap(fn path ->
        on_exit(fn ->
          File.rm_rf(path)
          File.rm_rf(capture_path)
        end)
      end)

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    {:ok, thread_opts} =
      ThreadOptions.new(%{
        sandbox_policy: %{
          type: :workspace_write,
          writable_roots: ["/tmp"],
          network_access: false,
          exclude_tmpdir_env_var: true,
          exclude_slash_tmp: true
        },
        shell_environment_policy: %{
          inherit: "core",
          ignore_default_excludes: false,
          exclude: ["AWS_*"],
          include_only: ["PATH"],
          set: %{"FOO" => "bar"}
        }
      })

    thread = Thread.build(codex_opts, thread_opts)

    assert {:ok, _} = Thread.run(thread, "policies")

    args =
      capture_path
      |> File.read!()
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    configs = flag_values(args, "--config")

    assert ~s(sandbox_workspace_write.writable_roots=["/tmp"]) in configs
    assert "sandbox_workspace_write.network_access=false" in configs
    assert "sandbox_workspace_write.exclude_tmpdir_env_var=true" in configs
    assert "sandbox_workspace_write.exclude_slash_tmp=true" in configs
    assert ~s(shell_environment_policy.inherit="core") in configs
    assert "shell_environment_policy.ignore_default_excludes=false" in configs
    assert ~s(shell_environment_policy.exclude=["AWS_*"]) in configs
    assert ~s(shell_environment_policy.include_only=["PATH"]) in configs
    assert ~s(shell_environment_policy.set={"FOO"="bar"}) in configs
  end

  test "enables web search when configured" do
    capture_path =
      Path.join(
        System.tmp_dir!(),
        "codex_exec_web_search_#{System.unique_integer([:positive])}"
      )

    script_path =
      "thread_basic.jsonl"
      |> FixtureScripts.capture_args(capture_path)
      |> tap(fn path ->
        on_exit(fn ->
          File.rm_rf(path)
          File.rm_rf(capture_path)
        end)
      end)

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    {:ok, thread_opts} = ThreadOptions.new(%{web_search_enabled: true})
    thread = Thread.build(codex_opts, thread_opts)

    assert {:ok, _} = Thread.run(thread, "web search")

    args =
      capture_path
      |> File.read!()
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    assert "features.web_search_request=true" in flag_values(args, "--config")
  end

  test "forwards dangerously bypass flag to codex exec" do
    capture_path =
      Path.join(
        System.tmp_dir!(),
        "codex_exec_danger_args_#{System.unique_integer([:positive])}"
      )

    script_path =
      "thread_basic.jsonl"
      |> FixtureScripts.capture_args(capture_path)
      |> tap(fn path ->
        on_exit(fn ->
          File.rm_rf(path)
          File.rm_rf(capture_path)
        end)
      end)

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    {:ok, thread_opts} = ThreadOptions.new(%{dangerously_bypass_approvals_and_sandbox: true})
    thread = Thread.build(codex_opts, thread_opts)

    assert {:ok, _} = Thread.run(thread, "danger")

    args =
      capture_path
      |> File.read!()
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    assert Enum.any?(args, &(&1 == "--dangerously-bypass-approvals-and-sandbox"))
  end

  test "resume args precede image args in built CLI args" do
    capture_path =
      Path.join(
        System.tmp_dir!(),
        "codex_exec_resume_image_#{System.unique_integer([:positive])}"
      )

    script_path =
      "thread_basic.jsonl"
      |> FixtureScripts.capture_args(capture_path)
      |> tap(fn path ->
        on_exit(fn ->
          File.rm_rf(path)
          File.rm_rf(capture_path)
        end)
      end)

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    attachment = %Codex.Files.Attachment{
      id: "att_1",
      name: "test.png",
      path: "/tmp/test.png",
      checksum: "abc",
      size: 100,
      persist: false,
      inserted_at: System.system_time(:millisecond),
      ttl_ms: 86_400_000
    }

    {:ok, thread_opts} = ThreadOptions.new(%{attachments: [attachment]})
    thread = Thread.build(codex_opts, thread_opts, thread_id: "thread_resume_img")

    assert {:ok, _} = Thread.run(thread, "hello")

    args =
      capture_path
      |> File.read!()
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    resume_idx = Enum.find_index(args, &(&1 == "resume"))
    image_idx = Enum.find_index(args, &(&1 == "--image"))

    assert resume_idx, "expected resume arg in: #{inspect(args)}"
    assert image_idx, "expected --image arg in: #{inspect(args)}"
    assert resume_idx < image_idx, "resume (#{resume_idx}) must precede --image (#{image_idx})"
  end

  test "config override precedence: derived < thread < turn (later wins)" do
    capture_path =
      Path.join(
        System.tmp_dir!(),
        "codex_exec_precedence_#{System.unique_integer([:positive])}"
      )

    script_path =
      "thread_basic.jsonl"
      |> FixtureScripts.capture_args(capture_path)
      |> tap(fn path ->
        on_exit(fn ->
          File.rm_rf(path)
          File.rm_rf(capture_path)
        end)
      end)

    {:ok, codex_opts} =
      Options.new(%{
        api_key: "test",
        codex_path_override: script_path,
        model_personality: :friendly
      })

    {:ok, thread_opts} =
      ThreadOptions.new(%{
        personality: :pragmatic,
        config_overrides: [{"model_personality", "none"}]
      })

    thread = Thread.build(codex_opts, thread_opts)

    turn_opts = %{config_overrides: [{"model_personality", "override"}]}

    assert {:ok, _} = Thread.run(thread, "precedence", turn_opts)

    args =
      capture_path
      |> File.read!()
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    personality_configs =
      args
      |> Enum.with_index()
      |> Enum.filter(fn {value, _} -> value == "--config" end)
      |> Enum.map(fn {_, idx} -> Enum.at(args, idx + 1) end)
      |> Enum.filter(&String.starts_with?(&1, "model_personality="))

    # All three layers should emit their value; last one wins with the CLI
    assert length(personality_configs) >= 2,
           "expected multiple model_personality overrides, got: #{inspect(personality_configs)}"

    # The last emitted value should be the turn-level override (highest precedence)
    assert List.last(personality_configs) == ~s(model_personality="override")
  end

  test "auto-flattens nested config override maps in turn opts" do
    capture_path =
      Path.join(
        System.tmp_dir!(),
        "codex_exec_flatten_#{System.unique_integer([:positive])}"
      )

    script_path =
      "thread_basic.jsonl"
      |> FixtureScripts.capture_args(capture_path)
      |> tap(fn path ->
        on_exit(fn ->
          File.rm_rf(path)
          File.rm_rf(capture_path)
        end)
      end)

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    {:ok, thread_opts} = ThreadOptions.new(%{})
    thread = Thread.build(codex_opts, thread_opts)

    turn_opts = %{
      config_overrides: %{
        "model" => %{"personality" => "friendly"},
        "timeout" => 5000
      }
    }

    assert {:ok, _} = Thread.run(thread, "flatten", turn_opts)

    args =
      capture_path
      |> File.read!()
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    configs = flag_values(args, "--config")

    assert ~s(model.personality="friendly") in configs
    assert "timeout=5000" in configs
  end

  test "runs exec review subcommand" do
    capture_path =
      Path.join(System.tmp_dir!(), "codex_exec_review_args_#{System.unique_integer([:positive])}")

    script_path =
      "thread_basic.jsonl"
      |> FixtureScripts.capture_args(capture_path)
      |> tap(fn path ->
        on_exit(fn ->
          File.rm_rf(path)
          File.rm_rf(capture_path)
        end)
      end)

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    assert {:ok, _} =
             Exec.review({:base_branch, "main"}, %{codex_opts: codex_opts, timeout_ms: 1_000})

    args =
      capture_path
      |> File.read!()
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    assert Enum.any?(args, &(&1 == "review"))

    assert fetch_flag_value(args, "--base") == "main"
  end

  test "stream idle timeout raises retryable transport error" do
    script_path =
      temp_script("""
      #!/usr/bin/env bash
      sleep 0.3
      """)
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    exec_opts = %{
      codex_opts: codex_opts,
      stream_idle_timeout_ms: 100
    }

    {:ok, stream} = Exec.run_stream("idle", exec_opts)

    error =
      try do
        Enum.to_list(stream)
        flunk("expected idle timeout")
      rescue
        error in Codex.TransportError -> error
      end

    assert error.retryable? == true
    assert error.message =~ "idle timeout"
  end

  test "emits clarified timeout error when exec stalls" do
    script_path =
      temp_script("""
      #!/usr/bin/env bash
      sleep 0.2
      echo "{\\"type\\":\\"turn.completed\\",\\"turn_id\\":\\"turn_timeout\\",\\"thread_id\\":\\"thread_timeout\\"}"
      """)
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    exec_opts = %{codex_opts: codex_opts, timeout_ms: 50}

    log =
      capture_log(fn ->
        assert {:error, {:codex_timeout, 50}} = Exec.run("stall", exec_opts)
      end)

    assert log =~ "codex exec timed out"
    assert log =~ "50"
  end

  defp final_text(%Items.AgentMessage{text: text}), do: text
  defp final_text(%{"text" => text}), do: text
  defp final_text(%{text: text}), do: text
  defp final_text(_other), do: nil

  defp fetch_flag_value(args, flag) do
    case Enum.find_index(args, &(&1 == flag)) do
      nil -> nil
      idx -> Enum.at(args, idx + 1)
    end
  end

  defp flag_values(args, flag) do
    args
    |> Enum.with_index()
    |> Enum.filter(fn {value, _idx} -> value == flag end)
    |> Enum.map(fn {_value, idx} -> Enum.at(args, idx + 1) end)
  end

  defp temp_script(contents) do
    path = Path.join(System.tmp_dir!(), "codex_exec_#{System.unique_integer([:positive])}")
    File.write!(path, contents)
    File.chmod!(path, 0o755)
    path
  end
end

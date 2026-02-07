defmodule Codex.ThreadTest do
  use ExUnit.Case, async: true

  alias Codex.Events
  alias Codex.Protocol.RateLimit.Snapshot, as: RateLimitSnapshot
  alias Codex.TestSupport.FixtureScripts
  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.Turn.Result, as: TurnResult

  alias Codex.{
    Error,
    GuardrailError,
    Items,
    Options,
    RunResultStreaming,
    Thread,
    ToolGuardrail,
    Tools
  }

  describe "thread options validation" do
    test "rejects conflicting auto flags" do
      assert {:error, :conflicting_auto_flags} ==
               ThreadOptions.new(%{
                 full_auto: true,
                 dangerously_bypass_approvals_and_sandbox: true
               })
    end

    test "accepts reasoning, tuning, and retry options" do
      {:ok, opts} =
        ThreadOptions.new(%{
          model_reasoning_summary: :detailed,
          model_verbosity: :low,
          model_context_window: 4096,
          model_supports_reasoning_summaries: true,
          history_persistence: "local",
          history_max_bytes: 50_000,
          request_max_retries: 3,
          stream_max_retries: 5,
          stream_idle_timeout_ms: 10_000,
          shell_environment_policy: %{
            inherit: "core",
            exclude: ["AWS_*"],
            set: %{"FOO" => "bar"}
          },
          retry: true,
          retry_opts: [max_attempts: 2],
          rate_limit: true,
          rate_limit_opts: [max_attempts: 2]
        })

      assert opts.model_reasoning_summary == "detailed"
      assert opts.model_verbosity == "low"
      assert opts.model_context_window == 4096
      assert opts.model_supports_reasoning_summaries == true
      assert opts.history_persistence == "local"
      assert opts.history_max_bytes == 50_000
      assert opts.request_max_retries == 3
      assert opts.stream_max_retries == 5
      assert opts.stream_idle_timeout_ms == 10_000
      assert opts.retry == true
      assert opts.retry_opts == [max_attempts: 2]
      assert opts.rate_limit == true
      assert opts.rate_limit_opts == [max_attempts: 2]
    end

    test "accepts none personality" do
      {:ok, opts} = ThreadOptions.new(%{personality: :none})
      assert opts.personality == :none

      {:ok, opts} = ThreadOptions.new(%{personality: "none"})
      assert opts.personality == :none
    end

    test "rejects invalid shell environment policy" do
      assert {:error, {:invalid_shell_environment_set, _}} =
               ThreadOptions.new(%{
                 shell_environment_policy: %{set: %{"FOO" => 1}}
               })
    end
  end

  describe "build/3" do
    test "does not monitor app_server transports" do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(pid, :kill) end)

      {:ok, codex_opts} = Options.new(%{api_key: "test"})
      {:ok, thread_opts} = ThreadOptions.new(%{transport: {:app_server, pid}})

      {:monitors, before_monitors} = Process.info(self(), :monitors)

      thread = Thread.build(codex_opts, thread_opts)

      {:monitors, after_monitors} = Process.info(self(), :monitors)

      assert after_monitors == before_monitors
      assert thread.transport_ref == nil
    end

    test "clear_pending_tool_payloads/1 clears pending tool fields" do
      {:ok, codex_opts} = Options.new(%{api_key: "test"})
      {:ok, thread_opts} = ThreadOptions.new(%{})

      thread =
        Thread.build(codex_opts, thread_opts,
          pending_tool_outputs: [%{call_id: "tool-1", output: %{"ok" => true}}],
          pending_tool_failures: [%{call_id: "tool-2", error: %{"message" => "failed"}}]
        )

      cleared = Thread.clear_pending_tool_payloads(thread)

      assert cleared.pending_tool_outputs == []
      assert cleared.pending_tool_failures == []
      assert cleared.thread_id == thread.thread_id
      assert cleared.codex_opts == thread.codex_opts
    end
  end

  describe "run/3" do
    test "returns turn result and updates thread metadata" do
      codex_path =
        "thread_basic.jsonl"
        |> FixtureScripts.cat_fixture()
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: codex_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      {:ok, result} = Thread.run(thread, "Hello Codex")

      assert result.thread.thread_id == "thread_abc123"
      assert %Items.AgentMessage{text: "Hello from Python Codex!"} = result.final_response

      assert result.usage == %{
               "input_tokens" => 12,
               "cached_input_tokens" => 0,
               "output_tokens" => 9,
               "total_tokens" => 21
             }

      assert length(result.events) == 5
    end

    test "passes default model and reasoning effort to codex exec" do
      capture_path =
        Path.join(
          System.tmp_dir!(),
          "codex_exec_model_args_#{System.unique_integer([:positive])}"
        )

      script_path =
        "thread_basic.jsonl"
        |> FixtureScripts.capture_args(capture_path)
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      on_exit(fn -> File.rm_rf(capture_path) end)

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: script_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      {:ok, _result} = Thread.run(thread, "Model defaults")

      args =
        capture_path
        |> File.read!()
        |> String.trim()
        |> String.split(~r/\s+/)

      assert Enum.chunk_every(args, 2)
             |> Enum.any?(fn
               ["--model", "gpt-5.3-codex"] -> true
               _ -> false
             end)

      assert Enum.chunk_every(args, 2)
             |> Enum.any?(fn
               ["--config", ~s(model_reasoning_effort="medium")] -> true
               _ -> false
             end)
    end

    test "writes output schema to temp file and passes flag to exec" do
      capture_path =
        Path.join(
          System.tmp_dir!(),
          "codex_exec_schema_args_#{System.unique_integer([:positive])}"
        )

      script_path =
        "thread_basic.jsonl"
        |> FixtureScripts.capture_args(capture_path)
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      on_exit(fn -> File.rm_rf(capture_path) end)

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: script_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      schema = %{
        "type" => "object",
        "properties" => %{"status" => %{"type" => "string"}},
        "required" => ["status"]
      }

      assert {:ok, _result} =
               Thread.run(thread, "Provide status", %{output_schema: schema})

      args =
        capture_path
        |> File.read!()
        |> String.trim()
        |> String.split(~r/\s+/)

      assert Enum.any?(args, &(&1 == "--output-schema"))

      schema_index = Enum.find_index(args, &(&1 == "--output-schema"))
      schema_path = Enum.at(args, schema_index + 1)
      assert schema_path
      refute File.exists?(schema_path)
    end

    test "uses thread output_schema when turn opts omit output_schema" do
      capture_path =
        Path.join(
          System.tmp_dir!(),
          "codex_exec_schema_thread_#{System.unique_integer([:positive])}"
        )

      script_path =
        "thread_basic.jsonl"
        |> FixtureScripts.capture_args(capture_path)
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      on_exit(fn -> File.rm_rf(capture_path) end)

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: script_path
        })

      schema = %{"type" => "object", "properties" => %{"ok" => %{"type" => "boolean"}}}
      {:ok, thread_opts} = ThreadOptions.new(%{output_schema: schema})
      thread = Thread.build(codex_opts, thread_opts)

      assert {:ok, _result} = Thread.run(thread, "Provide status")

      args =
        capture_path
        |> File.read!()
        |> String.trim()
        |> String.split(~r/\s+/)

      assert Enum.any?(args, &(&1 == "--output-schema"))
    end

    test "decodes structured output when schema is provided" do
      codex_path =
        "thread_structured.jsonl"
        |> FixtureScripts.cat_fixture()
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: codex_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      schema = %{
        "type" => "object",
        "properties" => %{
          "status" => %{"type" => "string"},
          "count" => %{"type" => "integer"}
        },
        "required" => ["status", "count"]
      }

      {:ok, result} = Thread.run(thread, "Generate structured output", %{output_schema: schema})

      assert %Items.AgentMessage{
               text: "{\"status\":\"ok\",\"count\":2}",
               parsed: %{"status" => "ok", "count" => 2}
             } = result.final_response

      assert {:ok, %{"status" => "ok", "count" => 2}} = TurnResult.json(result)
    end

    test "retains raw text and surfaces decode error when structured output is invalid" do
      codex_path =
        "thread_structured_invalid.jsonl"
        |> FixtureScripts.cat_fixture()
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: codex_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      schema = %{"type" => "object"}

      {:ok, result} = Thread.run(thread, "Generate structured output", %{output_schema: schema})

      assert %Items.AgentMessage{text: "not-json", parsed: nil} = result.final_response
      assert {:error, {:invalid_json, _}} = TurnResult.json(result)
    end

    test "does not decode structured payload when schema is absent" do
      codex_path =
        "thread_structured.jsonl"
        |> FixtureScripts.cat_fixture()
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: codex_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      {:ok, result} = Thread.run(thread, "Generate structured output")

      assert %Items.AgentMessage{text: "{\"status\":\"ok\",\"count\":2}", parsed: nil} =
               result.final_response

      assert {:error, :not_structured} = TurnResult.json(result)
    end

    test "captures token usage updates and turn diffs" do
      codex_path =
        "thread_usage_events.jsonl"
        |> FixtureScripts.cat_fixture()
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: codex_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      {:ok, result} = Thread.run(thread, "Track usage")

      assert %Items.AgentMessage{text: "Usage tracked"} = result.final_response

      assert %{
               "input_tokens" => 100,
               "cached_input_tokens" => 10,
               "output_tokens" => 0,
               "total_tokens" => 110
             } = result.usage

      assert result.thread.usage == result.usage

      assert Enum.any?(result.events, &match?(%Events.ThreadTokenUsageUpdated{}, &1))
      assert Enum.any?(result.events, &match?(%Events.TurnDiffUpdated{}, &1))
      assert Enum.any?(result.events, &match?(%Events.TurnCompaction{}, &1))
    end

    test "merges usage deltas and compaction updates into thread usage" do
      codex_path =
        "thread_usage_compaction.jsonl"
        |> FixtureScripts.cat_fixture()
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: codex_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      {:ok, result} = Thread.run(thread, "Track compaction usage")

      assert %Items.AgentMessage{text: "Usage + compaction tracked"} = result.final_response

      assert %{
               "input_tokens" => 150,
               "cached_input_tokens" => 10,
               "output_tokens" => 25,
               "total_tokens" => 185,
               "reasoning_output_tokens" => 20
             } = result.usage

      assert result.thread.usage == result.usage

      assert Enum.any?(result.events, fn
               %Events.TurnCompaction{compaction: %{"usage_delta" => _}, stage: :completed} ->
                 true

               _ ->
                 false
             end)

      assert Enum.any?(result.events, &match?(%Events.ThreadTokenUsageUpdated{}, &1))
    end

    test "parses MCP tool calls with arguments, streamed results, and git metadata" do
      codex_path =
        "thread_mcp_rich.jsonl"
        |> FixtureScripts.cat_fixture()
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: codex_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      {:ok, result} = Thread.run(thread, "Check MCP call")

      assert get_in(result.thread.metadata, ["git", "branch"]) == "feature/mcp-updates"

      assert Enum.any?(result.events, fn
               %Events.ItemUpdated{
                 item: %Items.McpToolCall{
                   arguments: %{"path" => "/tmp"},
                   result: %{
                     "content" => [%{"text" => "listing..."}],
                     "structured_content" => nil
                   },
                   status: :in_progress
                 }
               } ->
                 true

               _ ->
                 false
             end)

      assert Enum.any?(result.events, fn
               %Events.ItemCompleted{
                 item: %Items.McpToolCall{
                   arguments: %{"path" => "/tmp"},
                   result: %{
                     "content" => [%{"text" => "ok"}],
                     "structured_content" => %{"entries" => 3}
                   },
                   status: :completed
                 }
               } ->
                 true

               _ ->
                 false
             end)

      assert Enum.any?(result.events, fn
               %Events.ItemCompleted{item: %Items.CommandExecution{status: :declined}} -> true
               _ -> false
             end)
    end
  end

  describe "run_streamed/3" do
    test "lazy stream yields events" do
      codex_path =
        "thread_basic.jsonl"
        |> FixtureScripts.cat_fixture()
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: codex_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      {:ok, result} = Thread.run_streamed(thread, "Hello")

      events = result |> RunResultStreaming.raw_events() |> Enum.to_list()
      assert length(events) == 5
      assert Enum.any?(events, &match?(%Events.TurnCompleted{}, &1))
    end

    test "structured output stream items include parsed payload" do
      codex_path =
        "thread_structured.jsonl"
        |> FixtureScripts.cat_fixture()
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: codex_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      schema = %{"type" => "object"}

      {:ok, result} = Thread.run_streamed(thread, "Stream structured", %{output_schema: schema})

      events = result |> RunResultStreaming.raw_events() |> Enum.to_list()

      assert Enum.any?(events, fn
               %Events.ItemCompleted{item: %Items.AgentMessage{parsed: %{"status" => "ok"}}} ->
                 true

               _ ->
                 false
             end)

      assert Enum.any?(events, fn
               %Events.TurnCompleted{final_response: %Items.AgentMessage{parsed: %{"count" => 2}}} ->
                 true

               _ ->
                 false
             end)
    end

    test "streams usage, diff, and compaction updates" do
      codex_path =
        "thread_usage_events.jsonl"
        |> FixtureScripts.cat_fixture()
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: codex_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      {:ok, result} = Thread.run_streamed(thread, "Watch usage")
      events = result |> RunResultStreaming.raw_events() |> Enum.to_list()

      assert Enum.any?(events, &match?(%Events.ThreadTokenUsageUpdated{}, &1))

      assert Enum.any?(events, fn
               %Events.TurnDiffUpdated{thread_id: "thread_usage", turn_id: "turn_usage"} -> true
               _ -> false
             end)

      assert Enum.any?(events, &match?(%Events.TurnCompaction{stage: :completed}, &1))
    end

    test "streams MCP tool call payloads with arguments and results" do
      codex_path =
        "thread_mcp_rich.jsonl"
        |> FixtureScripts.cat_fixture()
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: codex_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      {:ok, result} = Thread.run_streamed(thread, "Stream MCP")
      events = result |> RunResultStreaming.raw_events() |> Enum.to_list()

      assert Enum.any?(events, fn
               %Events.ItemStarted{
                 item: %Items.McpToolCall{arguments: %{"path" => "/tmp"}, status: :in_progress}
               } ->
                 true

               _ ->
                 false
             end)

      assert Enum.any?(events, fn
               %Events.ItemCompleted{
                 item: %Items.McpToolCall{
                   result: %{"structured_content" => %{"entries" => 3}}
                 }
               } ->
                 true

               _ ->
                 false
             end)
    end
  end

  describe "conversation lifecycle" do
    test "/new resets the conversation and clears existing thread_id" do
      capture_path =
        Path.join(System.tmp_dir!(), "codex_exec_new_args_#{System.unique_integer([:positive])}")

      script_path =
        "thread_new_command.jsonl"
        |> FixtureScripts.capture_args(capture_path)
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      on_exit(fn -> File.rm_rf(capture_path) end)

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: script_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})

      thread =
        Thread.build(codex_opts, thread_opts,
          thread_id: "thread_old",
          labels: %{topic: "legacy"}
        )

      {:ok, result} = Thread.run(thread, "/new")

      args =
        capture_path
        |> File.read!()
        |> String.trim()
        |> String.split(~r/\s+/)

      refute Enum.any?(args, &(&1 == "--thread-id"))

      assert %Items.AgentMessage{text: "Started fresh conversation"} = result.final_response
      assert result.thread.thread_id == "thread_new_123"
      assert result.thread.labels == %{"topic" => "reset"}
      assert result.thread.metadata["labels"] == %{"topic" => "reset"}
    end

    test "does not persist thread_id when turn exits early" do
      codex_path =
        "thread_early_exit.jsonl"
        |> FixtureScripts.cat_fixture()
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: codex_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})

      thread =
        Thread.build(codex_opts, thread_opts,
          thread_id: "thread_stale",
          labels: %{topic: "should_reset"}
        )

      {:ok, result} = Thread.run(thread, "abort mission")

      assert %Items.AgentMessage{text: "Session exited before start"} = result.final_response
      assert result.thread.thread_id == nil
      assert result.thread.labels == %{}
    end

    test "resumes existing conversation using resume subcommand" do
      capture_path =
        Path.join(
          System.tmp_dir!(),
          "codex_exec_resume_args_#{System.unique_integer([:positive])}"
        )

      script_path =
        "thread_basic.jsonl"
        |> FixtureScripts.capture_args(capture_path)
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      on_exit(fn -> File.rm_rf(capture_path) end)

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: script_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})

      thread =
        Thread.build(codex_opts, thread_opts, thread_id: "thread_resume")

      {:ok, _result} = Thread.run(thread, "continue")

      raw_args = capture_path |> File.read!() |> String.trim()

      refute String.contains?(raw_args, "--thread-id")

      assert String.contains?(raw_args, "resume thread_resume"),
             "expected resume subcommand in args: #{inspect(raw_args)}"
    end

    test "resumes most recent conversation using resume --last" do
      capture_path =
        Path.join(
          System.tmp_dir!(),
          "codex_exec_resume_last_args_#{System.unique_integer([:positive])}"
        )

      script_path =
        "thread_basic.jsonl"
        |> FixtureScripts.capture_args(capture_path)
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      on_exit(fn -> File.rm_rf(capture_path) end)

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: script_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      {:ok, thread} = Codex.resume_thread(:last, codex_opts, thread_opts)

      {:ok, _result} = Thread.run(thread, "continue")

      raw_args = capture_path |> File.read!() |> String.trim()

      assert String.contains?(raw_args, "resume --last"),
             "expected resume --last in args: #{inspect(raw_args)}"
    end
  end

  describe "turn failures" do
    test "normalizes rate limit failures into Codex.Error" do
      codex_path =
        "thread_error_rate_limit.jsonl"
        |> FixtureScripts.cat_fixture()
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: codex_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      assert {:error, {:turn_failed, %Error{} = error}} =
               Thread.run(thread, "trigger rate limit")

      assert error.kind == :rate_limit
      assert error.message == "Azure OpenAI rate limit hit"
      assert error.details[:code] == "rate_limit_exceeded"
      assert error.details[:status] == 429
      assert error.details[:retry_after] == 15
    end

    test "parses sandbox assessment failures with nested details" do
      codex_path =
        "thread_error_sandbox_assessment.jsonl"
        |> FixtureScripts.cat_fixture()
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: codex_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      assert {:error, {:turn_failed, %Error{} = error}} =
               Thread.run(thread, "trigger sandbox assessment")

      assert error.kind == :sandbox_assessment_failed
      assert error.message =~ "Sandbox assessment rejected command"
      assert error.details[:code] == "sandbox_assessment_failed"
      assert error.details[:type] == "sandbox_assessment"

      assert %{
               "command" => "rm -rf /",
               "assessment" => %{"status" => "blocked", "reason" => "dangerous_command"}
             } = error.details[:details]
    end
  end

  describe "rate limits" do
    test "stores account rate limit snapshots on the thread" do
      {:ok, codex_opts} = Options.new(%{api_key: "test"})
      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      rate_limits =
        RateLimitSnapshot.from_map(%{
          "primary" => %{"usedPercent" => 10.0}
        })

      event = %Events.AccountRateLimitsUpdated{thread_id: "thread_1", rate_limits: rate_limits}

      {updated, _response, _usage} = Thread.reduce_events(thread, [event], %{})

      assert updated.rate_limits == rate_limits
      assert Thread.rate_limits(updated) == rate_limits
    end

    test "stores token usage rate limits on the thread" do
      {:ok, codex_opts} = Options.new(%{api_key: "test"})
      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      rate_limits =
        RateLimitSnapshot.from_map(%{
          "primary" => %{"usedPercent" => 5.0}
        })

      event = %Events.ThreadTokenUsageUpdated{rate_limits: rate_limits, usage: %{}, delta: nil}

      {updated, _response, _usage} = Thread.reduce_events(thread, [event], %{})

      assert updated.rate_limits == rate_limits
      assert Thread.rate_limits(updated) == rate_limits
    end

    test "session configured updates model and coerces reasoning effort" do
      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          model: "gpt-5.3-codex",
          reasoning_effort: :xhigh
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      event = %Events.SessionConfigured{
        model: "gpt-5.1-codex-mini",
        reasoning_effort: "xhigh"
      }

      {updated, _response, _usage} = Thread.reduce_events(thread, [event], %{})

      assert updated.codex_opts.model == "gpt-5.1-codex-mini"
      assert updated.codex_opts.reasoning_effort == :high
    end
  end

  describe "tool output forwarding" do
    test "does not forward pending tool outputs and failures to codex exec" do
      capture_path =
        Path.join(System.tmp_dir!(), "codex_exec_tool_args_#{System.unique_integer([:positive])}")

      script_path =
        "thread_basic.jsonl"
        |> FixtureScripts.capture_args(capture_path)
        |> tap(&on_exit(fn -> File.rm_rf(&1) end))

      on_exit(fn -> File.rm_rf(capture_path) end)

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: script_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})

      thread =
        Thread.build(codex_opts, thread_opts,
          pending_tool_outputs: [%{call_id: "call-output", output: %{"sum" => 9}}],
          pending_tool_failures: [%{call_id: "call-failure", reason: %{message: "boom"}}]
        )

      {:ok, result} = Thread.run(thread, "Continue turn")

      args =
        capture_path
        |> File.read!()
        |> String.trim()
        |> String.split(~r/\s+/)

      refute "--tool-output" in args
      refute "--tool-failure" in args

      assert result.thread.pending_tool_outputs == []
      assert result.thread.pending_tool_failures == []
    end
  end

  defmodule DedupTool do
    @behaviour Codex.Tool

    @impl true
    def metadata, do: %{name: "dedup_tool", description: "noop"}

    @impl true
    def invoke(_args, %{thread: %{thread_opts: %{metadata: %{parent: parent}}}}) do
      send(parent, :tool_invoked)
      {:ok, %{"status" => "ok"}}
    end
  end

  describe "handle_tool_requests/3" do
    setup do
      Tools.reset!()
      Tools.reset_metrics()

      {:ok, _} = Tools.register(DedupTool, name: "dedup_tool")

      {:ok, codex_opts} = Options.new(%{api_key: "test"})
      {:ok, thread_opts} = ThreadOptions.new(%{metadata: %{parent: self()}})

      thread = Thread.build(codex_opts, thread_opts)

      %{thread: thread}
    end

    test "skips duplicate tool outputs when already present", %{thread: thread} do
      existing = %{call_id: "call-1", tool_name: "dedup_tool", output: %{"cached" => true}}

      event = %Events.ToolCallRequested{
        thread_id: "thread_dup",
        turn_id: "turn_dup",
        call_id: "call-1",
        tool_name: "dedup_tool",
        arguments: %{}
      }

      result = %TurnResult{
        thread: %{thread | pending_tool_outputs: [existing]},
        events: [event],
        final_response: nil,
        usage: %{},
        raw: %{tool_outputs: [existing]}
      }

      assert {:ok, updated} = Thread.handle_tool_requests(result, 1, %{})

      assert updated.raw.tool_outputs == [existing]
      assert updated.thread.pending_tool_outputs == [existing]
      refute_receive :tool_invoked
    end

    test "invokes distinct tool calls when call_id is missing", %{thread: thread} do
      event_one = %Events.ToolCallRequested{
        thread_id: "thread_nil",
        turn_id: "turn_nil",
        call_id: nil,
        tool_name: "dedup_tool",
        arguments: %{"value" => 1}
      }

      event_two = %Events.ToolCallRequested{
        thread_id: "thread_nil",
        turn_id: "turn_nil",
        call_id: nil,
        tool_name: "dedup_tool",
        arguments: %{"value" => 2}
      }

      result = %TurnResult{
        thread: thread,
        events: [event_one, event_two],
        final_response: nil,
        usage: %{},
        raw: %{}
      }

      assert {:ok, updated} = Thread.handle_tool_requests(result, 1, %{})

      assert_receive :tool_invoked
      assert_receive :tool_invoked
      refute_receive :tool_invoked

      assert length(updated.raw.tool_outputs) == 2
    end

    test "reject_content guardrail returns tool output without invoking tool", %{thread: thread} do
      guardrail =
        ToolGuardrail.new(
          name: "reject_content_guardrail",
          behavior: :reject_content,
          handler: fn _event, _payload, _context -> {:reject, "blocked"} end
        )

      event = %Events.ToolCallRequested{
        thread_id: "thread_guardrail",
        turn_id: "turn_guardrail",
        call_id: "call_guardrail",
        tool_name: "dedup_tool",
        arguments: %{}
      }

      result = %TurnResult{
        thread: thread,
        events: [event],
        final_response: nil,
        usage: %{},
        raw: %{}
      }

      assert {:ok, updated} = Thread.handle_tool_requests(result, 1, %{tool_input: [guardrail]})

      assert [%{output: output}] = updated.raw.tool_outputs
      assert output == %{"type" => "input_text", "text" => "blocked"}
      refute_receive :tool_invoked
    end

    test "raise_exception guardrail treats reject as tripwire", %{thread: thread} do
      guardrail =
        ToolGuardrail.new(
          name: "raise_guardrail",
          behavior: :raise_exception,
          handler: fn _event, _payload, _context -> {:reject, "blocked"} end
        )

      event = %Events.ToolCallRequested{
        thread_id: "thread_guardrail",
        turn_id: "turn_guardrail",
        call_id: "call_guardrail",
        tool_name: "dedup_tool",
        arguments: %{}
      }

      result = %TurnResult{
        thread: thread,
        events: [event],
        final_response: nil,
        usage: %{},
        raw: %{}
      }

      assert {:error, %GuardrailError{guardrail: "raise_guardrail", type: :tripwire}} =
               Thread.handle_tool_requests(result, 1, %{tool_input: [guardrail]})

      refute_receive :tool_invoked
    end

    test "run_in_parallel tool guardrails enforce rejections", %{thread: thread} do
      guardrail =
        ToolGuardrail.new(
          name: "parallel_guardrail",
          run_in_parallel: true,
          handler: fn _event, _payload, _context -> {:reject, "blocked"} end
        )

      event = %Events.ToolCallRequested{
        thread_id: "thread_guardrail",
        turn_id: "turn_guardrail",
        call_id: "call_guardrail",
        tool_name: "dedup_tool",
        arguments: %{}
      }

      result = %TurnResult{
        thread: thread,
        events: [event],
        final_response: nil,
        usage: %{},
        raw: %{}
      }

      assert {:error, %GuardrailError{guardrail: "parallel_guardrail", type: :reject}} =
               Thread.handle_tool_requests(result, 1, %{tool_input: [guardrail]})

      refute_receive :tool_invoked
    end

    test "returns guardrail errors when tool guardrail handlers raise", %{thread: thread} do
      guardrail =
        ToolGuardrail.new(
          name: "boom_guardrail",
          handler: fn _event, _payload, _context -> raise "boom" end
        )

      event = %Events.ToolCallRequested{
        thread_id: "thread_guardrail",
        turn_id: "turn_guardrail",
        call_id: "call_guardrail",
        tool_name: "dedup_tool",
        arguments: %{}
      }

      result = %TurnResult{
        thread: thread,
        events: [event],
        final_response: nil,
        usage: %{},
        raw: %{}
      }

      assert {:error, %GuardrailError{guardrail: "boom_guardrail", stage: :tool_input}} =
               Thread.handle_tool_requests(result, 1, %{tool_input: [guardrail]})

      refute_receive :tool_invoked
    end

    test "returns guardrail errors when tool guardrail hooks raise", %{thread: thread} do
      guardrail =
        ToolGuardrail.new(
          name: "hook_guardrail",
          handler: fn _event, _payload, _context -> :ok end
        )

      event = %Events.ToolCallRequested{
        thread_id: "thread_guardrail",
        turn_id: "turn_guardrail",
        call_id: "call_guardrail",
        tool_name: "dedup_tool",
        arguments: %{}
      }

      result = %TurnResult{
        thread: thread,
        events: [event],
        final_response: nil,
        usage: %{},
        raw: %{}
      }

      hooks = %{
        on_guardrail: fn _stage, _guardrail, _result, _message -> raise "hook boom" end
      }

      assert {:error, %GuardrailError{guardrail: "hook_guardrail", stage: :tool_input}} =
               Thread.handle_tool_requests(result, 1, %{tool_input: [guardrail], hooks: hooks})

      refute_receive :tool_invoked
    end

    test "returns approval hook errors without crashing", %{thread: thread} do
      event = %Events.ToolCallRequested{
        thread_id: "thread_approval",
        turn_id: "turn_approval",
        call_id: "call_approval",
        tool_name: "dedup_tool",
        arguments: %{}
      }

      result = %TurnResult{
        thread: thread,
        events: [event],
        final_response: nil,
        usage: %{},
        raw: %{}
      }

      hooks = %{
        on_approval: fn _event, _decision, _reason -> raise "approval boom" end
      }

      assert {:error, %Error{kind: :approval_hook_failed}} =
               Thread.handle_tool_requests(result, 1, %{hooks: hooks})

      refute_receive :tool_invoked
    end
  end
end

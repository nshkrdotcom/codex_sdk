defmodule Codex.ThreadTest do
  use ExUnit.Case, async: true

  alias Codex.Events
  alias Codex.{Error, Items, Options, RunResultStreaming, Thread, Tools}
  alias Codex.TestSupport.FixtureScripts
  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.Turn.Result, as: TurnResult

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
               ["--model", "gpt-5.1-codex-max"] -> true
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
    def invoke(_args, %{metadata: %{parent: parent}}) do
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
  end
end

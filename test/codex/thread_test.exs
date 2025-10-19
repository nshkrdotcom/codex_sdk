defmodule Codex.ThreadTest do
  use ExUnit.Case, async: true

  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.Events
  alias Codex.{Items, Options, Thread}
  alias Codex.Turn.Result, as: TurnResult
  alias Codex.TestSupport.FixtureScripts

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

      {:ok, stream} = Thread.run_streamed(thread, "Hello")

      assert is_function(stream, 2)
      events = Enum.to_list(stream)
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

      {:ok, stream} = Thread.run_streamed(thread, "Stream structured", %{output_schema: schema})

      events = Enum.to_list(stream)

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
  end

  describe "tool output forwarding" do
    test "forwards pending tool outputs and failures to codex exec" do
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

      output_index = Enum.find_index(args, &(&1 == "--tool-output"))
      refute is_nil(output_index), "expected --tool-output flag in #{inspect(args)}"

      failure_index = Enum.find_index(args, &(&1 == "--tool-failure"))
      refute is_nil(failure_index), "expected --tool-failure flag in #{inspect(args)}"

      output_payload =
        args
        |> Enum.at(output_index + 1)
        |> Jason.decode!()

      failure_payload =
        args
        |> Enum.at(failure_index + 1)
        |> Jason.decode!()

      assert output_payload == %{"call_id" => "call-output", "output" => %{"sum" => 9}}

      assert failure_payload == %{
               "call_id" => "call-failure",
               "reason" => %{"message" => "boom"}
             }

      assert result.thread.pending_tool_outputs == []
      assert result.thread.pending_tool_failures == []
    end
  end
end

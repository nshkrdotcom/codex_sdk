defmodule Codex.AgentRunnerStreamedTest do
  use ExUnit.Case, async: false

  alias Codex.Agent
  alias Codex.AgentRunner
  alias Codex.Events
  alias Codex.Guardrail
  alias Codex.Options
  alias Codex.RunResultStreaming
  alias Codex.StreamEvent.{AgentUpdated, GuardrailResult, RawResponses, RunItem}
  alias Codex.TestSupport.FixtureScripts
  alias Codex.Thread
  alias Codex.Thread.Options, as: ThreadOptions

  setup do
    {:ok, thread_opts} = ThreadOptions.new(%{})
    %{thread_opts: thread_opts}
  end

  test "streams semantic events with agent update and raw compatibility", %{
    thread_opts: thread_opts
  } do
    script_path =
      "thread_basic.jsonl"
      |> FixtureScripts.cat_fixture()
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} =
      Options.new(%{
        api_key: "test",
        codex_path_override: script_path
      })

    thread = Thread.build(codex_opts, thread_opts)

    {:ok, result} =
      AgentRunner.run_streamed(thread, "Hello streaming", %{
        agent: %{name: "helper"}
      })

    semantic_events = result |> RunResultStreaming.events() |> Enum.to_list()

    raw_events =
      semantic_events
      |> Enum.flat_map(fn
        %RunItem{event: event} -> [event]
        _ -> []
      end)

    assert [%AgentUpdated{agent: %Agent{name: "helper"}} | _] = semantic_events
    assert Enum.any?(semantic_events, &match?(%RunItem{event: %Events.ThreadStarted{}}, &1))

    assert Enum.any?(semantic_events, fn
             %RawResponses{events: events} -> events != []
             _ -> false
           end)

    assert Enum.any?(raw_events, &match?(%Events.TurnCompleted{}, &1))
    assert length(raw_events) == 5

    assert RunResultStreaming.usage(result) == %{
             "input_tokens" => 12,
             "cached_input_tokens" => 0,
             "output_tokens" => 9,
             "total_tokens" => 21
           }
  end

  test "after_turn cancellation stops before next continuation", %{thread_opts: thread_opts} do
    {script_path, state_file} =
      FixtureScripts.sequential_fixtures([
        "thread_auto_run_step1.jsonl",
        "thread_auto_run_step2.jsonl"
      ])

    on_exit(fn ->
      File.rm_rf(script_path)
      File.rm_rf(state_file)
    end)

    {:ok, codex_opts} =
      Options.new(%{
        api_key: "test",
        codex_path_override: script_path
      })

    thread = Thread.build(codex_opts, thread_opts)

    {:ok, result} = AgentRunner.run_streamed(thread, "stop after first", %{max_turns: 3})

    RunResultStreaming.cancel(result, :after_turn)

    events = result |> RunResultStreaming.raw_events() |> Enum.to_list()

    # Should only emit the first turn events, no second turn start
    assert Enum.any?(events, &match?(%Events.TurnContinuation{}, &1))
    assert Enum.count(events, &match?(%Events.TurnStarted{}, &1)) == 1
    assert Enum.count(events, &match?(%Events.TurnCompleted{}, &1)) == 1

    refute Enum.any?(events, fn
             %Events.TurnStarted{turn_id: "turn_auto_attempt2"} -> true
             _ -> false
           end)
  end

  test "guardrail results are streamed", %{thread_opts: thread_opts} do
    script_path =
      "thread_basic.jsonl"
      |> FixtureScripts.cat_fixture()
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} =
      Options.new(%{
        api_key: "test",
        codex_path_override: script_path
      })

    thread = Thread.build(codex_opts, thread_opts)

    guardrail =
      Guardrail.new(name: "input-check", handler: fn _input, _ctx -> {:tripwire, "nope"} end)

    {:ok, result} =
      AgentRunner.run_streamed(thread, "blocked run", %{
        agent: %{input_guardrails: [guardrail]}
      })

    events = result |> RunResultStreaming.events() |> Enum.to_list()

    assert Enum.any?(events, fn
             %GuardrailResult{stage: :input, guardrail: "input-check", result: :tripwire} -> true
             _ -> false
           end)

    # guardrail trip halts turn streaming
    assert result |> RunResultStreaming.raw_events() |> Enum.to_list() == []
  end

  test "immediate cancel before first event closes stream quickly", %{thread_opts: thread_opts} do
    script_path =
      temp_shell_script("""
      #!/usr/bin/env bash
      sleep 5
      """)

    on_exit(fn -> File.rm_rf(script_path) end)

    {:ok, codex_opts} =
      Options.new(%{
        api_key: "test",
        codex_path_override: script_path
      })

    thread = Thread.build(codex_opts, thread_opts)

    {:ok, result} = AgentRunner.run_streamed(thread, "cancel early")

    task =
      Task.Supervisor.async_nolink(Codex.TaskSupervisor, fn ->
        result |> RunResultStreaming.raw_events() |> Enum.to_list()
      end)

    Process.sleep(50)
    :ok = RunResultStreaming.cancel(result, :immediate)

    assert {:ok, []} = Task.yield(task, 700)
  end

  defp temp_shell_script(body) do
    path =
      Path.join(System.tmp_dir!(), "codex_stream_cancel_#{System.unique_integer([:positive])}.sh")

    File.write!(path, body)
    File.chmod!(path, 0o755)
    path
  end
end

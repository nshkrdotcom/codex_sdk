defmodule Codex.SessionTest do
  use ExUnit.Case, async: false

  alias Codex.AgentRunner
  alias Codex.Options
  alias Codex.Session.Memory
  alias Codex.TestSupport.FixtureScripts
  alias Codex.Thread
  alias Codex.Thread.Options, as: ThreadOptions

  test "session input callback merges history and saves responses" do
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

    {:ok, session_pid} = Memory.start_link()

    on_exit(fn ->
      if Process.alive?(session_pid) do
        Agent.stop(session_pid)
      end
    end)

    callback = fn input, history ->
      send(self(), {:session_callback, input, history})
      {:ok, input <> " (resumed)"}
    end

    run_config = %{
      session: {Memory, session_pid},
      session_input_callback: callback,
      conversation_id: "conv-123",
      previous_response_id: "resp-9"
    }

    {:ok, result} = AgentRunner.run(thread, "Hello", %{run_config: run_config})

    assert_received {:session_callback, "Hello", []}
    assert {:ok, history} = Memory.load(session_pid)

    assert [
             %{
               input: "Hello (resumed)",
               response: response,
               conversation_id: "conv-123",
               previous_response_id: "resp-9"
             }
           ] = history

    assert response == result.final_response
    assert result.thread.metadata[:conversation_id] == "conv-123"
    assert result.thread.metadata[:previous_response_id] == "resp-9"
  end
end

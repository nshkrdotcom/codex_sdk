defmodule Codex.ThreadTurnStreamTest do
  use ExUnit.Case, async: true

  alias Codex.Events
  alias Codex.Options
  alias Codex.TestSupport.FixtureScripts
  alias Codex.Thread
  alias Codex.Thread.Options, as: ThreadOptions

  setup do
    {:ok, thread_opts} = ThreadOptions.new(%{})
    %{thread_opts: thread_opts}
  end

  test "run_turn_streamed/3 is lazy until enumerated", %{thread_opts: thread_opts} do
    touch_path =
      Path.join(
        System.tmp_dir!(),
        "codex_turn_stream_touch_#{System.unique_integer([:positive])}"
      )

    script_path =
      FixtureScripts.touch_on_start("thread_basic.jsonl", touch_path)
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    on_exit(fn -> File.rm_rf(touch_path) end)

    {:ok, codex_opts} =
      Options.new(%{
        api_key: "test",
        codex_path_override: script_path
      })

    thread = Thread.build(codex_opts, thread_opts)

    {:ok, stream} = Thread.run_turn_streamed(thread, "Hello turn stream")

    refute File.exists?(touch_path)

    _events = Enum.take(stream, 1)
    assert File.exists?(touch_path)
  end

  test "run_turn_streamed/3 does not crash on failed turn.completed payloads",
       %{thread_opts: thread_opts} do
    script_path =
      FixtureScripts.cat_fixture("thread_failed_turn_completed.jsonl")
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} =
      Options.new(%{
        api_key: "test",
        codex_path_override: script_path
      })

    thread = Thread.build(codex_opts, thread_opts)

    {:ok, stream} = Thread.run_turn_streamed(thread, "Hello")
    events = Enum.to_list(stream)

    assert Enum.any?(events, &match?(%Events.TurnCompleted{status: "failed"}, &1))
  end
end

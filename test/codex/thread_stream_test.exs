defmodule Codex.ThreadStreamTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Codex.{Options, RunResultStreaming, Thread}
  alias Codex.TestSupport.FixtureScripts
  alias Codex.Thread.Options, as: ThreadOptions

  setup do
    {:ok, thread_opts} = ThreadOptions.new(%{})
    %{thread_opts: thread_opts}
  end

  describe "run_streamed/3" do
    test "is lazy until enumerated", %{thread_opts: thread_opts} do
      touch_path =
        Path.join(System.tmp_dir!(), "codex_stream_touch_#{System.unique_integer([:positive])}")

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

      {:ok, result} = Thread.run_streamed(thread, "Hello stream")
      refute File.exists?(touch_path)

      events = result |> RunResultStreaming.raw_events() |> Enum.to_list()
      assert length(events) == 5
      assert File.exists?(touch_path)
    end
  end

  property "partial enumeration yields deterministic sequences", %{thread_opts: thread_opts} do
    script_path =
      FixtureScripts.cat_fixture("thread_basic.jsonl")
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} =
      Options.new(%{
        api_key: "test",
        codex_path_override: script_path
      })

    check all(take_count <- StreamData.integer(0..5)) do
      thread = Thread.build(codex_opts, thread_opts)

      {:ok, full_stream} = Thread.run_streamed(thread, "Deterministic test")
      all_events = full_stream |> RunResultStreaming.raw_events() |> Enum.to_list()

      {:ok, partial_stream} = Thread.run_streamed(thread, "Deterministic test")

      assert Enum.take(all_events, take_count) ==
               partial_stream |> RunResultStreaming.raw_events() |> Enum.take(take_count)
    end
  end
end

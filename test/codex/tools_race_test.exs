defmodule Codex.ToolsRaceTest do
  use ExUnit.Case, async: false

  alias Codex.Tools

  setup do
    Tools.reset!()
    Tools.reset_metrics()

    on_exit(fn ->
      Tools.reset!()
      Tools.reset_metrics()
    end)

    :ok
  end

  test "record_invocation handles concurrent metrics table bootstrap" do
    case :ets.whereis(:codex_tool_metrics) do
      :undefined -> :ok
      _ -> :ets.delete(:codex_tool_metrics)
    end

    parent = self()
    ready_ref = make_ref()
    go_ref = make_ref()

    tasks =
      for _ <- 1..40 do
        Task.async(fn ->
          send(parent, {ready_ref, self()})
          receive do: (^go_ref -> :ok)
          Tools.record_invocation("race_tool", :success, 1)
        end)
      end

    for _ <- 1..40 do
      assert_receive {^ready_ref, _pid}, 1_000
    end

    Enum.each(tasks, fn task ->
      send(task.pid, go_ref)
    end)

    Enum.each(tasks, fn task ->
      assert Task.await(task, 1_000) == :ok
    end)
  end
end

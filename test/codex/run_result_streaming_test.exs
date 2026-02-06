defmodule Codex.RunResultStreamingTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Codex.{Error, Options, RunResultStreaming, Thread}
  alias Codex.RunResultStreaming.Control
  alias Codex.StreamQueue
  alias Codex.Thread.Options, as: ThreadOptions

  test "RunResultStreaming: surfaces transport errors for streamed runs" do
    previous_flag = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, previous_flag) end)

    script_path =
      temp_script("""
      #!/usr/bin/env bash
      echo '{"type":"thread.started","thread_id":"thread_error"}'
      exit 9
      """)
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    {:ok, thread_opts} = ThreadOptions.new(%{})
    thread = Thread.build(codex_opts, thread_opts)

    {:ok, result} = Thread.run_streamed(thread, "hi")

    task =
      Task.async(fn ->
        result
        |> RunResultStreaming.raw_events()
        |> Enum.to_list()
      end)

    _log =
      capture_log(fn ->
        send(self(), {:task_result, Task.yield(task, 1_000) || Task.shutdown(task, :brutal_kill)})
      end)

    assert_receive {:task_result, task_result}

    case task_result do
      {:exit, {%Error{} = error, _}} ->
        assert error.details[:exit_status] == 9

      other ->
        flunk("expected Codex.Error exit, got: #{inspect(other)}")
    end
  end

  test "RunResultStreaming.Control: fallback producer crashes do not crash control process" do
    remove_task_supervisor()

    on_exit(fn ->
      restore_task_supervisor()
    end)

    {:ok, queue} = StreamQueue.start_link()
    {:ok, control} = Control.start_link()

    on_exit(fn ->
      if Process.alive?(control) do
        Agent.stop(control, :normal)
      end

      if Process.alive?(queue) do
        StreamQueue.close(queue)
      end
    end)

    starter = fn ->
      receive do
        :halt -> :ok
      end
    end

    :ok = Control.start_if_needed(control, starter, queue)

    producer_pid =
      Agent.get(control, fn state ->
        state.producer_pid
      end)

    assert is_pid(producer_pid)
    Process.exit(producer_pid, :boom)
    Process.sleep(50)

    assert Process.alive?(control)
  end

  defp remove_task_supervisor do
    case Process.whereis(Codex.Supervisor) do
      nil ->
        :ok

      _ ->
        case Process.whereis(Codex.TaskSupervisor) do
          nil ->
            :ok

          _ ->
            :ok = Supervisor.terminate_child(Codex.Supervisor, Codex.TaskSupervisor)
            :ok = Supervisor.delete_child(Codex.Supervisor, Codex.TaskSupervisor)
        end
    end
  end

  defp restore_task_supervisor do
    cond do
      is_nil(Process.whereis(Codex.Supervisor)) ->
        :ok

      is_pid(Process.whereis(Codex.TaskSupervisor)) ->
        :ok

      true ->
        case Supervisor.start_child(
               Codex.Supervisor,
               {Task.Supervisor, name: Codex.TaskSupervisor}
             ) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end
    end
  end

  defp temp_script(contents) do
    path = Path.join(System.tmp_dir!(), "codex_stream_#{System.unique_integer([:positive])}")
    File.write!(path, contents)
    File.chmod!(path, 0o755)
    path
  end
end

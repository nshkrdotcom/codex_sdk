defmodule Codex.RunResultStreamingTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Codex.{Options, RunResultStreaming, Thread, TransportError}
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
      {:exit, {%TransportError{} = error, _}} ->
        assert error.exit_status == 9

      other ->
        flunk("expected TransportError exit, got: #{inspect(other)}")
    end
  end

  defp temp_script(contents) do
    path = Path.join(System.tmp_dir!(), "codex_stream_#{System.unique_integer([:positive])}")
    File.write!(path, contents)
    File.chmod!(path, 0o755)
    path
  end
end

defmodule Codex.ExecTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Codex.{Events, Exec, Items, Options}
  alias Codex.TestSupport.FixtureScripts

  test "injects custom env into codex exec processes" do
    script_path =
      temp_script("""
      #!/usr/bin/env bash
      echo "{\\"type\\":\\"turn.completed\\",\\"turn_id\\":\\"turn_env\\",\\"thread_id\\":\\"thread_env\\",\\"final_response\\":{\\"type\\":\\"text\\",\\"text\\":\\"${CUSTOM_ENV}\\"}}"
      """)
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    exec_opts = %{
      codex_opts: codex_opts,
      env: %{"CUSTOM_ENV" => "injected-value"}
    }

    assert {:ok, %{events: events}} = Exec.run("hi", exec_opts)

    assert Enum.any?(events, fn
             %Events.TurnCompleted{final_response: response} ->
               final_text(response) == "injected-value"

             _ ->
               false
           end)
  end

  test "forwards cancellation token flag to codex exec" do
    capture_path =
      Path.join(System.tmp_dir!(), "codex_exec_args_#{System.unique_integer([:positive])}")

    script_path =
      "thread_basic.jsonl"
      |> FixtureScripts.capture_args(capture_path)
      |> tap(fn path ->
        on_exit(fn ->
          File.rm_rf(path)
          File.rm_rf(capture_path)
        end)
      end)

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    exec_opts = %{codex_opts: codex_opts, cancellation_token: "cancel-me"}

    assert {:ok, _} = Exec.run("cancel", exec_opts)

    args =
      capture_path
      |> File.read!()
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    idx = Enum.find_index(args, &(&1 == "--cancellation-token"))
    assert idx
    assert Enum.at(args, idx + 1) == "cancel-me"
  end

  test "emits clarified timeout error when exec stalls" do
    script_path =
      temp_script("""
      #!/usr/bin/env bash
      sleep 0.2
      echo "{\\"type\\":\\"turn.completed\\",\\"turn_id\\":\\"turn_timeout\\",\\"thread_id\\":\\"thread_timeout\\"}"
      """)
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    exec_opts = %{codex_opts: codex_opts, timeout_ms: 50}

    log =
      capture_log(fn ->
        assert {:error, {:codex_timeout, 50}} = Exec.run("stall", exec_opts)
      end)

    assert log =~ "codex exec timed out"
    assert log =~ "50"
  end

  defp final_text(%Items.AgentMessage{text: text}), do: text
  defp final_text(%{"text" => text}), do: text
  defp final_text(%{text: text}), do: text
  defp final_text(_other), do: nil

  defp temp_script(contents) do
    path = Path.join(System.tmp_dir!(), "codex_exec_#{System.unique_integer([:positive])}")
    File.write!(path, contents)
    File.chmod!(path, 0o755)
    path
  end
end

defmodule Codex.ExecTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Codex.{Events, Exec, Items, Options, Thread}
  alias Codex.TestSupport.FixtureScripts
  alias Codex.Thread.Options, as: ThreadOptions

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

  test "forwards exec CLI flags and config overrides" do
    capture_path =
      Path.join(System.tmp_dir!(), "codex_exec_flags_#{System.unique_integer([:positive])}")

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

    {:ok, thread_opts} =
      ThreadOptions.new(%{
        profile: "team",
        oss: true,
        local_provider: "ollama",
        full_auto: true,
        output_last_message: "/tmp/last_message.txt",
        color: :always,
        config_overrides: %{
          "features.web_search_request" => true,
          "model" => "o3"
        }
      })

    thread = Thread.build(codex_opts, thread_opts)

    assert {:ok, _} = Thread.run(thread, "flags")

    args =
      capture_path
      |> File.read!()
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    assert fetch_flag_value(args, "--profile") == "team"

    assert Enum.any?(args, &(&1 == "--oss"))

    assert fetch_flag_value(args, "--local-provider") == "ollama"

    assert Enum.any?(args, &(&1 == "--full-auto"))

    assert fetch_flag_value(args, "--output-last-message") == "/tmp/last_message.txt"

    assert fetch_flag_value(args, "--color") == "always"

    assert "features.web_search_request=true" in flag_values(args, "--config")
    assert ~s(model="o3") in flag_values(args, "--config")
  end

  test "forwards dangerously bypass flag to codex exec" do
    capture_path =
      Path.join(
        System.tmp_dir!(),
        "codex_exec_danger_args_#{System.unique_integer([:positive])}"
      )

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
    {:ok, thread_opts} = ThreadOptions.new(%{dangerously_bypass_approvals_and_sandbox: true})
    thread = Thread.build(codex_opts, thread_opts)

    assert {:ok, _} = Thread.run(thread, "danger")

    args =
      capture_path
      |> File.read!()
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    assert Enum.any?(args, &(&1 == "--dangerously-bypass-approvals-and-sandbox"))
  end

  test "runs exec review subcommand" do
    capture_path =
      Path.join(System.tmp_dir!(), "codex_exec_review_args_#{System.unique_integer([:positive])}")

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

    assert {:ok, _} =
             Exec.review({:base_branch, "main"}, %{codex_opts: codex_opts, timeout_ms: 1_000})

    args =
      capture_path
      |> File.read!()
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    assert Enum.any?(args, &(&1 == "review"))

    assert fetch_flag_value(args, "--base") == "main"
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

  defp fetch_flag_value(args, flag) do
    case Enum.find_index(args, &(&1 == flag)) do
      nil -> nil
      idx -> Enum.at(args, idx + 1)
    end
  end

  defp flag_values(args, flag) do
    args
    |> Enum.with_index()
    |> Enum.filter(fn {value, _idx} -> value == flag end)
    |> Enum.map(fn {_value, idx} -> Enum.at(args, idx + 1) end)
  end

  defp temp_script(contents) do
    path = Path.join(System.tmp_dir!(), "codex_exec_#{System.unique_integer([:positive])}")
    File.write!(path, contents)
    File.chmod!(path, 0o755)
    path
  end
end

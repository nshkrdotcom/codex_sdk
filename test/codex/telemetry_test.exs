defmodule Codex.TelemetryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.TestSupport.FixtureScripts
  alias Codex.{Options, Thread, Telemetry}

  setup do
    handler_id = "telemetry-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [
        [:codex, :thread, :start],
        [:codex, :thread, :stop],
        [:codex, :thread, :exception]
      ],
      &__MODULE__.collect_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  test "thread run emits start and stop events" do
    script_path =
      FixtureScripts.cat_fixture("thread_basic.jsonl")
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    {:ok, thread_opts} = ThreadOptions.new(%{})
    thread = Thread.build(codex_opts, thread_opts)

    {:ok, _result} = Thread.run(thread, "hi")

    assert_receive {[:codex, :thread, :start], %{system_time: _}, %{input: "hi"}}, 100
    assert_receive {[:codex, :thread, :stop], %{duration: duration}, _}, 100
    assert duration > 0
  end

  test "exceptions emit telemetry" do
    script_body = """
    #!/usr/bin/env bash
    exit 9
    """

    script_path = temp_script(script_body)
    on_exit(fn -> File.rm_rf(script_path) end)

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    {:ok, thread_opts} = ThreadOptions.new(%{})
    thread = Thread.build(codex_opts, thread_opts)

    assert {:error, _} = Thread.run(thread, "boom")

    assert_receive {[:codex, :thread, :exception], %{duration: _}, %{reason: _}}, 100
  end

  test "default logger writes events" do
    script_path =
      FixtureScripts.cat_fixture("thread_basic.jsonl")
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    {:ok, thread_opts} = ThreadOptions.new(%{})
    thread = Thread.build(codex_opts, thread_opts)

    handler = "codex-default-logger-test-#{System.unique_integer([:positive])}"
    :ok = Telemetry.attach_default_logger(handler_id: handler)
    on_exit(fn -> :telemetry.detach(handler) end)

    log =
      capture_log(fn ->
        {:ok, _} = Thread.run(thread, "log message")
      end)

    assert log =~ "[codex] thread start"
    assert log =~ "[codex] thread stop"
  end

  def collect_event(event, measurements, metadata, pid) do
    send(pid, {event, measurements, metadata})
  end

  defp temp_script(contents) do
    path = Path.join(System.tmp_dir!(), "codex_telemetry_#{System.unique_integer([:positive])}")
    File.write!(path, contents)
    File.chmod!(path, 0o755)
    path
  end
end

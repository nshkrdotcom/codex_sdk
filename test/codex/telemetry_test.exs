defmodule Codex.TelemetryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  require Record

  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.TestSupport.FixtureScripts
  alias Codex.{Options, Thread, Telemetry}

  @thread_events [
    [:codex, :thread, :start],
    [:codex, :thread, :stop],
    [:codex, :thread, :exception]
  ]

  Record.defrecord(
    :otel_span,
    :span,
    Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  )

  setup do
    handler_id = "telemetry-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      @thread_events,
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

    assert_receive {[:codex, :thread, :start], %{system_time: _},
                    %{input: "hi", originator: :sdk}},
                   100

    assert_receive {[:codex, :thread, :stop], measurements, metadata}, 100
    assert measurements.duration_ms > 0
    assert metadata.originator == :sdk
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

    assert_receive {[:codex, :thread, :exception], measurements, metadata}, 100
    assert measurements.duration_ms > 0
    assert metadata.originator == :sdk
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

  test "configure is no-op when OTLP endpoint missing" do
    previous = Application.get_env(:codex_sdk, :enable_otlp?, false)
    Application.put_env(:codex_sdk, :enable_otlp?, false)
    on_exit(fn -> Application.put_env(:codex_sdk, :enable_otlp?, previous) end)
    assert :ok = Telemetry.configure(env: %{}, enabled?: false)
  end

  test "configure with pid exporter attaches tracing when enabled" do
    previous = Application.get_env(:codex_sdk, :enable_otlp?, false)
    Application.put_env(:codex_sdk, :enable_otlp?, true)

    on_exit(fn ->
      Application.put_env(:codex_sdk, :enable_otlp?, previous)
      _ = Application.stop(:opentelemetry_exporter)
      _ = Application.stop(:opentelemetry)
      :telemetry.detach(Telemetry.tracing_handler_id())
    end)

    env = %{"CODEX_OTLP_ENDPOINT" => "otlp://test.local"}

    assert :ok =
             Telemetry.configure(
               env: env,
               exporter: {:otel_exporter_pid, self()},
               enabled?: true
             )

    processors = Application.get_env(:opentelemetry, :processors)
    assert [{:otel_simple_processor, config}] = processors
    assert config.exporter == {:otel_exporter_pid, self()}

    handler_id = Telemetry.tracing_handler_id()

    assert Enum.any?(@thread_events, fn event ->
             :telemetry.list_handlers(event)
             |> Enum.any?(fn handler -> handler.id == handler_id end)
           end)

    script_path =
      FixtureScripts.cat_fixture("thread_basic.jsonl")
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    {:ok, thread_opts} = ThreadOptions.new(%{})
    thread = Thread.build(codex_opts, thread_opts)

    assert {:ok, _} = Thread.run(thread, "otel trace run")

    assert Enum.any?(Application.started_applications(), fn {app, _, _} ->
             app == :opentelemetry
           end)
  end

  test "early exit runs mark telemetry and logs pruning" do
    script_path =
      FixtureScripts.cat_fixture("thread_early_exit.jsonl")
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    {:ok, thread_opts} = ThreadOptions.new(%{})
    thread = Thread.build(codex_opts, thread_opts)

    handler = "codex-default-logger-test-#{System.unique_integer([:positive])}"
    :ok = Telemetry.attach_default_logger(handler_id: handler)
    on_exit(fn -> :telemetry.detach(handler) end)

    log =
      capture_log(fn ->
        {:ok, _} = Thread.run(thread, "prune")
      end)

    assert log =~ "early_exit"

    assert_receive {[:codex, :thread, :start], %{system_time: _}, %{originator: :sdk}}, 100

    assert_receive {[:codex, :thread, :stop], measurements, metadata}, 100
    assert measurements.duration_ms > 0
    assert metadata.result == :early_exit
    assert metadata.early_exit?
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

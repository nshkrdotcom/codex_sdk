defmodule Codex.TelemetryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Codex.{Options, RunResultStreaming, Telemetry, Thread}
  alias Codex.TestSupport.FixtureScripts
  alias Codex.Thread.Options, as: ThreadOptions

  @thread_events [
    [:codex, :thread, :start],
    [:codex, :thread, :stop],
    [:codex, :thread, :exception]
  ]

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

    {_m_start, _meta_start} =
      assert_event([:codex, :thread, :start],
        match: fn _e, _m, metadata -> metadata.input == "hi" end
      )

    {measurements, metadata} =
      assert_event([:codex, :thread, :stop],
        match: fn _e, _m, md -> md.thread_id == "thread_abc123" end
      )

    assert measurements.duration_ms > 0
    assert metadata.originator == :sdk
  end

  test "thread telemetry preserves explicit false trace flags" do
    script_path =
      FixtureScripts.cat_fixture("thread_basic.jsonl")
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    {:ok, thread_opts} = ThreadOptions.new(%{})

    thread =
      Thread.build(codex_opts, thread_opts,
        metadata: %{trace_sensitive: false, tracing_disabled: false}
      )

    {:ok, _result} = Thread.run(thread, "trace flags")

    {_m_start, meta_start} =
      assert_event([:codex, :thread, :start],
        match: fn _e, _m, metadata -> metadata.input == "trace flags" end
      )

    assert Map.fetch!(meta_start, :trace_sensitive) == false
    assert Map.fetch!(meta_start, :tracing_disabled) == false
  end

  test "thread run_streamed emits start and stop events" do
    script_path =
      FixtureScripts.cat_fixture("thread_basic.jsonl")
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    {:ok, thread_opts} = ThreadOptions.new(%{})
    thread = Thread.build(codex_opts, thread_opts)

    {:ok, result} = Thread.run_streamed(thread, "hi")

    result
    |> RunResultStreaming.raw_events()
    |> Enum.to_list()

    {_m_start, _meta_start} =
      assert_event([:codex, :thread, :start],
        match: fn _e, _m, metadata -> metadata.input == "hi" end
      )

    {measurements, metadata} =
      assert_event([:codex, :thread, :stop],
        match: fn _e, _m, md -> md.thread_id == "thread_abc123" end
      )

    assert measurements.duration_ms > 0
    assert metadata.originator == :sdk
  end

  test "streamed progress events include thread and turn context" do
    script_path =
      FixtureScripts.cat_fixture("thread_progress_no_ids.jsonl")
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    {:ok, thread_opts} = ThreadOptions.new(%{})
    thread = Thread.build(codex_opts, thread_opts)

    handler_id = "telemetry-progress-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_id,
      [:codex, :thread, :token_usage, :updated],
      &__MODULE__.collect_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, result} = Thread.run_streamed(thread, "progress")

    result
    |> RunResultStreaming.raw_events()
    |> Enum.to_list()

    {_measurements, metadata} =
      assert_event([:codex, :thread, :token_usage, :updated],
        match: fn _e, _m, md -> md.thread_id == "thread_progress" end
      )

    assert metadata.thread_id == "thread_progress"
    assert metadata.turn_id == "turn_progress"
  end

  test "thread telemetry captures ids and source metadata" do
    script_body = """
    #!/usr/bin/env bash
    cat <<'EOF'
    {"type":"thread.started","thread_id":"thread_src","metadata":{"labels":{"topic":"sources"},"source":{"origin":"unit-test","workspace":"/tmp/test"}}}
    {"type":"turn.started","turn_id":"turn_src","thread_id":"thread_src"}
    {"type":"turn.completed","turn_id":"turn_src","thread_id":"thread_src","final_response":{"type":"text","text":"done"}}
    EOF
    """

    script_path = temp_script(script_body)
    on_exit(fn -> File.rm_rf(script_path) end)

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    {:ok, thread_opts} = ThreadOptions.new(%{})
    thread = Thread.build(codex_opts, thread_opts)

    {:ok, _result} = Thread.run(thread, "capture source info")

    {_m_start, %{span_token: span_token}} =
      assert_event([:codex, :thread, :start],
        match: fn _e, _m, metadata -> metadata.input == "capture source info" end
      )

    {measurements, metadata} =
      assert_event([:codex, :thread, :stop],
        match: fn _e, _m, md -> md.thread_id == "thread_src" end
      )

    assert measurements.duration_ms > 0
    assert metadata.thread_id == "thread_src"
    assert metadata.turn_id == "turn_src"
    assert metadata.source == %{"origin" => "unit-test", "workspace" => "/tmp/test"}
    assert metadata.span_token == span_token
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

  test "otlp_enabled? prefers CODEX_OTLP_ENABLE when present" do
    assert Telemetry.otlp_enabled?(env: %{"CODEX_OTLP_ENABLE" => "1"}, app_enabled?: false)
    assert Telemetry.otlp_enabled?(env: %{"CODEX_OTLP_ENABLE" => "true"}, app_enabled?: false)
    refute Telemetry.otlp_enabled?(env: %{"CODEX_OTLP_ENABLE" => "0"}, app_enabled?: true)
  end

  test "otlp_enabled? falls back to app config when env flag missing or invalid" do
    assert Telemetry.otlp_enabled?(env: %{}, app_enabled?: true)
    refute Telemetry.otlp_enabled?(env: %{}, app_enabled?: false)
    assert Telemetry.otlp_enabled?(env: %{"CODEX_OTLP_ENABLE" => "bogus"}, app_enabled?: true)
  end

  test "configure is no-op when OTLP endpoint missing" do
    previous = Application.get_env(:codex_sdk, :enable_otlp?, false)
    Application.put_env(:codex_sdk, :enable_otlp?, false)
    on_exit(fn -> Application.put_env(:codex_sdk, :enable_otlp?, previous) end)
    assert :ok = Telemetry.configure(env: %{}, enabled?: false)
  end

  test "configure reads CODEX_OTLP_ENABLE from env map by default" do
    previous = Application.get_env(:codex_sdk, :enable_otlp?, false)
    Application.put_env(:codex_sdk, :enable_otlp?, false)

    on_exit(fn ->
      Application.put_env(:codex_sdk, :enable_otlp?, previous)
      _ = Application.stop(:opentelemetry_exporter)
      _ = Application.stop(:opentelemetry)
      _ = Application.stop(:tls_certificate_check)
      :telemetry.detach(Telemetry.tracing_handler_id())
    end)

    env = %{
      "CODEX_OTLP_ENABLE" => "1",
      "CODEX_OTLP_ENDPOINT" => "otlp://test.local"
    }

    assert :ok = Telemetry.configure(env: env, exporter: {:otel_exporter_pid, self()})

    assert [{:otel_simple_processor, config}] = Application.get_env(:opentelemetry, :processors)
    assert config.exporter == {:otel_exporter_pid, self()}
  end

  test "configure with pid exporter attaches tracing when enabled" do
    previous = Application.get_env(:codex_sdk, :enable_otlp?, false)
    Application.put_env(:codex_sdk, :enable_otlp?, true)

    on_exit(fn ->
      Application.put_env(:codex_sdk, :enable_otlp?, previous)
      _ = Application.stop(:opentelemetry_exporter)
      _ = Application.stop(:opentelemetry)
      _ = Application.stop(:tls_certificate_check)
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

    {_start_m, _start_meta} =
      assert_event([:codex, :thread, :start],
        match: fn _e, _m, metadata -> metadata.input == "otel trace run" end
      )

    {_stop_m, metadata} =
      assert_event([:codex, :thread, :stop],
        match: fn _e, _m, md -> md.thread_id == "thread_abc123" end
      )

    attributes =
      metadata
      |> Telemetry.thread_span_attributes()
      |> Map.merge(Telemetry.finalize_thread_attributes(metadata))

    assert attributes[:"codex.thread.id"] == "thread_abc123"
    assert attributes[:"codex.turn.id"] == "turn_def456"
    assert attributes[:"codex.originator"] == "sdk"
  end

  test "telemetry emits token usage, diff, and compaction updates with ids" do
    handler_id = "telemetry-progress-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [
        [:codex, :thread, :token_usage, :updated],
        [:codex, :turn, :diff, :updated],
        [:codex, :turn, :compaction, :completed]
      ],
      &__MODULE__.collect_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    script_path =
      FixtureScripts.cat_fixture("thread_usage_events.jsonl")
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    {:ok, thread_opts} = ThreadOptions.new(%{})
    thread = Thread.build(codex_opts, thread_opts)

    {:ok, _result} = Thread.run(thread, "usage telemetry")

    assert_receive {[:codex, :thread, :token_usage, :updated], %{system_time: _},
                    %{
                      thread_id: "thread_usage",
                      turn_id: "turn_usage",
                      usage: usage,
                      delta: delta
                    }},
                   100

    assert usage["total_tokens"] == 110
    assert delta["input_tokens"] == 100

    diff = %{"ops" => [%{"op" => "add", "path" => "response", "text" => "+ summarized"}]}

    assert_receive {[:codex, :turn, :diff, :updated], %{system_time: _},
                    %{thread_id: "thread_usage", turn_id: "turn_usage", diff: ^diff}},
                   100

    assert_receive {[:codex, :turn, :compaction, :completed], %{system_time: _} = measurements,
                    %{thread_id: "thread_usage", turn_id: "turn_usage", compaction: compaction}},
                   100

    assert compaction["token_savings"] == 256
    assert measurements[:token_savings] == 256
  end

  test "configure supports mTLS exporter settings" do
    cert_path = temp_file("cert", "mtls-cert")
    key_path = temp_file("key", "mtls-key")
    ca_path = temp_file("ca", "mtls-ca")

    on_exit(fn ->
      File.rm_rf(cert_path)
      File.rm_rf(key_path)
      File.rm_rf(ca_path)
    end)

    previous = Application.get_env(:codex_sdk, :enable_otlp?, false)
    Application.put_env(:codex_sdk, :enable_otlp?, true)

    on_exit(fn ->
      Application.put_env(:codex_sdk, :enable_otlp?, previous)
      _ = Application.stop(:opentelemetry_exporter)
      _ = Application.stop(:opentelemetry)
      _ = Application.stop(:tls_certificate_check)
      :telemetry.detach(Telemetry.tracing_handler_id())
    end)

    env = %{
      "CODEX_OTLP_ENDPOINT" => "https://otel.example.com:4318",
      "CODEX_OTLP_CERTFILE" => cert_path,
      "CODEX_OTLP_KEYFILE" => key_path,
      "CODEX_OTLP_CACERTFILE" => ca_path
    }

    assert :ok = Telemetry.configure(env: env, enabled?: true)

    assert [{:otel_simple_processor, %{exporter: {:opentelemetry_exporter, exporter_cfg}}}] =
             Application.get_env(:opentelemetry, :processors)

    assert exporter_cfg[:ssl_options] |> Enum.into(%{}) == %{
             certfile: cert_path,
             keyfile: key_path,
             cacertfile: ca_path
           }
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

    {_start_measurements, _start_metadata} =
      assert_event([:codex, :thread, :start],
        match: fn _e, _m, md -> md.input == "prune" end
      )

    {measurements, metadata} =
      assert_event([:codex, :thread, :stop],
        match: fn _e, _m, md -> md.thread_id == "thread_ephemeral" end
      )

    assert measurements.duration_ms > 0
    assert metadata.result == :early_exit
    assert metadata.early_exit?
  end

  def collect_event(event, measurements, metadata, pid) do
    send(pid, {event, measurements, metadata})
  end

  defp assert_event(event_name, opts) do
    matcher = Keyword.get(opts, :match, fn _e, _m, _md -> true end)
    timeout = Keyword.get(opts, :timeout, 200)

    receive do
      {^event_name, measurements, metadata} ->
        if matcher.(event_name, measurements, metadata) do
          {measurements, metadata}
        else
          assert_event(event_name, opts)
        end

      _other ->
        assert_event(event_name, opts)
    after
      timeout ->
        flunk("expected telemetry event #{inspect(event_name)}")
    end
  end

  defp temp_script(contents) do
    path = Path.join(System.tmp_dir!(), "codex_telemetry_#{System.unique_integer([:positive])}")
    File.write!(path, contents)
    File.chmod!(path, 0o755)
    path
  end

  defp temp_file(prefix, content) do
    path =
      Path.join(
        System.tmp_dir!(),
        "codex_telemetry_#{prefix}_#{System.unique_integer([:positive])}"
      )

    File.write!(path, content)
    path
  end
end

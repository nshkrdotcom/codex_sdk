defmodule Codex.Telemetry do
  @moduledoc """
  Telemetry helpers and default logging for Codex events.
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias OpenTelemetry.Span

  @thread_events [
    [:codex, :thread, :start],
    [:codex, :thread, :stop],
    [:codex, :thread, :exception]
  ]

  @realtime_events [
    [:codex, :realtime, :session, :start],
    [:codex, :realtime, :session, :stop],
    [:codex, :realtime, :audio, :send],
    [:codex, :realtime, :audio, :receive]
  ]

  @voice_events [
    [:codex, :voice, :pipeline, :start],
    [:codex, :voice, :pipeline, :stop],
    [:codex, :voice, :transcription, :start],
    [:codex, :voice, :transcription, :stop],
    [:codex, :voice, :synthesis, :start],
    [:codex, :voice, :synthesis, :stop]
  ]

  alias Codex.Config.Defaults

  @trace_events @thread_events ++ @realtime_events ++ @voice_events
  @otel_handler_id Defaults.telemetry_otel_handler_id()
  @default_originator Defaults.telemetry_default_originator()
  @default_processor_name Defaults.telemetry_processor_name()
  @otlp_configured_key :otlp_configured?

  @type telemetry_event :: [atom()]

  @doc """
  Emits a telemetry event with the given measurements and metadata.
  """
  @spec emit(telemetry_event(), map(), map()) :: :ok
  def emit(event, measurements \\ %{}, metadata \\ %{}) do
    normalized_measurements = normalize_measurements(measurements)
    normalized_metadata = normalize_metadata(metadata)

    :telemetry.execute(event, normalized_measurements, normalized_metadata)
  end

  @doc """
  Configures OpenTelemetry exporting if the required environment variables are present.

  Reads `CODEX_OTLP_ENDPOINT` and optional `CODEX_OTLP_HEADERS` from the provided `:env` map
  (defaults to `System.get_env/0`) and wires the exporter when set.
  """
  @spec configure(keyword()) :: :ok
  def configure(opts \\ []) do
    env = resolve_env(Keyword.get(opts, :env))
    enabled? = Keyword.get(opts, :enabled?, otlp_enabled?(env: env))

    if enabled? do
      endpoint = env |> Map.get("CODEX_OTLP_ENDPOINT") |> normalize_string()

      if is_nil(endpoint) do
        :ok
      else
        configure_with_endpoint(endpoint, env, opts)
      end
    else
      disable_otel_tracing()

      if otlp_configured?() do
        reset_otel_apps()
        set_otlp_configured(false)
      end

      Application.put_env(:opentelemetry, :processors, [])
      :ok
    end
  end

  @doc false
  @spec otlp_enabled?(keyword()) :: boolean()
  def otlp_enabled?(opts \\ []) do
    env = resolve_env(Keyword.get(opts, :env))

    app_enabled? =
      Keyword.get(opts, :app_enabled?, Application.get_env(:codex_sdk, :enable_otlp?, false))

    case parse_boolean(Map.get(env, "CODEX_OTLP_ENABLE")) do
      {:ok, value} -> value
      :error -> app_enabled?
    end
  end

  @doc false
  @spec tracing_handler_id() :: String.t()
  def tracing_handler_id, do: @otel_handler_id

  @doc """
  Attaches the default logger to thread telemetry events.
  """
  @spec attach_default_logger(keyword()) :: :ok | {:error, :already_exists}
  def attach_default_logger(opts \\ []) do
    handler_id = Keyword.get(opts, :handler_id, "codex-default-logger")
    level = Keyword.get(opts, :level, :info)

    :telemetry.attach_many(handler_id, @thread_events, &__MODULE__.handle_event/4, %{level: level})
  end

  @doc false
  def handle_event([:codex, :thread, :start], _measurements, metadata, %{level: level}) do
    Logger.log(level, fn ->
      "[codex] thread start input=#{inspect(Map.get(metadata, :input))} thread_id=#{inspect(Map.get(metadata, :thread_id))}"
    end)
  end

  def handle_event([:codex, :thread, :stop], measurements, metadata, %{level: level}) do
    duration_ms = Map.get(measurements, :duration_ms)
    result = Map.get(metadata, :result, :ok)
    early_exit? = Map.get(metadata, :early_exit?, false)

    Logger.log(level, fn ->
      "[codex] thread stop duration_ms=#{duration_ms} thread_id=#{inspect(Map.get(metadata, :thread_id))} turn_id=#{inspect(Map.get(metadata, :turn_id))} result=#{result}#{maybe_flag(" early_exit", early_exit?)}"
    end)
  end

  def handle_event([:codex, :thread, :exception], measurements, metadata, _config) do
    duration_ms = Map.get(measurements, :duration_ms)
    reason = Map.get(metadata, :reason)

    Logger.log(:error, fn ->
      "[codex] thread exception duration_ms=#{duration_ms} thread_id=#{inspect(Map.get(metadata, :thread_id))} turn_id=#{inspect(Map.get(metadata, :turn_id))} reason=#{inspect(reason)}"
    end)
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  @doc false
  def handle_trace_event([:codex, :thread, :start], measurements, metadata, _config) do
    start_thread_span(measurements, metadata)
  end

  def handle_trace_event([:codex, :thread, status], measurements, metadata, _config)
      when status in [:stop, :exception] do
    finish_thread_span(status, measurements, metadata)
  end

  def handle_trace_event(_event, _measurements, _metadata, _config), do: :ok

  defp maybe_flag(_label, false), do: ""
  defp maybe_flag(label, true), do: "#{label}=true"

  # -- emit helpers ---------------------------------------------------------

  defp normalize_measurements(measurements) when is_map(measurements) do
    measurements
    |> maybe_put_duration_ms()
  end

  defp normalize_measurements(measurements) when is_list(measurements) do
    measurements
    |> Map.new()
    |> normalize_measurements()
  end

  defp normalize_measurements(other) do
    other
    |> Map.new()
    |> normalize_measurements()
  end

  defp maybe_put_duration_ms(measurements) do
    cond do
      Map.has_key?(measurements, :duration_ms) ->
        measurements

      duration = measurements[:duration] ->
        if is_integer(duration) do
          Map.put(measurements, :duration_ms, convert_duration_to_ms(duration))
        else
          measurements
        end

      true ->
        measurements
    end
  end

  defp normalize_metadata(metadata) when is_map(metadata) do
    metadata
    |> normalize_warnings()
    |> Map.put_new(:originator, @default_originator)
  end

  defp normalize_metadata(metadata) when is_list(metadata) do
    metadata
    |> Map.new()
    |> normalize_metadata()
  end

  defp normalize_metadata(_), do: %{originator: @default_originator}

  defp normalize_warnings(metadata) do
    case warning_key_and_values(metadata) do
      {nil, _} ->
        metadata

      {key, warnings} ->
        Map.put(metadata, key, normalize_warning_list(warnings))
    end
  end

  defp warning_key_and_values(metadata) do
    cond do
      Map.has_key?(metadata, :sandbox_warnings) ->
        {:sandbox_warnings, Map.get(metadata, :sandbox_warnings)}

      Map.has_key?(metadata, "sandbox_warnings") ->
        {"sandbox_warnings", Map.get(metadata, "sandbox_warnings")}

      Map.has_key?(metadata, :warnings) ->
        {:warnings, Map.get(metadata, :warnings)}

      Map.has_key?(metadata, "warnings") ->
        {"warnings", Map.get(metadata, "warnings")}

      true ->
        {nil, nil}
    end
  end

  defp normalize_warning_list(nil), do: []

  defp normalize_warning_list(warning) when not is_list(warning),
    do: normalize_warning_list([warning])

  defp normalize_warning_list(warnings) do
    {_, acc} =
      Enum.reduce(warnings, {MapSet.new(), []}, fn warning, {seen, acc} ->
        normalized = normalize_warning_value(warning)
        key = warning_key(normalized)

        if MapSet.member?(seen, key) do
          {seen, acc}
        else
          {MapSet.put(seen, key), acc ++ [normalized]}
        end
      end)

    acc
  end

  defp normalize_warning_value(warning) when is_binary(warning) do
    if windows_path_fragment?(warning) do
      warning
      |> String.replace("\\", "/")
      |> String.replace(~r{/+}, "/")
    else
      warning
    end
  end

  defp normalize_warning_value(warning), do: normalize_warning_value(to_string(warning))

  defp warning_key(value) do
    normalized = to_string(value)

    if windows_path_fragment?(normalized) do
      normalized
      |> String.replace("\\", "/")
      |> String.downcase()
    else
      normalized
    end
  end

  defp windows_path_fragment?(value) do
    Regex.match?(~r/[A-Za-z]:[\\\/]/, value)
  end

  defp convert_duration_to_ms(duration) do
    duration
    |> System.convert_time_unit(:native, :microsecond)
    |> div(1000)
  end

  # -- configure helpers ----------------------------------------------------

  defp configure_with_endpoint(endpoint, env, opts) do
    exporter_spec = build_exporter_spec(endpoint, env, opts)
    processors = build_processors(exporter_spec, opts)

    enable_otel_tracing()
    reset_otel_apps()
    Application.put_env(:opentelemetry, :processors, processors)

    with :ok <- maybe_start_exporter(exporter_spec),
         :ok <- maybe_start_app(:opentelemetry),
         :ok <- attach_tracing_handler() do
      set_otlp_configured(true)
      :ok
    else
      {:error, reason} ->
        Logger.warning("failed to configure OpenTelemetry exporter: #{inspect(reason)}")
        :ok
    end
  end

  defp resolve_env(nil), do: System.get_env()
  defp resolve_env(env) when is_map(env), do: env

  defp parse_boolean(nil), do: :error
  defp parse_boolean(value) when is_boolean(value), do: {:ok, value}
  defp parse_boolean(value) when is_integer(value) and value in [0, 1], do: {:ok, value == 1}

  @truthy_strings ~w(1 true yes on) |> MapSet.new()
  @falsy_strings ~w(0 false no off) |> MapSet.new()

  defp parse_boolean(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    cond do
      normalized in @truthy_strings -> {:ok, true}
      normalized in @falsy_strings -> {:ok, false}
      true -> :error
    end
  end

  defp parse_boolean(_), do: :error

  defp otlp_configured? do
    Application.get_env(:codex_sdk, @otlp_configured_key, false)
  end

  defp set_otlp_configured(value) when is_boolean(value) do
    Application.put_env(:codex_sdk, @otlp_configured_key, value)
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp enable_otel_tracing do
    Application.put_env(:opentelemetry, :tracer, :otel_trace)
    Application.put_env(:opentelemetry, :meter, :otel_meter)
    Application.put_env(:opentelemetry, :traces_exporter, :otlp)
    Application.put_env(:opentelemetry, :metrics_exporter, :otlp)
  end

  defp disable_otel_tracing do
    Application.put_env(:opentelemetry, :tracer, :none)
    Application.put_env(:opentelemetry, :meter, :none)
    Application.put_env(:opentelemetry, :traces_exporter, :none)
    Application.put_env(:opentelemetry, :metrics_exporter, :none)
  end

  defp build_exporter_spec(endpoint, env, opts) do
    case Keyword.get(opts, :exporter) do
      nil ->
        headers =
          env
          |> Map.get("CODEX_OTLP_HEADERS")
          |> parse_headers()

        ssl_options = build_ssl_options(env, opts)

        config =
          %{}
          |> Map.put(:endpoints, [endpoint])
          |> maybe_put(:headers, headers)
          |> maybe_put(:protocol, Keyword.get(opts, :protocol))
          |> maybe_put(:compression, Keyword.get(opts, :compression))
          |> maybe_put(:ssl_options, ssl_options)

        {:opentelemetry_exporter, config}

      {module, _} = exporter when is_atom(module) ->
        exporter

      module when is_atom(module) ->
        {module, []}

      exporter ->
        exporter
    end
  end

  defp parse_headers(nil), do: []

  defp parse_headers(headers) when is_binary(headers) do
    headers
    |> String.split([",", ";"], trim: true)
    |> Enum.reduce([], fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        [key, value] ->
          [{String.trim(key), String.trim(value)} | acc]

        [key] ->
          [{String.trim(key), ""} | acc]

        _ ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  defp parse_headers(list) when is_list(list), do: list
  defp parse_headers(_), do: []

  defp build_ssl_options(env, opts) do
    case Keyword.get(opts, :ssl_options) do
      value when is_list(value) and value != [] ->
        value

      value when is_map(value) ->
        Map.to_list(value)

      value when not is_nil(value) ->
        List.wrap(value)

      _ ->
        [
          {:certfile, env |> Map.get("CODEX_OTLP_CERTFILE") |> normalize_string()},
          {:keyfile, env |> Map.get("CODEX_OTLP_KEYFILE") |> normalize_string()},
          {:cacertfile,
           env |> Map.get("CODEX_OTLP_CACERTFILE") |> normalize_string() ||
             env |> Map.get("CODEX_OTLP_CA_CERTFILE") |> normalize_string()}
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    end
  end

  defp build_processors(exporter_spec, opts) do
    case Keyword.get(opts, :processors) do
      nil ->
        name = Keyword.get(opts, :processor_name, @default_processor_name)

        config =
          %{
            exporter: exporter_spec,
            name: name
          }
          |> maybe_put(:exporting_timeout_ms, Keyword.get(opts, :exporting_timeout_ms))
          |> maybe_put(:resource, Keyword.get(opts, :resource))

        [{:otel_simple_processor, config}]

      processors ->
        processors
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_start_app(app) do
    case Application.ensure_all_started(app) do
      {:ok, _} -> :ok
      {:error, {^app, {:already_started, _}}} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_start_exporter({:opentelemetry_exporter, _}) do
    with :ok <- maybe_start_app(:tls_certificate_check) do
      maybe_start_app(:opentelemetry_exporter)
    end
  end

  defp maybe_start_exporter({module, _})
       when module in [:otel_exporter_pid, :otel_exporter_stdout, :otel_exporter_tab] do
    with :ok <- maybe_start_app(:tls_certificate_check) do
      maybe_start_app(:opentelemetry_exporter)
    end
  end

  defp maybe_start_exporter(module) when module == :opentelemetry_exporter,
    do: maybe_start_exporter({module, []})

  defp maybe_start_exporter(_), do: :ok

  defp reset_otel_apps do
    _ = Application.stop(:opentelemetry)
    _ = Application.stop(:opentelemetry_exporter)
    _ = Application.stop(:tls_certificate_check)
    :ok
  end

  defp attach_tracing_handler do
    case :telemetry.attach_many(
           @otel_handler_id,
           @trace_events,
           &__MODULE__.handle_trace_event/4,
           %{}
         ) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  # -- span helpers ---------------------------------------------------------

  defp start_thread_span(_measurements, %{span_token: token} = metadata) do
    previous_ctx = Tracer.current_span_ctx()
    span_ctx = Tracer.start_span("codex.thread")
    Tracer.set_current_span(span_ctx)
    Span.set_attributes(span_ctx, thread_span_attributes(metadata))
    put_span_ctx(token, {span_ctx, previous_ctx})
    :ok
  end

  defp start_thread_span(_measurements, _metadata), do: :ok

  defp finish_thread_span(status, measurements, %{span_token: token} = metadata) do
    case pop_span_ctx(token) do
      nil ->
        :ok

      {span_ctx, previous_ctx} ->
        Tracer.set_current_span(span_ctx)
        maybe_set_duration_attribute(span_ctx, measurements)
        Span.set_attributes(span_ctx, finalize_thread_attributes(metadata))
        maybe_record_exception(span_ctx, status, metadata)
        maybe_set_status(span_ctx, status, metadata)
        Span.end_span(span_ctx)
        Tracer.set_current_span(previous_ctx)
        :ok
    end
  end

  defp finish_thread_span(_status, _measurements, _metadata), do: :ok

  @doc false
  @spec thread_span_attributes(map()) :: map()
  def thread_span_attributes(metadata) do
    metadata
    |> Map.take([
      :thread_id,
      :turn_id,
      :originator,
      :workflow,
      :group,
      :trace_id,
      :trace_sensitive
    ])
    |> Enum.reduce(%{}, fn
      {:thread_id, value}, acc when not is_nil(value) ->
        Map.put(acc, :"codex.thread.id", value)

      {:turn_id, value}, acc when not is_nil(value) ->
        Map.put(acc, :"codex.turn.id", value)

      {:originator, value}, acc ->
        Map.put(acc, :"codex.originator", format_originator(value))

      {:workflow, value}, acc when not is_nil(value) ->
        Map.put(acc, :"codex.workflow", value)

      {:group, value}, acc when not is_nil(value) ->
        Map.put(acc, :"codex.group", value)

      {:trace_id, value}, acc when not is_nil(value) ->
        Map.put(acc, :"codex.trace_id", value)

      {:trace_sensitive, value}, acc when not is_nil(value) ->
        Map.put(acc, :"codex.trace.sensitive_data", value)

      _, acc ->
        acc
    end)
  end

  @doc false
  @spec finalize_thread_attributes(map()) :: map()
  def finalize_thread_attributes(metadata) do
    metadata
    |> Map.take([:result, :thread_id, :turn_id, :source, :early_exit?])
    |> Enum.reduce(%{}, fn
      {:result, value}, acc when not is_nil(value) ->
        Map.put(acc, :"codex.thread.result", to_string(value))

      {:thread_id, value}, acc when not is_nil(value) ->
        Map.put(acc, :"codex.thread.id", value)

      {:turn_id, value}, acc when not is_nil(value) ->
        Map.put(acc, :"codex.turn.id", value)

      {:source, value}, acc when not is_nil(value) ->
        Map.put(acc, :"codex.source", format_source(value))

      {:early_exit?, true}, acc ->
        Map.put(acc, :"codex.thread.early_exit", true)

      _, acc ->
        acc
    end)
  end

  defp format_source(%{} = source) do
    case Jason.encode(source) do
      {:ok, encoded} -> encoded
      _ -> inspect(source)
    end
  end

  defp format_source(value) when is_atom(value), do: Atom.to_string(value)
  defp format_source(value) when is_binary(value), do: value
  defp format_source(value), do: to_string(value)

  defp format_originator(nil), do: "sdk"
  defp format_originator(value) when is_atom(value), do: Atom.to_string(value)
  defp format_originator(value), do: to_string(value)

  defp put_span_ctx(token, span_ctx), do: Process.put({@otel_handler_id, token}, span_ctx)

  defp pop_span_ctx(token) do
    key = {@otel_handler_id, token}

    case Process.get(key) do
      nil ->
        nil

      span_ctx ->
        Process.delete(key)
        span_ctx
    end
  end

  defp maybe_set_duration_attribute(span_ctx, measurements) do
    case Map.get(measurements, :duration_ms) do
      value when is_integer(value) ->
        Span.set_attribute(span_ctx, :"codex.duration_ms", value)

      _ ->
        :ok
    end
  end

  defp maybe_record_exception(span_ctx, :exception, metadata) do
    reason = Map.get(metadata, :reason)

    cond do
      is_nil(reason) ->
        :ok

      is_exception(reason) ->
        Span.record_exception(span_ctx, reason)

      true ->
        Span.add_event(span_ctx, :"codex.exception", [{:"exception.message", inspect(reason)}])
    end
  end

  defp maybe_record_exception(_span_ctx, _status, _metadata), do: :ok

  defp maybe_set_status(span_ctx, :exception, metadata) do
    reason = Map.get(metadata, :reason)
    Span.set_status(span_ctx, OpenTelemetry.status(:error, format_status_reason(reason)))
  end

  defp maybe_set_status(_span_ctx, _status, _metadata), do: :ok

  defp format_status_reason(reason) do
    cond do
      is_nil(reason) -> "thread exception"
      is_exception(reason) -> Exception.message(reason)
      true -> inspect(reason)
    end
  end

  # -- Realtime telemetry helpers ---------------------------------------------

  @doc """
  Emits telemetry for realtime session start.
  """
  @spec realtime_session_start(map()) :: :ok
  def realtime_session_start(metadata) do
    :telemetry.execute(
      [:codex, :realtime, :session, :start],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits telemetry for realtime session stop.
  """
  @spec realtime_session_stop(map(), map()) :: :ok
  def realtime_session_stop(metadata, measurements \\ %{}) do
    :telemetry.execute(
      [:codex, :realtime, :session, :stop],
      Map.merge(%{system_time: System.system_time()}, measurements),
      metadata
    )
  end

  @doc """
  Emits telemetry for realtime audio send events.
  """
  @spec realtime_audio_send(map()) :: :ok
  def realtime_audio_send(metadata) do
    :telemetry.execute(
      [:codex, :realtime, :audio, :send],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits telemetry for realtime audio receive events.
  """
  @spec realtime_audio_receive(map()) :: :ok
  def realtime_audio_receive(metadata) do
    :telemetry.execute(
      [:codex, :realtime, :audio, :receive],
      %{system_time: System.system_time()},
      metadata
    )
  end

  # -- Voice telemetry helpers ------------------------------------------------

  @doc """
  Emits telemetry for voice pipeline start.
  """
  @spec voice_pipeline_start(map()) :: :ok
  def voice_pipeline_start(metadata) do
    :telemetry.execute(
      [:codex, :voice, :pipeline, :start],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits telemetry for voice pipeline stop.
  """
  @spec voice_pipeline_stop(map(), map()) :: :ok
  def voice_pipeline_stop(metadata, measurements \\ %{}) do
    :telemetry.execute(
      [:codex, :voice, :pipeline, :stop],
      Map.merge(%{system_time: System.system_time()}, measurements),
      metadata
    )
  end

  @doc """
  Emits telemetry for voice transcription start.
  """
  @spec voice_transcription_start(map()) :: :ok
  def voice_transcription_start(metadata) do
    :telemetry.execute(
      [:codex, :voice, :transcription, :start],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits telemetry for voice transcription stop.
  """
  @spec voice_transcription_stop(map(), map()) :: :ok
  def voice_transcription_stop(metadata, measurements \\ %{}) do
    :telemetry.execute(
      [:codex, :voice, :transcription, :stop],
      Map.merge(%{system_time: System.system_time()}, measurements),
      metadata
    )
  end

  @doc """
  Emits telemetry for voice synthesis start.
  """
  @spec voice_synthesis_start(map()) :: :ok
  def voice_synthesis_start(metadata) do
    :telemetry.execute(
      [:codex, :voice, :synthesis, :start],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits telemetry for voice synthesis stop.
  """
  @spec voice_synthesis_stop(map(), map()) :: :ok
  def voice_synthesis_stop(metadata, measurements \\ %{}) do
    :telemetry.execute(
      [:codex, :voice, :synthesis, :stop],
      Map.merge(%{system_time: System.system_time()}, measurements),
      metadata
    )
  end
end

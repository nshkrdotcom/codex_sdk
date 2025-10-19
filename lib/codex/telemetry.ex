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

  @trace_events @thread_events
  @otel_handler_id "codex-otel-tracing"
  @default_originator :sdk
  @default_processor_name :codex_sdk_processor

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
    enabled? = Keyword.get(opts, :enabled?, Application.get_env(:codex_sdk, :enable_otlp?, false))

    if enabled? do
      endpoint = env |> Map.get("CODEX_OTLP_ENDPOINT") |> normalize_string()

      if is_nil(endpoint) do
        :ok
      else
        exporter_spec = build_exporter_spec(endpoint, env, opts)
        processors = build_processors(exporter_spec, opts)

        reset_otel_apps()
        Application.put_env(:opentelemetry, :processors, processors)

        with :ok <- maybe_start_exporter(exporter_spec),
             :ok <- maybe_start_app(:opentelemetry),
             :ok <- attach_tracing_handler() do
          :ok
        else
          {:error, reason} ->
            Logger.warning("failed to configure OpenTelemetry exporter: #{inspect(reason)}")
            :ok
        end
      end
    else
      reset_otel_apps()
      Application.put_env(:opentelemetry, :processors, [])
      :ok
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

    Logger.log(level, fn ->
      "[codex] thread stop duration_ms=#{duration_ms} thread_id=#{inspect(Map.get(metadata, :thread_id))}"
    end)
  end

  def handle_event([:codex, :thread, :exception], measurements, metadata, _config) do
    duration_ms = Map.get(measurements, :duration_ms)
    reason = Map.get(metadata, :reason)

    Logger.log(:error, fn ->
      "[codex] thread exception duration_ms=#{duration_ms} thread_id=#{inspect(Map.get(metadata, :thread_id))} reason=#{inspect(reason)}"
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
    Map.put_new(metadata, :originator, @default_originator)
  end

  defp normalize_metadata(metadata) when is_list(metadata) do
    metadata
    |> Map.new()
    |> normalize_metadata()
  end

  defp normalize_metadata(_), do: %{originator: @default_originator}

  defp convert_duration_to_ms(duration) do
    duration
    |> System.convert_time_unit(:native, :microsecond)
    |> div(1000)
  end

  # -- configure helpers ----------------------------------------------------

  defp resolve_env(nil), do: System.get_env()
  defp resolve_env(env) when is_map(env), do: env

  defp normalize_string(nil), do: nil

  defp normalize_string(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp build_exporter_spec(endpoint, env, opts) do
    case Keyword.get(opts, :exporter) do
      nil ->
        headers =
          env
          |> Map.get("CODEX_OTLP_HEADERS")
          |> parse_headers()

        config =
          %{}
          |> Map.put(:endpoints, [endpoint])
          |> maybe_put(:headers, headers)
          |> maybe_put(:protocol, Keyword.get(opts, :protocol))
          |> maybe_put(:compression, Keyword.get(opts, :compression))

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
    with :ok <- maybe_start_app(:tls_certificate_check),
         :ok <- maybe_start_app(:opentelemetry_exporter) do
      :ok
    end
  end

  defp maybe_start_exporter({module, _})
       when module in [:otel_exporter_pid, :otel_exporter_stdout, :otel_exporter_tab],
       do: :ok

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

  defp thread_span_attributes(metadata) do
    metadata
    |> Map.take([:thread_id, :originator])
    |> Enum.reduce(%{}, fn
      {:thread_id, value}, acc when not is_nil(value) ->
        Map.put(acc, :"codex.thread.id", value)

      {:originator, value}, acc ->
        Map.put(acc, :"codex.originator", format_originator(value))

      _, acc ->
        acc
    end)
  end

  defp finalize_thread_attributes(metadata) do
    metadata
    |> Map.take([:result])
    |> Enum.reduce(%{}, fn
      {:result, value}, acc when not is_nil(value) ->
        Map.put(acc, :"codex.thread.result", to_string(value))

      _, acc ->
        acc
    end)
  end

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
end

defmodule Codex.Telemetry do
  @moduledoc """
  Telemetry helpers and default logging for Codex events.
  """

  require Logger

  @thread_events [
    [:codex, :thread, :start],
    [:codex, :thread, :stop],
    [:codex, :thread, :exception]
  ]

  @doc """
  Emits a telemetry event with the given measurements and metadata.
  """
  @spec emit([atom()], map(), map()) :: :ok
  def emit(event, measurements \\ %{}, metadata \\ %{}) do
    :telemetry.execute(event, measurements, metadata)
  end

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
    duration_us = System.convert_time_unit(measurements.duration, :native, :microsecond)

    Logger.log(level, fn ->
      "[codex] thread stop duration_us=#{duration_us} thread_id=#{inspect(Map.get(metadata, :thread_id))}"
    end)
  end

  def handle_event([:codex, :thread, :exception], measurements, metadata, _config) do
    duration_us = System.convert_time_unit(measurements.duration, :native, :microsecond)
    reason = Map.get(metadata, :reason)

    Logger.log(:error, fn ->
      "[codex] thread exception duration_us=#{duration_us} thread_id=#{inspect(Map.get(metadata, :thread_id))} reason=#{inspect(reason)}"
    end)
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok
end

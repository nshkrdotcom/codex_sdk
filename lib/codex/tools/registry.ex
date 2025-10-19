defmodule Codex.Tools.Registry do
  @moduledoc false

  alias Codex.Telemetry
  alias Codex.Tools
  alias Codex.Tools.Handle

  @table :codex_tools_registry

  @doc false
  def register(%{name: name, module: module, metadata: metadata}) do
    ensure_table()

    case :ets.lookup(@table, name) do
      [] ->
        true = :ets.insert(@table, {name, module, metadata})
        {:ok, %Handle{name: name, module: module}}

      _ ->
        {:error, {:already_registered, name}}
    end
  end

  @doc false
  def deregister(%Handle{name: name}) do
    ensure_table()
    :ets.delete(@table, name)
    :ok
  end

  @doc false
  def lookup(name) when is_binary(name) do
    ensure_table()

    case :ets.lookup(@table, name) do
      [{^name, module, metadata}] ->
        {:ok, %{name: name, module: module, metadata: metadata}}

      [] ->
        {:error, :not_found}
    end
  end

  @doc false
  def invoke(name, args, context) when is_binary(name) do
    with {:ok, %{module: module, metadata: metadata} = info} <- lookup(name) do
      normalized_args = Map.new(args)

      full_context =
        context
        |> Map.put(:tool, %{name: info.name, metadata: metadata})
        |> Map.put(:metadata, metadata)

      telemetry_meta =
        build_telemetry_metadata(
          info.name,
          module,
          metadata,
          normalized_args,
          full_context
        )
        |> Map.put(:originator, :sdk)
        |> Map.put(:span_token, make_ref())

      Telemetry.emit(
        [:codex, :tool, :start],
        %{system_time: System.system_time()},
        telemetry_meta
      )

      started = System.monotonic_time()

      case safe_invoke(module, normalized_args, full_context) do
        {:ok, output} ->
          duration = System.monotonic_time() - started
          Tools.record_invocation(info.name, :success, duration_to_ms(duration))

          Telemetry.emit(
            [:codex, :tool, :success],
            %{duration: duration, system_time: System.system_time()},
            telemetry_meta
            |> Map.put(:output, output)
            |> Map.put(:result, :ok)
          )

          {:ok, output}

        {:error, reason} = error ->
          duration = System.monotonic_time() - started
          Tools.record_invocation(info.name, :failure, duration_to_ms(duration), reason)

          Telemetry.emit(
            [:codex, :tool, :failure],
            %{duration: duration, system_time: System.system_time()},
            telemetry_meta
            |> Map.put(:error, reason)
            |> Map.put(:result, :error)
          )

          error
      end
    end
  end

  defp safe_invoke(module, args, context) do
    try do
      module.invoke(args, context)
    rescue
      error -> {:error, {:tool_exception, module, error}}
    catch
      kind, reason -> {:error, {:tool_failure, module, {kind, reason}}}
    end
  end

  @doc false
  def reset! do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _ -> :ets.delete(@table)
    end

    ensure_table()
    :ok
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        :ok
    end
  end

  defp build_telemetry_metadata(tool, module, metadata, args, context) do
    event = Map.get(context, :event)
    thread = Map.get(context, :thread)

    %{
      tool: tool,
      module: module,
      metadata: metadata,
      arguments: args,
      retry?: Map.get(context, :retry?, false),
      attempt: Map.get(context, :attempt),
      call_id: event && Map.get(event, :call_id),
      thread_id: thread && Map.get(thread, :thread_id)
    }
  end

  defp duration_to_ms(duration_native) when is_integer(duration_native) do
    duration_native
    |> System.convert_time_unit(:native, :microsecond)
    |> div(1000)
  end
end

defmodule Codex.Approvals do
  @moduledoc """
  Approval helpers invoked by the auto-run pipeline when actions require consent.

  Supports both synchronous and asynchronous approval workflows via pluggable hooks.
  """

  alias Codex.Approvals.StaticPolicy
  alias Codex.Telemetry

  @type decision :: :allow | {:deny, String.t()}
  @type async_result :: {:async, reference()} | {:async, reference(), metadata :: map()}
  @type review_result :: decision() | async_result()

  @doc """
  Reviews a tool invocation given the configured policy or hook.

  ## Parameters
  - `policy_or_hook` - StaticPolicy struct, hook module, or nil
  - `event` - Tool call event (must contain `:tool_name` and `:call_id`)
  - `context` - Approval context
  - `opts` - Optional keyword list with `:timeout` (default: 30_000ms)

  ## Returns
  - `:allow` - approve the operation
  - `{:deny, reason}` - deny with reason
  - `{:async, ref}` or `{:async, ref, metadata}` - async approval pending

  ## Telemetry
  Emits the following events:
  - `[:codex, :approval, :requested]` - when approval is requested
  - `[:codex, :approval, :approved]` - when synchronously approved
  - `[:codex, :approval, :denied]` - when denied
  - `[:codex, :approval, :timeout]` - when async approval times out
  """
  @spec review_tool(term(), map(), map(), keyword()) :: review_result()
  def review_tool(policy_or_hook, event, context, opts \\ [])

  def review_tool(_policy_or_hook, %{requires_approval: false}, _context, _opts), do: :allow
  def review_tool(_policy_or_hook, %{"requires_approval" => false}, _context, _opts), do: :allow

  def review_tool(policy_or_hook, event, context, opts) do
    if approved_by_policy?(event) do
      :allow
    else
      do_review_tool(policy_or_hook, event, context, opts)
    end
  end

  # Nil policy - allow by default
  defp do_review_tool(nil, _event, _context, _opts), do: :allow

  # StaticPolicy - backwards compatible
  defp do_review_tool(%StaticPolicy{} = policy, event, context, _opts) do
    emit_requested_telemetry(event)
    started = System.monotonic_time()

    result = StaticPolicy.review_tool(policy, event, context)

    emit_result_telemetry(result, event, started)
    result
  end

  # Hook module - new behaviour
  defp do_review_tool(module, event, context, opts) when is_atom(module) do
    emit_requested_telemetry(event)
    started = System.monotonic_time()
    timeout = Keyword.get(opts, :timeout, 30_000)

    prepared_context = maybe_prepare_context(module, event, context)

    module.review_tool(event, prepared_context, opts)
    |> handle_review_result(module, event, started, timeout)
  end

  defp do_review_tool(_policy_or_hook, _event, _context, _opts), do: :allow

  defp maybe_prepare_context(module, event, context) do
    if function_exported?(module, :prepare, 2) do
      case module.prepare(event, context) do
        {:ok, new_context} -> new_context
        _ -> context
      end
    else
      context
    end
  end

  defp handle_review_result(:allow = result, _module, event, started, _timeout) do
    emit_result_telemetry(result, event, started)
    result
  end

  defp handle_review_result({:deny, _reason} = result, _module, event, started, _timeout) do
    emit_result_telemetry(result, event, started)
    result
  end

  defp handle_review_result({:async, ref} = result, module, event, started, timeout) do
    maybe_await(module, ref, result, event, started, timeout)
  end

  defp handle_review_result({:async, ref, _metadata} = result, module, event, started, timeout) do
    maybe_await(module, ref, result, event, started, timeout)
  end

  defp maybe_await(module, ref, fallback, event, started, timeout) do
    if function_exported?(module, :await, 2) do
      module.await(ref, timeout)
      |> handle_await_result(event, started)
    else
      fallback
    end
  end

  defp handle_await_result({:ok, decision}, event, started) do
    emit_result_telemetry(decision, event, started)
    decision
  end

  defp handle_await_result({:error, :timeout}, event, started) do
    emit_timeout_telemetry(event, started)
    {:deny, "approval timeout"}
  end

  defp handle_await_result({:error, reason}, event, started) do
    result = {:deny, "approval error: #{inspect(reason)}"}
    emit_result_telemetry(result, event, started)
    result
  end

  defp emit_requested_telemetry(event) do
    Telemetry.emit(
      [:codex, :approval, :requested],
      %{system_time: System.system_time()},
      approval_metadata(event)
    )
  end

  defp emit_result_telemetry(:allow, event, started) do
    duration = System.monotonic_time() - started

    Telemetry.emit(
      [:codex, :approval, :approved],
      %{duration: duration, system_time: System.system_time()},
      approval_metadata(event)
    )
  end

  defp emit_result_telemetry({:deny, reason}, event, started) do
    duration = System.monotonic_time() - started

    Telemetry.emit(
      [:codex, :approval, :denied],
      %{duration: duration, system_time: System.system_time()},
      approval_metadata(event, %{reason: reason})
    )
  end

  defp emit_timeout_telemetry(event, started) do
    duration = System.monotonic_time() - started

    Telemetry.emit(
      [:codex, :approval, :timeout],
      %{duration: duration, system_time: System.system_time()},
      approval_metadata(event)
    )
  end

  # Helper to get field from event (handles both structs and maps)
  defp get_event_field(%{__struct__: _} = event, field) do
    Map.get(event, field)
  end

  defp get_event_field(event, field) when is_map(event) do
    event[field] || event[to_string(field)]
  end

  defp approved_by_policy?(event) when is_map(event) do
    event
    |> Map.take([:approved, "approved", :approved_by_policy, "approved_by_policy"])
    |> Map.values()
    |> Enum.any?(&truthy?/1)
  end

  defp approved_by_policy?(_event), do: false

  defp truthy?(value) when value in [true, "true", "TRUE", "True"], do: true
  defp truthy?(_), do: false

  defp approval_metadata(event, extra \\ %{}) do
    %{
      tool: get_event_field(event, :tool_name),
      call_id: get_event_field(event, :call_id),
      thread_id: get_event_field(event, :thread_id),
      turn_id: get_event_field(event, :turn_id),
      source: approval_source(event),
      originator: :sdk
    }
    |> Map.merge(extra)
  end

  defp approval_source(event) do
    get_event_field(event, :source) ||
      get_event_field(event, "source") ||
      if approved_by_policy?(event), do: :policy, else: :user
  end
end

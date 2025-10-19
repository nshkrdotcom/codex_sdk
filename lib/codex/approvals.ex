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

  # Nil policy - allow by default
  def review_tool(nil, _event, _context, _opts), do: :allow

  # StaticPolicy - backwards compatible
  def review_tool(%StaticPolicy{} = policy, event, context, _opts) do
    emit_requested_telemetry(event)
    started = System.monotonic_time()

    result = StaticPolicy.review_tool(policy, event, context)

    emit_result_telemetry(result, event, started)
    result
  end

  # Hook module - new behaviour
  def review_tool(module, event, context, opts) when is_atom(module) do
    emit_requested_telemetry(event)
    started = System.monotonic_time()
    timeout = Keyword.get(opts, :timeout, 30_000)

    # Call prepare if available
    context =
      if function_exported?(module, :prepare, 2) do
        case module.prepare(event, context) do
          {:ok, new_context} -> new_context
          {:error, _} -> context
        end
      else
        context
      end

    # Call review_tool
    case module.review_tool(event, context, opts) do
      :allow = result ->
        emit_result_telemetry(result, event, started)
        result

      {:deny, _reason} = result ->
        emit_result_telemetry(result, event, started)
        result

      {:async, ref} ->
        # Handle async - await if the hook supports it
        if function_exported?(module, :await, 2) do
          # Store test_pid in process dictionary for hook to access
          case module.await(ref, timeout) do
            {:ok, decision} ->
              emit_result_telemetry(decision, event, started)
              decision

            {:error, :timeout} ->
              emit_timeout_telemetry(event, started)
              {:deny, "approval timeout"}

            {:error, reason} ->
              result = {:deny, "approval error: #{inspect(reason)}"}
              emit_result_telemetry(result, event, started)
              result
          end
        else
          # Hook doesn't support await, return async
          {:async, ref}
        end

      {:async, ref, metadata} ->
        if function_exported?(module, :await, 2) do
          case module.await(ref, timeout) do
            {:ok, decision} ->
              emit_result_telemetry(decision, event, started)
              decision

            {:error, :timeout} ->
              emit_timeout_telemetry(event, started)
              {:deny, "approval timeout"}

            {:error, reason} ->
              result = {:deny, "approval error: #{inspect(reason)}"}
              emit_result_telemetry(result, event, started)
              result
          end
        else
          {:async, ref, metadata}
        end
    end
  end

  defp emit_requested_telemetry(event) do
    tool_name = get_event_field(event, :tool_name)
    call_id = get_event_field(event, :call_id)

    Telemetry.emit(
      [:codex, :approval, :requested],
      %{system_time: System.system_time()},
      %{
        tool: tool_name,
        call_id: call_id,
        originator: :sdk
      }
    )
  end

  defp emit_result_telemetry(:allow, event, started) do
    duration = System.monotonic_time() - started
    tool_name = get_event_field(event, :tool_name)

    Telemetry.emit(
      [:codex, :approval, :approved],
      %{duration: duration, system_time: System.system_time()},
      %{
        tool: tool_name,
        originator: :sdk
      }
    )
  end

  defp emit_result_telemetry({:deny, reason}, event, started) do
    duration = System.monotonic_time() - started
    tool_name = get_event_field(event, :tool_name)

    Telemetry.emit(
      [:codex, :approval, :denied],
      %{duration: duration, system_time: System.system_time()},
      %{
        tool: tool_name,
        reason: reason,
        originator: :sdk
      }
    )
  end

  defp emit_timeout_telemetry(event, started) do
    duration = System.monotonic_time() - started
    tool_name = get_event_field(event, :tool_name)

    Telemetry.emit(
      [:codex, :approval, :timeout],
      %{duration: duration, system_time: System.system_time()},
      %{
        tool: tool_name,
        originator: :sdk
      }
    )
  end

  # Helper to get field from event (handles both structs and maps)
  defp get_event_field(%{__struct__: _} = event, field) do
    Map.get(event, field)
  end

  defp get_event_field(event, field) when is_map(event) do
    event[field] || event[to_string(field)]
  end
end

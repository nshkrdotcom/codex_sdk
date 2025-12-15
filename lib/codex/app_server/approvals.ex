defmodule Codex.AppServer.Approvals do
  @moduledoc false

  require Logger

  alias Codex.Approvals.Hook
  alias Codex.AppServer.ApprovalDecision
  alias Codex.AppServer.Connection
  alias Codex.Thread

  @spec maybe_auto_respond(
          Connection.connection(),
          Thread.t(),
          Connection.request_id(),
          String.t(),
          map()
        ) ::
          :ok | :ignore
  def maybe_auto_respond(conn, %Thread{} = thread, id, method, params)
      when is_pid(conn) and (is_integer(id) or is_binary(id)) and is_binary(method) and
             is_map(params) do
    case approval_handler(thread) do
      nil ->
        :ignore

      handler ->
        do_auto_respond(conn, handler, thread, id, method, params)
    end
  end

  def maybe_auto_respond(_conn, _thread, _id, _method, _params), do: :ignore

  defp approval_handler(%Thread{} = thread) do
    thread.thread_opts.approval_hook || thread.thread_opts.approval_policy
  end

  defp do_auto_respond(conn, handler, %Thread{} = thread, id, method, params) do
    with {:ok, callback, event} <- approval_event(method, params),
         :ok <- ensure_matches_thread(thread, event),
         {:ok, decision} <- review(handler, callback, event, thread),
         :ok <- Connection.respond(conn, id, %{decision: ApprovalDecision.from_hook(decision)}) do
      :ok
    else
      :ignore ->
        :ignore

      {:error, reason} ->
        Logger.debug("Failed to auto-respond to app-server approval request: #{inspect(reason)}")

        _ =
          Connection.respond(conn, id, %{
            decision: ApprovalDecision.from_hook({:deny, "approval error: #{inspect(reason)}"})
          })

        :ok
    end
  end

  defp approval_event("item/commandExecution/requestApproval", %{} = params) do
    {:ok, :review_command,
     %{
       type: :command_execution_approval,
       thread_id: Map.get(params, "threadId") || Map.get(params, "thread_id") || "",
       turn_id: Map.get(params, "turnId") || Map.get(params, "turn_id") || "",
       item_id: Map.get(params, "itemId") || Map.get(params, "item_id") || "",
       reason: Map.get(params, "reason"),
       proposed_execpolicy_amendment:
         Map.get(params, "proposedExecpolicyAmendment") ||
           Map.get(params, "proposed_execpolicy_amendment")
     }}
  end

  defp approval_event("item/fileChange/requestApproval", %{} = params) do
    {:ok, :review_file,
     %{
       type: :file_change_approval,
       thread_id: Map.get(params, "threadId") || Map.get(params, "thread_id") || "",
       turn_id: Map.get(params, "turnId") || Map.get(params, "turn_id") || "",
       item_id: Map.get(params, "itemId") || Map.get(params, "item_id") || "",
       reason: Map.get(params, "reason"),
       grant_root: Map.get(params, "grantRoot") || Map.get(params, "grant_root")
     }}
  end

  defp approval_event(_method, _params), do: :ignore

  defp ensure_matches_thread(%Thread{thread_id: nil}, _event), do: :ok

  defp ensure_matches_thread(%Thread{thread_id: thread_id}, %{thread_id: thread_id})
       when is_binary(thread_id),
       do: :ok

  defp ensure_matches_thread(%Thread{thread_id: thread_id}, %{thread_id: other})
       when is_binary(thread_id) and is_binary(other) and other != "" and thread_id != "" do
    {:error, {:thread_id_mismatch, thread_id, other}}
  end

  defp ensure_matches_thread(_thread, _event), do: :ok

  defp review(handler, callback, event, %Thread{} = thread) do
    timeout = thread.thread_opts.approval_timeout_ms || 30_000

    base_context = %{
      thread: thread,
      metadata: thread.thread_opts.metadata || %{},
      transport: :app_server
    }

    context = prepare_context(handler, event, base_context)
    opts = []

    try do
      handler
      |> invoke_review(callback, event, context, opts)
      |> then(&resolve_decision(handler, &1, timeout))
    rescue
      exception ->
        {:error, {:hook_crash, exception}}
    end
  end

  defp prepare_context(handler, event, context) do
    if function_exported?(handler, :prepare, 2) do
      case handler.prepare(event, context) do
        {:ok, prepared} when is_map(prepared) -> prepared
        _ -> context
      end
    else
      context
    end
  end

  defp invoke_review(handler, :review_command, event, context, opts) do
    if function_exported?(handler, :review_command, 3) do
      handler.review_command(event, context, opts)
    else
      Hook.default_review(event, context, opts)
    end
  end

  defp invoke_review(handler, :review_file, event, context, opts) do
    if function_exported?(handler, :review_file, 3) do
      handler.review_file(event, context, opts)
    else
      Hook.default_review(event, context, opts)
    end
  end

  defp resolve_decision(_handler, :allow, _timeout), do: {:ok, :allow}
  defp resolve_decision(_handler, {:allow, _opts} = decision, _timeout), do: {:ok, decision}
  defp resolve_decision(_handler, {:deny, _reason} = decision, _timeout), do: {:ok, decision}

  defp resolve_decision(handler, {:async, ref}, timeout),
    do: await_decision(handler, ref, timeout)

  defp resolve_decision(handler, {:async, ref, _metadata}, timeout),
    do: await_decision(handler, ref, timeout)

  defp resolve_decision(_handler, other, _timeout), do: {:error, {:invalid_hook_decision, other}}

  defp await_decision(handler, ref, timeout) do
    if function_exported?(handler, :await, 2) do
      case handler.await(ref, timeout) do
        {:ok, decision} -> resolve_decision(handler, decision, timeout)
        {:error, :timeout} -> {:ok, {:deny, "approval timeout"}}
        {:error, reason} -> {:ok, {:deny, "approval error: #{inspect(reason)}"}}
      end
    else
      {:ok, {:deny, "async approval not supported"}}
    end
  end
end

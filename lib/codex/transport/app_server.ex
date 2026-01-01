defmodule Codex.Transport.AppServer do
  @moduledoc false

  @behaviour Codex.Transport

  alias Codex.AppServer
  alias Codex.AppServer.Approvals, as: AppServerApprovals
  alias Codex.AppServer.Connection
  alias Codex.AppServer.NotificationAdapter
  alias Codex.Config.Overrides
  alias Codex.Events
  alias Codex.Models
  alias Codex.Options
  alias Codex.Thread
  alias Codex.Transport.Support
  alias Codex.Turn.Result

  @impl true
  def run_turn(%Thread{transport: {:app_server, _pid}} = thread, input, turn_opts)
      when is_binary(input) or is_list(input) do
    turn_opts = Support.normalize_turn_opts(turn_opts)

    Support.with_retry_and_rate_limit(
      fn -> run_turn_once(thread, input, turn_opts) end,
      thread.thread_opts,
      turn_opts
    )
  end

  @impl true
  def run_turn_streamed(%Thread{transport: {:app_server, conn}} = thread, input, turn_opts)
      when (is_binary(input) or is_list(input)) and is_pid(conn) do
    turn_opts = Support.normalize_turn_opts(turn_opts)

    Support.with_retry_and_rate_limit(
      fn -> run_turn_streamed_once(thread, input, turn_opts) end,
      thread.thread_opts,
      turn_opts
    )
  end

  defp run_turn_once(%Thread{} = thread, input, turn_opts) do
    with {:ok, stream} <- run_turn_streamed_once(thread, input, turn_opts) do
      events = Enum.to_list(stream)

      {updated_thread, final_response, usage} =
        Thread.reduce_events(thread, events, %{structured_output?: false})

      updated_thread =
        updated_thread
        |> Map.put(:usage, usage || thread.usage)
        |> Map.put(:pending_tool_outputs, [])
        |> Map.put(:pending_tool_failures, [])

      {:ok,
       %Result{
         thread: updated_thread,
         events: events,
         final_response: final_response,
         usage: usage,
         raw: %{transport: :app_server},
         attempts: 1,
         last_response_id: Thread.last_response_id(events)
       }}
    end
  end

  defp run_turn_streamed_once(%Thread{transport: {:app_server, conn}} = thread, input, turn_opts) do
    :ok = Connection.subscribe(conn)

    with {:ok, thread_id, started_event, thread_start_raw} <- ensure_thread(conn, thread),
         {:ok, turn_id, turn_started_event, turn_start_raw} <-
           start_turn(conn, thread, thread_id, input, turn_opts) do
      thread = %Thread{thread | thread_id: thread_id}

      stream =
        Stream.resource(
          fn ->
            %{
              conn: conn,
              thread_id: thread_id,
              turn_id: turn_id,
              thread: thread,
              done?: false,
              buffer: [started_event, turn_started_event],
              raw: %{thread_start: thread_start_raw, turn_start: turn_start_raw},
              completion_timeout_ms: completion_timeout_ms(turn_opts)
            }
          end,
          &next_event/1,
          fn %{conn: conn} -> Connection.unsubscribe(conn) end
        )

      {:ok, stream}
    else
      {:error, _} = error ->
        Connection.unsubscribe(conn)
        error
    end
  end

  @impl true
  def interrupt(%Thread{transport: {:app_server, conn}, thread_id: thread_id}, turn_id)
      when is_pid(conn) and is_binary(turn_id) do
    if is_binary(thread_id) and thread_id != "" do
      AppServer.turn_interrupt(conn, thread_id, turn_id)
    else
      {:error, :missing_thread_id}
    end
  end

  defp completion_timeout_ms(%{} = turn_opts) do
    turn_opts
    |> Map.get(:completion_timeout_ms, Map.get(turn_opts, "completion_timeout_ms"))
    |> case do
      value when is_integer(value) and value > 0 -> value
      _ -> 300_000
    end
  end

  defp ensure_thread(conn, %Thread{} = thread) do
    params = thread_start_params(thread, :start)

    if is_binary(thread.thread_id) and thread.thread_id != "" do
      resume_thread(conn, thread.thread_id, thread_start_params(thread, :resume))
    else
      start_thread(conn, params)
    end
  end

  defp resume_thread(conn, thread_id, params) do
    case AppServer.thread_resume(conn, thread_id, params) do
      {:ok, response} ->
        thread_map = get_in(response, ["thread"]) || %{}

        {:ok, thread_id, %Events.ThreadStarted{thread_id: thread_id, metadata: thread_map},
         response}

      {:error, _} = error ->
        error
    end
  end

  defp start_thread(conn, params) do
    case AppServer.thread_start(conn, params) do
      {:ok, response} ->
        thread_map = get_in(response, ["thread"]) || %{}
        thread_id = Map.get(thread_map, "id") || ""

        {:ok, thread_id, %Events.ThreadStarted{thread_id: thread_id, metadata: thread_map},
         response}

      {:error, _} = error ->
        error
    end
  end

  defp thread_start_params(%Thread{} = thread, mode) do
    config =
      thread.thread_opts.config
      |> normalize_config()
      |> Overrides.merge_config(thread.codex_opts, thread.thread_opts)
      |> maybe_apply_reasoning_effort(thread, mode)

    model =
      thread.thread_opts.model ||
        default_model(thread, mode)

    %{}
    |> maybe_put(:model, model)
    |> maybe_put(:model_provider, thread.thread_opts.model_provider)
    |> maybe_put(:working_directory, thread.thread_opts.working_directory)
    |> maybe_put(:approval_policy, thread.thread_opts.ask_for_approval)
    |> maybe_put(:sandbox, thread.thread_opts.sandbox)
    |> maybe_put(:config, config)
    |> maybe_put(:base_instructions, thread.thread_opts.base_instructions)
    |> maybe_put(:developer_instructions, thread.thread_opts.developer_instructions)
    |> maybe_put(:experimental_raw_events, thread.thread_opts.experimental_raw_events)
  end

  defp start_turn(conn, %Thread{} = thread, thread_id, input, turn_opts) do
    sandbox_policy = fetch_opt(turn_opts, :sandbox_policy) || thread.thread_opts.sandbox_policy

    approval_policy =
      fetch_opt(turn_opts, :approval_policy) || thread.thread_opts.ask_for_approval

    model = fetch_opt(turn_opts, :model) || thread.thread_opts.model
    cwd = fetch_opt(turn_opts, :cwd) || thread.thread_opts.working_directory

    opts =
      []
      |> maybe_put_kw(:cwd, cwd)
      |> maybe_put_kw(:model, model)
      |> maybe_put_kw(:approval_policy, approval_policy)
      |> maybe_put_kw(:sandbox_policy, sandbox_policy)
      |> maybe_put_kw(:effort, fetch_opt(turn_opts, :effort))
      |> maybe_put_kw(:summary, fetch_opt(turn_opts, :summary))

    case AppServer.turn_start(conn, thread_id, input, opts) do
      {:ok, response} ->
        turn_id = get_in(response, ["turn", "id"]) || ""

        {:ok, turn_id, %Events.TurnStarted{thread_id: thread_id, turn_id: turn_id}, response}

      {:error, _} = error ->
        error
    end
  end

  defp next_event(%{done?: true} = state), do: {:halt, state}

  defp next_event(%{buffer: [event | rest]} = state),
    do: {[event], %{state | buffer: rest}}

  defp next_event(%{completion_timeout_ms: timeout_ms} = state) do
    receive do
      {:codex_notification, method, params} ->
        if notification_matches?(state, method, params) do
          {:ok, event} = NotificationAdapter.to_event(method, params)

          done? =
            match?(%Events.TurnCompleted{}, event) and
              Map.get(event, :thread_id) == state.thread_id and
              Map.get(event, :turn_id) == state.turn_id

          {[event], %{state | done?: done?}}
        else
          next_event(state)
        end

      {:codex_request, id, method, params} ->
        _ =
          if request_matches?(state, id, method, params) do
            AppServerApprovals.maybe_auto_respond(state.conn, state.thread, id, method, params)
          else
            :ignore
          end

        next_event(state)
    after
      timeout_ms ->
        {:halt, state}
    end
  end

  defp normalize_config(nil), do: nil
  defp normalize_config(%{} = config) when map_size(config) == 0, do: nil
  defp normalize_config(%{} = config), do: config
  defp normalize_config(_), do: nil

  defp maybe_apply_reasoning_effort(
         config,
         %Thread{codex_opts: %Options{reasoning_effort: nil}},
         _mode
       ),
       do: config

  defp maybe_apply_reasoning_effort(
         config,
         %Thread{codex_opts: %Options{reasoning_effort: effort}},
         :start
       ) do
    config = config || %{}

    if has_reasoning_effort?(config) do
      config
    else
      Map.put(config, "model_reasoning_effort", Models.reasoning_effort_to_string(effort))
    end
  end

  defp maybe_apply_reasoning_effort(config, _thread, _mode), do: config

  defp has_reasoning_effort?(%{} = config) do
    Map.has_key?(config, "model_reasoning_effort") ||
      Map.has_key?(config, :model_reasoning_effort)
  end

  defp default_model(%Thread{codex_opts: %Options{model: model}}, :start)
       when is_binary(model) and model != "" do
    model
  end

  defp default_model(_thread, _mode), do: nil

  defp request_matches?(%{thread_id: thread_id, turn_id: turn_id}, _id, method, params)
       when is_binary(method) and is_map(params) do
    approval_request_method?(method) and request_ids_match?(thread_id, turn_id, params)
  end

  defp request_matches?(_state, _id, _method, _params), do: false

  defp approval_request_method?(method),
    do: method in ["item/commandExecution/requestApproval", "item/fileChange/requestApproval"]

  defp request_ids_match?(thread_id, turn_id, params) do
    request_thread_id =
      fetch_any(params, ["threadId", "thread_id"]) || get_in(params, ["thread", "id"])

    request_turn_id = fetch_any(params, ["turnId", "turn_id"])

    matches_id?(thread_id, request_thread_id) and matches_id?(turn_id, request_turn_id)
  end

  defp notification_matches?(%{thread_id: thread_id, turn_id: turn_id}, method, params)
       when is_binary(method) and is_map(params) do
    params_thread_id =
      fetch_any(params, ["threadId", "thread_id"]) || get_in(params, ["thread", "id"])

    params_turn_id =
      fetch_any(params, ["turnId", "turn_id"]) || get_in(params, ["turn", "id"])

    matches_id?(thread_id, params_thread_id) and matches_id?(turn_id, params_turn_id)
  end

  defp notification_matches?(_state, _method, _params), do: false

  defp fetch_opt(%{} = map, key) when is_atom(key) do
    fetch_any(map, [key, Atom.to_string(key)])
  end

  defp fetch_any(%{} = map, keys) when is_list(keys) do
    Enum.find_value(keys, &Map.get(map, &1))
  end

  defp matches_id?(_expected, nil), do: true
  defp matches_id?(_expected, ""), do: true
  defp matches_id?(expected, expected), do: true
  defp matches_id?(_expected, _actual), do: false

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_kw(list, _key, nil), do: list
  defp maybe_put_kw(list, _key, ""), do: list
  defp maybe_put_kw(list, key, value), do: Keyword.put(list, key, value)
end

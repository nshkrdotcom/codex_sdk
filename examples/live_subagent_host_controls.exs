Mix.Task.run("app.start")

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias CodexExamples.Support

Support.init!()

alias Codex.{AppServer, Events, Items, RunResultStreaming, Subagents, Thread}
alias Codex.ExamplesSupport

defmodule CodexExamples.LiveSubagentHostControls do
  @moduledoc false

  @stream_wait_note """
  Waiting for streamed events. If the model stays quiet briefly, Codex is still working.
  """
  @thread_list_opts [sort_key: :updated_at, limit: 20, timeout_ms: 120_000]
  @thread_list_snapshot_opts [sort_key: :updated_at, limit: 20, timeout_ms: 5_000]
  @discovery_attempts 10
  @discovery_delay_ms 500
  @prompt_tool_kinds [:spawn_agent, :send_input, :resume_agent, :wait, :close_agent]

  @default_child_prompt """
  Spawn exactly one child agent for this task.
  Use the explorer agent.
  Do not spawn more agents.
  The child must not spawn more agents.
  Inspect lib/codex/subagents.ex and summarize what host-side controls it exposes.
  Wait for the child before answering.
  Return a concise summary.
  If multi-agent is unavailable, continue solo and say so explicitly.
  """

  def main(argv) do
    case Support.ensure_remote_working_directory() do
      :ok ->
        :ok

      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")
        System.halt(0)
    end

    prompt = parse_prompt(argv)
    cwd = Support.example_working_directory()
    model = ExamplesSupport.example_model(System.get_env("CODEX_MODEL"))

    reasoning_effort =
      ExamplesSupport.example_reasoning(Codex.Models.default_reasoning_effort(model))

    codex_opts =
      Support.codex_options!(%{
        model: model
      })

    :ok = Support.ensure_app_server_supported(codex_opts)

    IO.puts("""
    Starting live subagent host-controls example.
      model: #{model}
      reasoning_effort: #{reasoning_effort || "none"}
      working_directory: #{cwd}
      execution_surface: #{if(Support.ssh_enabled?(), do: ":ssh_exec", else: ":local_subprocess")}
    """)

    IO.puts("Connecting to codex app-server with experimental API enabled...")

    with_app_server_connection!(codex_opts, fn conn ->
      IO.puts(
        "Enabling the current runtime's experimental multi-agent feature and setting max_threads=2 max_depth=1"
      )

      configure_multi_agent!(conn)

      IO.puts("Starting parent thread...")

      {:ok, parent} =
        Codex.start_thread(
          codex_opts,
          Support.thread_opts!(%{
            transport: {:app_server, conn},
            working_directory: cwd,
            model: model
          })
        )

      IO.puts("Running parent turn with a one-parent -> one-child prompt.")
      IO.puts(@stream_wait_note)

      {:ok, stream} = Thread.run_streamed(parent, prompt, %{timeout_ms: 180_000})
      parent_state = consume_parent_stream(stream)
      parent_thread_id = extract_parent_thread_id(parent_state)

      IO.puts(
        "Parent turn finished. Opening a fresh host-controls connection for thread/list/read polling..."
      )

      with_app_server_connection!(codex_opts, fn host_conn ->
        list_opts = Keyword.put(@thread_list_opts, :cwd, cwd)
        snapshot_list_opts = Keyword.put(@thread_list_snapshot_opts, :cwd, cwd)

        {recent_subagent_snapshot, child_listing_snapshot} =
          if is_binary(parent_state.child_thread_id) do
            {
              {:skipped, :streamed_receiver_thread_id},
              {:skipped, :streamed_receiver_thread_id}
            }
          else
            {
              best_effort_snapshot(
                "thread/list for recent subagents",
                fn -> Subagents.list(host_conn, snapshot_list_opts) end
              ),
              best_effort_snapshot(
                "thread/list for child discovery",
                fn -> Subagents.children(host_conn, parent_thread_id, snapshot_list_opts) end
              )
            }
          end

        child =
          resolve_child_thread!(
            host_conn,
            parent_thread_id,
            parent_state,
            list_opts,
            child_listing_snapshot
          )

        case child do
          %{"id" => child_thread_id} ->
            child_metadata_snapshot =
              best_effort_snapshot(
                "thread/read for child metadata",
                fn -> Subagents.read(host_conn, child_thread_id, timeout_ms: 5_000) end
              )

            child_details = snapshot_value(child_metadata_snapshot, child)
            child_source = Subagents.source(child_details)
            child_parent_thread_id = Subagents.parent_thread_id(child_source)
            child_thread? = Subagents.child_thread?(child_details)
            listed_child_ids = snapshot_ids(recent_subagent_snapshot)

            IO.puts("""
            Child thread discovered.
              parent_thread_id: #{parent_thread_id}
              child_thread_id: #{child_thread_id}
              discovery_method: #{inspect(child_discovery_method(parent_state, child_listing_snapshot))}
              child_thread?: #{inspect(child_thread?)}
              source_parent_thread_id: #{inspect(child_parent_thread_id)}
              source_kind: #{inspect(Codex.Protocol.SessionSource.source_kind(child_source))}
              depth: #{inspect(child_depth(child_source))}
              role: #{inspect(child_role(child_source))}
              nickname: #{inspect(child_nickname(child_source))}
              listed_subagent_thread_ids: #{inspect(listed_child_ids)}
            """)

            require_observed_tool_kinds!(
              parent_state,
              [:spawn_agent, :wait],
              "initial parent turn"
            )

            IO.puts("Awaiting the child thread's latest turn status via thread/read polling...")

            child_status_snapshot =
              best_effort_snapshot(
                "await for child thread status",
                fn ->
                  Subagents.await(
                    host_conn,
                    child_thread_id,
                    timeout: 30_000,
                    interval: 250,
                    read_timeout_ms: 5_000
                  )
                end
              )

            child_status = snapshot_value(child_status_snapshot, {:error, :timeout})

            child_read_snapshot =
              best_effort_snapshot(
                "thread/read for child thread",
                fn ->
                  Subagents.read(host_conn, child_thread_id, include_turns: true, timeout_ms: 5_000)
                end
              )

            child_read = snapshot_value(child_read_snapshot)

            resumed_parent_state =
              run_parent_turn!(
                codex_opts,
                parent_thread_id,
                cwd,
                model,
                "Running a second parent turn that must resume or no-op the child before using send_input, wait, and close_agent...",
                parent_resume_prompt(child_thread_id)
              )

            report_missing_tool_kinds(
              resumed_parent_state,
              [:resume_agent, :send_input, :wait, :close_agent],
              "second parent turn"
            )

            post_close_child_read_snapshot =
              best_effort_snapshot(
                "thread/read for child thread after close",
                fn ->
                  Subagents.read(host_conn, child_thread_id, include_turns: true, timeout_ms: 5_000)
                end
              )

            post_close_child_read = snapshot_value(post_close_child_read_snapshot)

            post_close_child_status_snapshot =
              best_effort_snapshot(
                "await for child thread status after close",
                fn ->
                  Subagents.await(
                    host_conn,
                    child_thread_id,
                    timeout: 30_000,
                    interval: 250,
                    read_timeout_ms: 5_000
                  )
                end
              )

            post_close_child_status =
              snapshot_value(post_close_child_status_snapshot, {:error, :timeout})

            IO.puts("Opening a fresh child-turn connection for a direct host-side follow-up...")

            child_state =
              with_app_server_connection!(codex_opts, fn child_conn ->
                IO.puts("Resuming the known child thread for a direct host-side follow-up...")

                {:ok, child_thread} =
                  Codex.resume_thread(
                    child_thread_id,
                    codex_opts,
                    Support.thread_opts!(%{
                      transport: {:app_server, child_conn},
                      working_directory: cwd,
                      model: model
                    })
                  )

                IO.puts(@stream_wait_note)

                {:ok, child_stream} =
                  Thread.run_streamed(
                    child_thread,
                    "Reply with exactly one sentence that starts with 'child follow-up:'",
                    %{timeout_ms: 120_000}
                  )

                child_state = consume_child_stream(child_stream)
                %{child_state | usage: RunResultStreaming.usage(child_stream)}
              end)

            resumed_child_read_snapshot =
              best_effort_snapshot(
                "thread/read for child thread after host-side follow-up",
                fn ->
                  Subagents.read(host_conn, child_thread_id, include_turns: true, timeout_ms: 5_000)
                end
              )

            resumed_child_read = snapshot_value(resumed_child_read_snapshot)

            resumed_child_status_snapshot =
              best_effort_snapshot(
                "await for child thread status after host-side follow-up",
                fn ->
                  Subagents.await(
                    host_conn,
                    child_thread_id,
                    timeout: 30_000,
                    interval: 250,
                    read_timeout_ms: 5_000
                  )
                end
              )

            resumed_child_status = snapshot_value(resumed_child_status_snapshot, {:error, :timeout})

            observed_tool_kinds =
              merge_observed_tool_kinds([parent_state, resumed_parent_state])

            IO.inspect(%{
              parent_thread_id: parent_thread_id,
              child_thread_id: child_thread_id,
              child_parent_thread_id: child_parent_thread_id,
              child_source_type: Codex.Protocol.SessionSource.source_kind(child_source),
              child_thread?: child_thread?,
              child_depth: child_depth(child_source),
              child_role: child_role(child_source),
              child_nickname: child_nickname(child_source),
              listed_subagent_thread_ids: listed_child_ids,
              subagent_thread_count: snapshot_count(recent_subagent_snapshot),
              subagent_snapshot_status: snapshot_status(recent_subagent_snapshot),
              child_listing_snapshot_status: snapshot_status(child_listing_snapshot),
              used_multi_agent?: true,
              spawn_observed?: parent_state.spawn_observed?,
              child_turn_count: count_turns(child_read),
              child_status: child_status,
              child_turn_count_after_close: count_turns(post_close_child_read),
              child_status_after_close: post_close_child_status,
              child_turn_count_after_resume: count_turns(resumed_child_read),
              child_status_after_resume: resumed_child_status,
              child_follow_up: child_state.final_response,
              parent_summary: parent_state.parent_summary,
              parent_usage: RunResultStreaming.usage(stream),
              child_follow_up_usage: child_state.usage,
              parent_resume_summary: resumed_parent_state.parent_summary,
              parent_resume_usage: resumed_parent_state.usage,
              observed_prompt_tool_kinds: Enum.sort(MapSet.to_list(observed_tool_kinds)),
              prompt_tool_surface_complete?:
                MapSet.subset?(MapSet.new(@prompt_tool_kinds), observed_tool_kinds)
            })

          [] ->
            IO.puts(
              "No child thread was discovered. The parent likely took the documented solo fallback path."
            )

            IO.inspect(%{
              parent_thread_id: parent_thread_id,
              child_thread_id: nil,
              child_source_type: nil,
              child_parent_thread_id: nil,
              child_thread?: false,
              child_depth: nil,
              child_role: nil,
              child_nickname: nil,
              listed_subagent_thread_ids: snapshot_ids(recent_subagent_snapshot),
              subagent_thread_count: snapshot_count(recent_subagent_snapshot),
              subagent_snapshot_status: snapshot_status(recent_subagent_snapshot),
              child_listing_snapshot_status: snapshot_status(child_listing_snapshot),
              used_multi_agent?: false,
              spawn_observed?: parent_state.spawn_observed?,
              parent_summary: parent_state.parent_summary,
              parent_usage: RunResultStreaming.usage(stream)
            })
        end
      end)
    end)
  end

  defp configure_multi_agent!(conn) do
    {:ok, _} = AppServer.config_write(conn, "features.multi_agent", true)
    {:ok, _} = AppServer.config_write(conn, "agents.max_threads", 2)
    {:ok, _} = AppServer.config_write(conn, "agents.max_depth", 1)
  end

  defp parse_prompt([]), do: @default_child_prompt
  defp parse_prompt(values), do: Enum.join(values, " ")

  defp parent_resume_prompt(child_thread_id) do
    """
    Call resume_agent on the existing child agent with id #{child_thread_id} before any other collaboration tool.
    Do not spawn a new agent.
    Do not target any other agent.
    After resuming it, send exactly one follow-up message asking it to reply with exactly one sentence that starts with "resumed child:" and names two host helpers exposed by Codex.Subagents.
    Wait for that child to finish.
    After the child finishes, close that same child agent again.
    Then reply with exactly one sentence that confirms you used resume_agent, send_input, wait, and close_agent.
    If resume, send_input, wait, or close_agent fails, say so explicitly and do not spawn a replacement.
    """
  end

  defp run_parent_turn!(codex_opts, parent_thread_id, cwd, model, banner, prompt) do
    with_app_server_connection!(codex_opts, fn parent_conn ->
      IO.puts(banner)

      {:ok, parent_thread} =
        Codex.resume_thread(
          parent_thread_id,
          codex_opts,
          Support.thread_opts!(%{
            transport: {:app_server, parent_conn},
            working_directory: cwd,
            model: model
          })
        )

      IO.puts(@stream_wait_note)

      {:ok, parent_stream} = Thread.run_streamed(parent_thread, prompt, %{timeout_ms: 180_000})
      parent_state = consume_parent_stream(parent_stream)
      %{parent_state | usage: RunResultStreaming.usage(parent_stream)}
    end)
  end

  defp consume_parent_stream(stream) do
    stream
    |> RunResultStreaming.raw_events()
    |> Enum.reduce(
      %{
        parent_thread_id: nil,
        parent_summary: nil,
        child_thread_id: nil,
        spawn_observed?: false,
        observed_tool_kinds: MapSet.new(),
        parent_thread_started?: false,
        parent_turn_started?: false,
        text_open?: false,
        usage: %{}
      },
      &handle_parent_event/2
    )
    |> close_text_block()
  end

  defp consume_child_stream(stream) do
    stream
    |> RunResultStreaming.raw_events()
    |> Enum.reduce(
      %{final_response: nil, child_turn_started?: false, text_open?: false, usage: %{}},
      &handle_child_event/2
    )
    |> close_text_block()
  end

  defp extract_parent_thread_id(%{parent_thread_id: thread_id}) when is_binary(thread_id),
    do: thread_id

  defp extract_parent_thread_id(_state) do
    raise "unable to determine parent thread id from streamed events"
  end

  defp handle_parent_event(%Events.ThreadStarted{thread_id: thread_id}, state) do
    if state.parent_thread_started? do
      %{state | parent_thread_id: thread_id}
    else
      IO.puts("Parent thread started: #{thread_id}")
      %{state | parent_thread_id: thread_id, parent_thread_started?: true}
    end
  end

  defp handle_parent_event(%Events.TurnStarted{}, state) do
    if state.parent_turn_started? do
      state
    else
      IO.puts("Parent turn started.")
      %{state | parent_turn_started?: true}
    end
  end

  defp handle_parent_event(%Events.CollabAgentSpawnBegin{prompt: prompt}, state) do
    state
    |> close_text_block()
    |> then(fn next_state ->
      IO.puts("Subagent spawn started. Prompt preview: #{preview(prompt)}")
      mark_tool_kind(next_state, :spawn_agent)
    end)
  end

  defp handle_parent_event(
         %Events.CollabAgentSpawnEnd{
           new_thread_id: thread_id,
           new_agent_role: role,
           new_agent_nickname: nickname,
           reasoning_effort: reasoning_effort,
           model: model
         },
         state
       ) do
    state
    |> close_text_block()
    |> then(fn next_state ->
      IO.puts("""
      Subagent spawn completed.
        child_thread_id: #{inspect(thread_id)}
        role: #{inspect(role)}
        nickname: #{inspect(nickname)}
        model: #{inspect(model)}
        reasoning_effort: #{inspect(reasoning_effort)}
      """)

      %{
        mark_tool_kind(next_state, :spawn_agent)
        | child_thread_id: thread_id || next_state.child_thread_id
      }
    end)
  end

  defp handle_parent_event(%Events.CollabWaitingBegin{receiver_thread_ids: ids}, state) do
    state
    |> close_text_block()
    |> then(fn next_state ->
      IO.puts("Parent is waiting on child threads: #{Enum.join(ids, ", ")}")
      next_state
      |> mark_tool_kind(:wait)
      |> capture_child_thread_id(ids)
    end)
  end

  defp handle_parent_event(%Events.CollabWaitingEnd{agent_statuses: statuses}, state) do
    state
    |> close_text_block()
    |> then(fn next_state ->
      rendered =
        statuses
        |> Enum.map_join(", ", fn status ->
          "#{status.thread_id}=#{inspect(status.status.status)}"
        end)

      IO.puts("Parent finished waiting on child threads: #{rendered}")
      mark_tool_kind(next_state, :wait)
    end)
  end

  defp handle_parent_event(%Events.CollabResumeBegin{receiver_thread_id: thread_id}, state) do
    state
    |> close_text_block()
    |> then(fn next_state ->
      IO.puts("Parent resumed child thread #{inspect(thread_id)}.")
      next_state
      |> mark_tool_kind(:resume_agent)
      |> capture_child_thread_id(List.wrap(thread_id))
    end)
  end

  defp handle_parent_event(%Events.ItemStarted{item: %Items.CollabAgentToolCall{} = item}, state) do
    state
    |> close_text_block()
    |> then(fn next_state ->
      IO.puts(
        "Collab tool started: #{item.tool} kind=#{inspect(item.tool_kind)} receivers=#{inspect(item.receiver_thread_ids)}"
      )

      next_state
      |> mark_tool_kind(item.tool_kind)
      |> capture_child_thread_id(item.receiver_thread_ids)
    end)
  end

  defp handle_parent_event(
         %Events.ItemCompleted{item: %Items.CollabAgentToolCall{} = item},
         state
       ) do
    state
    |> close_text_block()
    |> then(fn next_state ->
      IO.puts(
        "Collab tool completed: #{item.tool} kind=#{inspect(item.tool_kind)} status=#{inspect(item.status)} receivers=#{inspect(item.receiver_thread_ids)}"
      )

      next_state
      |> mark_tool_kind(item.tool_kind)
      |> capture_child_thread_id(item.receiver_thread_ids)
    end)
  end

  defp handle_parent_event(%Events.ItemAgentMessageDelta{item: %{"text" => delta}}, state)
       when is_binary(delta) do
    open_text_block(state, "parent")
    IO.write(delta)
    %{state | text_open?: true}
  end

  defp handle_parent_event(%Events.ItemCompleted{item: %Items.AgentMessage{text: text}}, state)
       when is_binary(text) and text != "" do
    state
    |> close_text_block()
    |> then(fn next_state ->
      %{next_state | parent_summary: text}
    end)
  end

  defp handle_parent_event(%Events.TurnCompleted{status: status, final_response: response}, state) do
    state
    |> close_text_block()
    |> then(fn next_state ->
      IO.puts("Parent turn completed with status=#{inspect(status)}.")
      %{next_state | parent_summary: next_state.parent_summary || extract_text(response)}
    end)
  end

  defp handle_parent_event(_event, state), do: state

  defp handle_child_event(%Events.TurnStarted{}, state) do
    if state.child_turn_started? do
      state
    else
      IO.puts("Child follow-up turn started.")
      %{state | child_turn_started?: true}
    end
  end

  defp handle_child_event(%Events.ItemAgentMessageDelta{item: %{"text" => delta}}, state)
       when is_binary(delta) do
    open_text_block(state, "child")
    IO.write(delta)
    %{state | text_open?: true}
  end

  defp handle_child_event(%Events.ItemCompleted{item: %Items.AgentMessage{text: text}}, state)
       when is_binary(text) and text != "" do
    state
    |> close_text_block()
    |> then(fn next_state ->
      %{next_state | final_response: text}
    end)
  end

  defp handle_child_event(%Events.TurnCompleted{status: status, final_response: response}, state) do
    state
    |> close_text_block()
    |> then(fn next_state ->
      IO.puts("Child follow-up turn completed with status=#{inspect(status)}.")
      %{next_state | final_response: next_state.final_response || extract_text(response)}
    end)
  end

  defp handle_child_event(_event, state), do: state

  defp open_text_block(%{text_open?: true}, _label), do: :ok

  defp open_text_block(%{text_open?: false}, label) do
    IO.puts("")
    IO.puts("[#{label} text]")
  end

  defp close_text_block(%{text_open?: true} = state) do
    IO.puts("")
    %{state | text_open?: false}
  end

  defp close_text_block(state), do: state

  defp preview(nil), do: "<none>"

  defp preview(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 120)
  end

  defp preview(other), do: inspect(other)

  defp extract_text(%Items.AgentMessage{text: text}) when is_binary(text), do: text
  defp extract_text(%{"text" => text}) when is_binary(text), do: text
  defp extract_text(%{text: text}) when is_binary(text), do: text
  defp extract_text(text) when is_binary(text), do: text
  defp extract_text(_other), do: nil

  defp child_depth(%Codex.Protocol.SessionSource{sub_agent: %{depth: depth}}), do: depth
  defp child_depth(_), do: nil

  defp child_role(%Codex.Protocol.SessionSource{sub_agent: %{agent_role: role}}), do: role
  defp child_role(_), do: nil

  defp child_nickname(%Codex.Protocol.SessionSource{sub_agent: %{agent_nickname: nickname}}),
    do: nickname

  defp child_nickname(_), do: nil

  defp count_turns(%{"turns" => turns}) when is_list(turns), do: length(turns)
  defp count_turns(%{turns: turns}) when is_list(turns), do: length(turns)
  defp count_turns(_), do: 0

  defp resolve_child_thread!(
         _host_conn,
         _parent_thread_id,
         %{child_thread_id: child_thread_id},
         _list_opts,
         _child_listing_snapshot
       )
       when is_binary(child_thread_id) do
    IO.puts(
      "Using child thread id observed directly from streamed collaboration events: #{child_thread_id}"
    )

    %{"id" => child_thread_id}
  end

  defp resolve_child_thread!(
         host_conn,
         parent_thread_id,
         parent_state,
         list_opts,
         _child_listing_snapshot
       ) do
    children =
      if parent_state.spawn_observed? do
        retry_until!(
          "child thread discovery",
          fn ->
            with {:ok, child_threads} <-
                   Subagents.children(host_conn, parent_thread_id, list_opts) do
              case child_threads do
                [] -> {:retry, :no_children_yet}
                _ -> {:ok, child_threads}
              end
            end
          end
        )
      else
        []
      end

    List.first(children) || []
  end

  defp child_discovery_method(%{child_thread_id: child_thread_id}, _snapshot)
       when is_binary(child_thread_id),
       do: :streamed_receiver_thread_id

  defp child_discovery_method(_state, {:ok, _snapshot}), do: :thread_list
  defp child_discovery_method(_state, _snapshot), do: :none

  defp capture_child_thread_id(%{child_thread_id: existing} = state, _receiver_ids)
       when is_binary(existing),
       do: state

  defp capture_child_thread_id(state, receiver_ids) do
    case Enum.find(List.wrap(receiver_ids), &is_binary/1) do
      nil -> state
      thread_id -> %{state | child_thread_id: thread_id}
    end
  end

  defp best_effort_snapshot(label, fun) when is_binary(label) and is_function(fun, 0) do
    case fun.() do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        IO.puts("#{label} skipped: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp snapshot_ids({:ok, entries}) when is_list(entries), do: Enum.map(entries, & &1["id"])
  defp snapshot_ids(_snapshot), do: []

  defp snapshot_count({:ok, entries}) when is_list(entries), do: length(entries)
  defp snapshot_count(_snapshot), do: 0

  defp snapshot_status({:ok, _entries}), do: :ok
  defp snapshot_status({:skipped, reason}), do: {:skipped, reason}
  defp snapshot_status({:error, reason}), do: {:error, reason}
  defp snapshot_status(_snapshot), do: :unknown

  defp snapshot_value({:ok, value}, _default), do: value
  defp snapshot_value(_snapshot, default), do: default

  defp snapshot_value(snapshot), do: snapshot_value(snapshot, %{})

  defp require_observed_tool_kinds!(state, expected, label) when is_list(expected) do
    expected_set = MapSet.new(expected)
    observed = Map.get(state, :observed_tool_kinds, MapSet.new())
    missing = MapSet.difference(expected_set, observed)

    if MapSet.size(missing) > 0 do
      Mix.raise(
        "#{label} did not exercise the expected tool kinds. Missing=#{inspect(Enum.sort(MapSet.to_list(missing)))} observed=#{inspect(Enum.sort(MapSet.to_list(observed)))}"
      )
    end
  end

  defp report_missing_tool_kinds(state, expected, label) when is_list(expected) do
    expected_set = MapSet.new(expected)
    observed = Map.get(state, :observed_tool_kinds, MapSet.new())
    missing = MapSet.difference(expected_set, observed)

    if MapSet.size(missing) > 0 do
      IO.puts("""
      #{label} did not exercise the full expected tool surface.
        missing: #{inspect(Enum.sort(MapSet.to_list(missing)))}
        observed: #{inspect(Enum.sort(MapSet.to_list(observed)))}
      Continuing with direct host-side follow-up using the discovered child thread.
      """)
    end
  end

  defp merge_observed_tool_kinds(states) when is_list(states) do
    Enum.reduce(states, MapSet.new(), fn state, acc ->
      MapSet.union(acc, Map.get(state, :observed_tool_kinds, MapSet.new()))
    end)
  end

  defp mark_tool_kind(state, :unknown), do: state

  defp mark_tool_kind(%{observed_tool_kinds: observed} = state, tool_kind) do
    %{
      state
      | observed_tool_kinds: MapSet.put(observed, tool_kind),
        spawn_observed?: state.spawn_observed? or tool_kind == :spawn_agent
    }
  end

  defp with_app_server_connection!(codex_opts, fun) when is_function(fun, 1) do
    {:ok, conn} =
      AppServer.connect(codex_opts,
        experimental_api: true,
        init_timeout_ms: 30_000
      )

    try do
      fun.(conn)
    after
      :ok = AppServer.disconnect(conn)
    end
  end

  defp retry_until!(label, fun, attempts \\ @discovery_attempts, delay_ms \\ @discovery_delay_ms)
       when is_binary(label) and is_function(fun, 0) and attempts >= 1 and delay_ms >= 0 do
    case fun.() do
      {:ok, value} ->
        value

      {:retry, reason} when attempts > 1 ->
        IO.puts("#{label} not ready yet: #{inspect(reason)}. Retrying...")
        Process.sleep(delay_ms)
        retry_until!(label, fun, attempts - 1, delay_ms)

      {:retry, reason} ->
        Mix.raise("#{label} failed: #{inspect(reason)}")

      {:error, reason} when attempts > 1 ->
        IO.puts("#{label} errored: #{inspect(reason)}. Retrying...")
        Process.sleep(delay_ms)
        retry_until!(label, fun, attempts - 1, delay_ms)

      {:error, reason} ->
        Mix.raise("#{label} failed: #{inspect(reason)}")
    end
  end
end

CodexExamples.LiveSubagentHostControls.main(System.argv())

Mix.Task.run("app.start")

alias Codex.{AppServer, Events, Items, Options, RunResultStreaming, Subagents, Thread}

defmodule CodexExamples.LiveSubagentHostControls do
  @moduledoc false

  @stream_wait_note """
  Waiting for streamed events. If the model stays quiet briefly, Codex is still working.
  """

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
    prompt = parse_prompt(argv)
    cwd = File.cwd!()
    codex_path = fetch_codex_path!()
    ensure_app_server_supported!(codex_path)

    IO.puts("""
    Starting live subagent host-controls example.
      model: gpt-5.4
      reasoning_effort: low
      working_directory: #{cwd}
      codex_path: #{codex_path}
    """)

    {:ok, codex_opts} =
      Options.new(%{
        codex_path_override: codex_path,
        model: "gpt-5.4",
        reasoning_effort: :low
      })

    IO.puts("Connecting to codex app-server with experimental API enabled...")

    {:ok, conn} =
      AppServer.connect(codex_opts,
        experimental_api: true,
        init_timeout_ms: 30_000
      )

    try do
      IO.puts(
        "Configuring multi-agent limits: features.multi_agent=true max_threads=2 max_depth=1"
      )

      configure_multi_agent!(conn)

      IO.puts("Starting parent thread...")

      {:ok, parent} =
        Codex.start_thread(codex_opts, %{
          transport: {:app_server, conn},
          working_directory: cwd,
          model: "gpt-5.4"
        })

      IO.puts("Running parent turn with a one-parent -> one-child prompt.")
      IO.puts(@stream_wait_note)

      {:ok, stream} = Thread.run_streamed(parent, prompt, %{timeout_ms: 180_000})
      parent_state = consume_parent_stream(stream)
      parent_thread_id = extract_parent_thread_id(parent_state)

      IO.puts("Parent turn finished. Discovering any spawned child threads...")

      {:ok, children} = Subagents.children(conn, parent_thread_id)

      case children do
        [%{"id" => child_thread_id} = child | _] ->
          child_source = Subagents.source(child)

          IO.puts("""
          Child thread discovered.
            parent_thread_id: #{parent_thread_id}
            child_thread_id: #{child_thread_id}
            source_kind: #{inspect(Codex.Protocol.SessionSource.source_kind(child_source))}
            depth: #{inspect(child_depth(child_source))}
            role: #{inspect(child_role(child_source))}
            nickname: #{inspect(child_nickname(child_source))}
          """)

          IO.puts("Reading child thread state via thread/read(include_turns: true)...")
          {:ok, child_read} = Subagents.read(conn, child_thread_id, include_turns: true)

          IO.puts("Resuming the known child thread for a direct host-side follow-up...")

          {:ok, child_thread} =
            Codex.resume_thread(child_thread_id, codex_opts, %{
              transport: {:app_server, conn},
              working_directory: cwd
            })

          IO.puts(@stream_wait_note)

          {:ok, child_stream} =
            Thread.run_streamed(
              child_thread,
              "Reply with exactly one sentence that starts with 'child follow-up:'",
              %{timeout_ms: 120_000}
            )

          child_state = consume_child_stream(child_stream)

          IO.puts("Awaiting the child thread's latest turn status via thread/read polling...")

          {:ok, child_status} =
            Subagents.await(conn, child_thread_id, timeout: 30_000, interval: 250)

          IO.inspect(%{
            parent_thread_id: parent_thread_id,
            child_thread_id: child_thread_id,
            child_source_type: Codex.Protocol.SessionSource.source_kind(child_source),
            child_depth: child_depth(child_source),
            child_role: child_role(child_source),
            child_nickname: child_nickname(child_source),
            used_multi_agent?: true,
            spawn_observed?: parent_state.spawn_observed?,
            child_turn_count: count_turns(child_read),
            child_status: child_status,
            child_follow_up: child_state.final_response,
            parent_summary: parent_state.parent_summary,
            parent_usage: RunResultStreaming.usage(stream),
            child_follow_up_usage: RunResultStreaming.usage(child_stream)
          })

        [] ->
          IO.puts(
            "No child thread was discovered. The parent likely took the documented solo fallback path."
          )

          IO.inspect(%{
            parent_thread_id: parent_thread_id,
            child_thread_id: nil,
            child_source_type: nil,
            child_depth: nil,
            child_role: nil,
            child_nickname: nil,
            used_multi_agent?: false,
            spawn_observed?: parent_state.spawn_observed?,
            parent_summary: parent_state.parent_summary,
            parent_usage: RunResultStreaming.usage(stream)
          })
      end
    after
      :ok = AppServer.disconnect(conn)
    end
  end

  defp configure_multi_agent!(conn) do
    {:ok, _} = AppServer.config_write(conn, "features.multi_agent", true)
    {:ok, _} = AppServer.config_write(conn, "agents.max_threads", 2)
    {:ok, _} = AppServer.config_write(conn, "agents.max_depth", 1)
  end

  defp parse_prompt([]), do: @default_child_prompt
  defp parse_prompt(values), do: Enum.join(values, " ")

  defp consume_parent_stream(stream) do
    stream
    |> RunResultStreaming.raw_events()
    |> Enum.reduce(
      %{parent_thread_id: nil, parent_summary: nil, spawn_observed?: false, text_open?: false},
      &handle_parent_event/2
    )
    |> close_text_block()
  end

  defp consume_child_stream(stream) do
    stream
    |> RunResultStreaming.raw_events()
    |> Enum.reduce(%{final_response: nil, text_open?: false}, &handle_child_event/2)
    |> close_text_block()
  end

  defp extract_parent_thread_id(%{parent_thread_id: thread_id}) when is_binary(thread_id),
    do: thread_id

  defp extract_parent_thread_id(_state) do
    raise "unable to determine parent thread id from streamed events"
  end

  defp handle_parent_event(%Events.ThreadStarted{thread_id: thread_id}, state) do
    IO.puts("Parent thread started: #{thread_id}")
    %{state | parent_thread_id: thread_id}
  end

  defp handle_parent_event(%Events.TurnStarted{}, state) do
    IO.puts("Parent turn started.")
    state
  end

  defp handle_parent_event(%Events.CollabAgentSpawnBegin{prompt: prompt}, state) do
    state
    |> close_text_block()
    |> then(fn next_state ->
      IO.puts("Subagent spawn started. Prompt preview: #{preview(prompt)}")
      %{next_state | spawn_observed?: true}
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

      %{next_state | spawn_observed?: true}
    end)
  end

  defp handle_parent_event(%Events.CollabWaitingBegin{receiver_thread_ids: ids}, state) do
    state
    |> close_text_block()
    |> then(fn next_state ->
      IO.puts("Parent is waiting on child threads: #{Enum.join(ids, ", ")}")
      next_state
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
      next_state
    end)
  end

  defp handle_parent_event(%Events.CollabResumeBegin{receiver_thread_id: thread_id}, state) do
    state
    |> close_text_block()
    |> then(fn next_state ->
      IO.puts("Parent resumed child thread #{inspect(thread_id)}.")
      next_state
    end)
  end

  defp handle_parent_event(%Events.ItemStarted{item: %Items.CollabAgentToolCall{} = item}, state) do
    state
    |> close_text_block()
    |> then(fn next_state ->
      IO.puts(
        "Collab tool started: #{item.tool} kind=#{inspect(item.tool_kind)} receivers=#{inspect(item.receiver_thread_ids)}"
      )

      %{
        next_state
        | spawn_observed?: next_state.spawn_observed? or item.tool_kind == :spawn_agent
      }
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

      %{
        next_state
        | spawn_observed?: next_state.spawn_observed? or item.tool_kind == :spawn_agent
      }
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
    IO.puts("Child follow-up turn started.")
    state
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

  defp fetch_codex_path! do
    System.get_env("CODEX_PATH") ||
      System.find_executable("codex") ||
      Mix.raise("""
      Unable to locate the `codex` CLI.
      Install the Codex CLI and ensure it is on your PATH or set CODEX_PATH.
      """)
  end

  defp ensure_app_server_supported!(codex_path) do
    {_output, status} = System.cmd(codex_path, ["app-server", "--help"], stderr_to_stdout: true)

    if status != 0 do
      Mix.raise("""
      Your `codex` CLI does not appear to support `codex app-server`.
      Upgrade via `npm install -g @openai/codex` and retry.
      """)
    end
  end
end

CodexExamples.LiveSubagentHostControls.main(System.argv())

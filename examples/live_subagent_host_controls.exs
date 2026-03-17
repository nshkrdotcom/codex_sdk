Mix.Task.run("app.start")

alias Codex.{AppServer, Events, Items, Options, RunResultStreaming, Subagents, Thread}

defmodule CodexExamples.LiveSubagentHostControls do
  @moduledoc false

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

    {:ok, codex_opts} =
      Options.new(%{
        codex_path_override: codex_path,
        model: "gpt-5.4",
        reasoning_effort: :medium
      })

    {:ok, conn} =
      AppServer.connect(codex_opts,
        experimental_api: true,
        init_timeout_ms: 30_000
      )

    try do
      configure_multi_agent!(conn)

      {:ok, parent} =
        Codex.start_thread(codex_opts, %{
          transport: {:app_server, conn},
          working_directory: cwd,
          model: "gpt-5.4"
        })

      {:ok, stream} = Thread.run_streamed(parent, prompt, %{timeout_ms: 180_000})
      parent_events = RunResultStreaming.raw_events(stream) |> Enum.to_list()
      parent_thread_id = extract_parent_thread_id(parent_events)
      spawn_calls = collab_spawn_calls(parent_events)

      {:ok, children} = Subagents.children(conn, parent_thread_id)

      case children do
        [%{"id" => child_thread_id} = child | _] ->
          child_source = Subagents.source(child)
          {:ok, child_read} = Subagents.read(conn, child_thread_id, include_turns: true)

          {:ok, child_thread} =
            Codex.resume_thread(child_thread_id, codex_opts, %{
              transport: {:app_server, conn},
              working_directory: cwd
            })

          {:ok, child_result} =
            Thread.run(
              child_thread,
              "Reply with exactly one sentence that starts with 'child follow-up:'",
              %{timeout_ms: 120_000}
            )

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
            spawn_observed?: spawn_calls != [],
            child_turn_count: count_turns(child_read),
            child_status: child_status,
            child_follow_up: extract_text(child_result.final_response),
            parent_summary: extract_last_agent_text(parent_events)
          })

        [] ->
          IO.inspect(%{
            parent_thread_id: parent_thread_id,
            child_thread_id: nil,
            child_source_type: nil,
            child_depth: nil,
            child_role: nil,
            child_nickname: nil,
            used_multi_agent?: false,
            spawn_observed?: spawn_calls != [],
            parent_summary: extract_last_agent_text(parent_events)
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

  defp collab_spawn_calls(events) do
    Enum.filter(events, fn
      %Events.ItemStarted{item: %Items.CollabAgentToolCall{tool_kind: :spawn_agent}} -> true
      %Events.ItemCompleted{item: %Items.CollabAgentToolCall{tool_kind: :spawn_agent}} -> true
      _ -> false
    end)
  end

  defp extract_parent_thread_id(events) do
    Enum.find_value(events, fn
      %Events.ThreadStarted{thread_id: thread_id} -> thread_id
      _ -> nil
    end) || raise "unable to determine parent thread id from streamed events"
  end

  defp extract_last_agent_text(events) do
    events
    |> Enum.reverse()
    |> Enum.find_value(fn
      %Events.ItemCompleted{item: %Items.AgentMessage{text: text}}
      when is_binary(text) and text != "" ->
        text

      _ ->
        nil
    end)
  end

  defp extract_text(%Items.AgentMessage{text: text}) when is_binary(text), do: text
  defp extract_text(other) when is_binary(other), do: other
  defp extract_text(other), do: inspect(other)

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

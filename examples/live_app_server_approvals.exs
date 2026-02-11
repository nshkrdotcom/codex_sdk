Mix.Task.run("app.start")

alias Codex.Events
alias Codex.Items
alias Codex.RunResultStreaming

defmodule CodexExamples.LiveAppServerApprovals do
  @moduledoc false

  @default_prompt """
  Run `pwd` and `ls -la` in the current working directory, then create a small file named
  `approval_demo.txt` containing the current directory path and report exactly what completed.
  """

  @command_approval_method "item/commandExecution/requestApproval"
  @file_approval_method "item/fileChange/requestApproval"

  def main(argv) do
    prompt =
      case argv do
        [] -> @default_prompt
        values -> Enum.join(values, " ")
      end

    codex_path = fetch_codex_path!()
    ensure_app_server_supported!(codex_path)

    {:ok, codex_opts} =
      Codex.Options.new(%{
        codex_path_override: codex_path
      })

    {:ok, conn} = Codex.AppServer.connect(codex_opts, init_timeout_ms: 30_000)

    try do
      parent = self()

      {:ok, approval_pid} =
        Task.start_link(fn ->
          # Subscribe without method filters so request logging stays useful if method names evolve.
          :ok = Codex.AppServer.subscribe(conn)
          send(parent, {:approvals_ready, self()})
          approval_loop(conn, parent)
        end)

      :ok = await_approvals_ready!(approval_pid)

      {:ok, thread} =
        Codex.start_thread(codex_opts, %{
          transport: {:app_server, conn},
          working_directory: File.cwd!(),
          ask_for_approval: :untrusted
        })

      IO.puts("""
      Streaming over app-server with manual approvals.
        prompt: #{prompt}

      This run prints:
        - proposed commandExecution/fileChange items
        - incoming app-server request methods
        - approval responses sent
        - completion status for command/file items
      """)

      case Codex.Thread.run_streamed(thread, prompt, %{timeout_ms: 120_000}) do
        {:ok, stream} ->
          stream
          |> RunResultStreaming.raw_events()
          |> Enum.each(&print_event(&1, parent))

          IO.puts("\nusage: #{inspect(RunResultStreaming.usage(stream))}")

        {:error, reason} ->
          Mix.raise("Streaming run failed: #{inspect(reason)}")
      end

      audit = drain_audit_messages(new_audit_state())
      print_audit_summary(audit)

      send(approval_pid, :stop)
    after
      :ok = Codex.AppServer.disconnect(conn)
    end
  end

  defp approval_loop(conn, parent) do
    receive do
      :stop ->
        :ok

      {:codex_request, id, method, params} ->
        IO.puts("\n[codex_request] method=#{method}")
        send(parent, {:audit, {:request_received, method}})

        case method do
          @command_approval_method ->
            decision = command_decision(params)
            :ok = Codex.AppServer.respond(conn, id, %{decision: decision})
            IO.puts("[approval] responded to commandExecution request")
            send(parent, {:audit, {:response_sent, method}})

          @file_approval_method ->
            :ok = Codex.AppServer.respond(conn, id, %{decision: "accept"})
            IO.puts("[approval] responded to fileChange request")
            send(parent, {:audit, {:response_sent, method}})

          _other ->
            IO.puts("[codex_request] no handler configured for #{method}")
        end

        approval_loop(conn, parent)

      _other ->
        approval_loop(conn, parent)
    end
  end

  defp command_decision(%{"proposedExecpolicyAmendment" => argv})
       when is_list(argv) and argv != [] do
    %{"acceptWithExecpolicyAmendment" => %{"execpolicyAmendment" => argv}}
  end

  defp command_decision(_params), do: "acceptForSession"

  defp await_approvals_ready!(task_pid) when is_pid(task_pid) do
    receive do
      {:approvals_ready, ^task_pid} -> :ok
    after
      5_000 -> Mix.raise("Timed out waiting for approval subscription")
    end
  end

  defp print_event(%Events.ItemAgentMessageDelta{item: %{"text" => delta}}, _parent)
       when is_binary(delta) do
    IO.write(delta)
  end

  defp print_event(%Events.ItemStarted{item: %Items.CommandExecution{} = item}, parent) do
    IO.puts("""

    [item.started commandExecution]
      command: #{item.command}
      cwd: #{inspect(item.cwd)}
      status: #{inspect(item.status)}
    """)

    send(parent, {:audit, :command_proposed})
  end

  defp print_event(%Events.ItemStarted{item: %Items.FileChange{} = item}, parent) do
    IO.puts("""

    [item.started fileChange]
      changes: #{length(item.changes)}
      status: #{inspect(item.status)}
    """)

    send(parent, {:audit, :file_proposed})
  end

  defp print_event(%Events.ItemCompleted{item: %Items.CommandExecution{} = item}, parent) do
    IO.puts("""

    [item.completed commandExecution]
      status: #{inspect(item.status)}
      exit_code: #{inspect(item.exit_code)}
      command: #{item.command}
    """)

    send(parent, {:audit, {:command_completed, item.status}})
  end

  defp print_event(%Events.ItemCompleted{item: %Items.FileChange{} = item}, parent) do
    IO.puts("""

    [item.completed fileChange]
      status: #{inspect(item.status)}
      changes: #{length(item.changes)}
    """)

    send(parent, {:audit, {:file_completed, item.status}})
  end

  defp print_event(%Events.ItemCompleted{item: %Items.AgentMessage{text: text}}, _parent) do
    if is_binary(text) and String.trim(text) != "" do
      IO.puts("\n\n[agent_message.completed]\n#{text}\n")
    end
  end

  defp print_event(%Events.TurnCompleted{status: status}, _parent) do
    IO.puts("\n[turn.completed] status=#{inspect(status)}")
  end

  defp print_event(_other, _parent), do: :ok

  defp new_audit_state do
    %{
      command_proposed?: false,
      file_proposed?: false,
      approval_request_methods: MapSet.new(),
      approval_response_methods: MapSet.new(),
      command_completed_statuses: [],
      file_completed_statuses: []
    }
  end

  defp drain_audit_messages(state) do
    receive do
      {:audit, :command_proposed} ->
        drain_audit_messages(%{state | command_proposed?: true})

      {:audit, :file_proposed} ->
        drain_audit_messages(%{state | file_proposed?: true})

      {:audit, {:request_received, method}} ->
        methods = MapSet.put(state.approval_request_methods, method)
        drain_audit_messages(%{state | approval_request_methods: methods})

      {:audit, {:response_sent, method}} ->
        methods = MapSet.put(state.approval_response_methods, method)
        drain_audit_messages(%{state | approval_response_methods: methods})

      {:audit, {:command_completed, status}} ->
        drain_audit_messages(%{
          state
          | command_completed_statuses: [status | state.command_completed_statuses]
        })

      {:audit, {:file_completed, status}} ->
        drain_audit_messages(%{
          state
          | file_completed_statuses: [status | state.file_completed_statuses]
        })
    after
      250 ->
        state
    end
  end

  defp print_audit_summary(audit) do
    IO.puts("\nAudit summary:")
    IO.puts("  command/file item proposed? #{audit.command_proposed? or audit.file_proposed?}")
    IO.puts("  commandExecution proposed? #{audit.command_proposed?}")
    IO.puts("  fileChange proposed? #{audit.file_proposed?}")

    IO.puts(
      "  approval request methods: #{inspect(MapSet.to_list(audit.approval_request_methods))}"
    )

    IO.puts(
      "  approval response methods: #{inspect(MapSet.to_list(audit.approval_response_methods))}"
    )

    IO.puts(
      "  commandExecution completed statuses: #{inspect(Enum.reverse(audit.command_completed_statuses))}"
    )

    IO.puts(
      "  fileChange completed statuses: #{inspect(Enum.reverse(audit.file_completed_statuses))}"
    )

    if MapSet.size(audit.approval_request_methods) == 0 do
      IO.puts(
        "  note: no approval requests observed for this prompt/policy combination; check item events above to confirm whether tools were invoked."
      )
    end
  end

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

CodexExamples.LiveAppServerApprovals.main(System.argv())

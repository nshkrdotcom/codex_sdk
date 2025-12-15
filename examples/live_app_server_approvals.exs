Mix.Task.run("app.start")

alias Codex.RunResultStreaming
alias Codex.Events
alias Codex.Items

defmodule CodexExamples.LiveAppServerApprovals do
  @moduledoc false

  @default_prompt "Run `pwd` and `ls -la` in the current working directory, then reply with exactly ok."

  @approval_methods [
    "item/commandExecution/requestApproval",
    "item/fileChange/requestApproval"
  ]

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
          :ok = Codex.AppServer.subscribe(conn, methods: @approval_methods)
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

      If Codex requests approval for a command or file change, this example auto-responds.
      """)

      case Codex.Thread.run_streamed(thread, prompt, %{timeout_ms: 120_000}) do
        {:ok, stream} ->
          stream
          |> RunResultStreaming.raw_events()
          |> Enum.each(&print_event/1)

          IO.puts("\nusage: #{inspect(RunResultStreaming.usage(stream))}")

        {:error, reason} ->
          Mix.raise("Streaming run failed: #{inspect(reason)}")
      end

      handled = drain_handled_approvals([])

      if handled == [] do
        IO.puts("No approval requests were observed for this prompt.")
      else
        IO.puts("Handled approvals: #{Enum.join(Enum.reverse(handled), ", ")}")
      end

      send(approval_pid, :stop)
    after
      :ok = Codex.AppServer.disconnect(conn)
    end
  end

  defp approval_loop(conn, parent) do
    receive do
      :stop ->
        :ok

      {:codex_request, id, "item/commandExecution/requestApproval", params} ->
        decision = command_decision(params)
        :ok = Codex.AppServer.respond(conn, id, %{decision: decision})
        send(parent, {:approval_handled, "commandExecution"})
        approval_loop(conn, parent)

      {:codex_request, id, "item/fileChange/requestApproval", _params} ->
        :ok = Codex.AppServer.respond(conn, id, %{decision: "accept"})
        send(parent, {:approval_handled, "fileChange"})
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

  defp drain_handled_approvals(acc) do
    receive do
      {:approval_handled, kind} ->
        drain_handled_approvals([kind | acc])
    after
      0 ->
        acc
    end
  end

  defp print_event(%Events.ItemAgentMessageDelta{item: %{"text" => delta}})
       when is_binary(delta) do
    IO.write(delta)
  end

  defp print_event(%Events.ItemCompleted{item: %Items.AgentMessage{text: text}}) do
    if is_binary(text) and String.trim(text) != "" do
      IO.puts("\n\n[agent_message.completed]\n#{text}\n")
    end
  end

  defp print_event(%Events.TurnCompleted{status: status}) do
    IO.puts("\n[turn.completed] status=#{inspect(status)}")
  end

  defp print_event(_other), do: :ok

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

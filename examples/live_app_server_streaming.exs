Mix.Task.run("app.start")

alias Codex.RunResultStreaming
alias Codex.Events
alias Codex.Items

defmodule CodexExamples.LiveAppServerStreaming do
  @moduledoc false

  @default_prompt "Reply with exactly ok and nothing else."

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
      {:ok, thread} =
        Codex.start_thread(codex_opts, %{
          transport: {:app_server, conn},
          working_directory: File.cwd!()
        })

      IO.puts("""
      Streaming over app-server.
        prompt: #{prompt}
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
    after
      :ok = Codex.AppServer.disconnect(conn)
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

CodexExamples.LiveAppServerStreaming.main(System.argv())

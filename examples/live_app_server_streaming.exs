Mix.Task.run("app.start")

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias CodexExamples.Support

Support.init!()

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

    case Support.ensure_remote_working_directory() do
      :ok ->
        :ok

      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")
        System.halt(0)
    end

    codex_opts = Support.codex_options!()
    :ok = Support.ensure_app_server_supported(codex_opts)

    {:ok, conn} = Codex.AppServer.connect(codex_opts, init_timeout_ms: 30_000)

    try do
      {:ok, thread} =
        Codex.start_thread(
          codex_opts,
          Support.thread_opts!(%{
            transport: {:app_server, conn},
            working_directory: Support.example_working_directory()
          })
        )

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
end

CodexExamples.LiveAppServerStreaming.main(System.argv())

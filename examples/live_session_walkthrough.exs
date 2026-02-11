Mix.Task.run("app.start")

defmodule CodexExamples.LiveSessionWalkthrough do
  def main(argv) do
    prompt =
      case argv do
        [] ->
          "Summarize this repository in three bullets."

        values ->
          Enum.join(values, " ")
      end

    codex_opts =
      Codex.Options.new(%{
        codex_path_override: fetch_codex_path!(),
        model: Codex.Models.default_model()
      })
      |> unwrap!("codex options")

    thread_opts =
      Codex.Thread.Options.new(%{
        labels: %{example: "live-session"},
        metadata: %{origin: "mix run example"}
      })
      |> unwrap!("thread options")

    IO.puts("""
    Running against the live Codex CLI. Auth will use CODEX_API_KEY if set, otherwise your CLI login.
    Prompt: #{prompt}
    """)

    with {:ok, thread} <- Codex.start_thread(codex_opts, thread_opts),
         {:ok, first} <- Codex.Thread.run(thread, prompt) do
      print_turn("First reply", first)

      follow_up = "Suggest two next actions, numbered, that build on your previous answer."

      with {:ok, second} <- Codex.Thread.run(first.thread, follow_up) do
        print_turn("Follow-up", second)

        IO.puts("""
        Conversation complete.
        Thread ID: #{second.thread.thread_id || "pending"}
        """)

        case Codex.Sessions.list_sessions() do
          {:ok, [latest | _]} ->
            IO.puts("Latest session metadata: #{inspect(latest.metadata)}")

          {:ok, []} ->
            IO.puts("No session files found under ~/.codex/sessions.")

          {:error, reason} ->
            IO.puts("Failed to list sessions: #{inspect(reason)}")
        end
      else
        {:error, reason} -> Mix.raise("Follow-up turn failed: #{inspect(reason)}")
      end
    else
      {:error, reason} -> Mix.raise("Failed to start thread: #{inspect(reason)}")
    end
  end

  defp print_turn(label, %Codex.Turn.Result{} = result) do
    IO.puts("== #{label} ==")

    case result.final_response do
      %Codex.Items.AgentMessage{text: text} ->
        IO.puts(text)

      %{"type" => "text", "text" => text} ->
        IO.puts(text)

      other ->
        IO.puts(inspect(other))
    end

    if is_map(result.usage) and map_size(result.usage) > 0 do
      IO.puts("Usage: #{inspect(result.usage)}")
    end

    IO.puts("")
  end

  defp fetch_codex_path! do
    System.get_env("CODEX_PATH") ||
      System.find_executable("codex") ||
      Mix.raise("""
      Unable to locate the `codex` CLI.
      Install the Codex CLI and ensure it is on your PATH or set CODEX_PATH.
      """)
  end

  defp unwrap!({:ok, value}, _label), do: value

  defp unwrap!({:error, reason}, label),
    do: Mix.raise("Failed to build #{label}: #{inspect(reason)}")
end

CodexExamples.LiveSessionWalkthrough.main(System.argv())

Mix.Task.run("app.start")

defmodule CodexExamples.LiveCLISession do
  @moduledoc """
  Demonstrates a root `codex` session launched through `Codex.CLI`.

  This example uses prompt mode so the session exits after streaming a response:

      mix run examples/live_cli_session.exs "Summarize this repository in three bullets"
  """

  @default_prompt "Summarize this repository in three bullets."

  def main(argv) do
    prompt =
      case argv do
        [] -> @default_prompt
        values -> Enum.join(values, " ")
      end

    {:ok, codex_opts} =
      Codex.Options.new(%{
        codex_path_override: fetch_codex_path!()
      })

    IO.puts("Launching prompt-mode `codex` session via PTY...")
    IO.puts("Prompt: #{prompt}\n")

    with {:ok, session} <-
           Codex.CLI.interactive(prompt,
             codex_opts: codex_opts,
             config_overrides: %{"model_reasoning_effort" => "low"}
           ),
         :ok <- close_input(session),
         {:ok, result} <- Codex.CLI.Session.collect(session, 120_000) do
      if String.trim(result.stdout) != "" do
        IO.puts("stdout:\n#{result.stdout}")
      end

      if String.trim(result.stderr) != "" do
        IO.puts("\nstderr:\n#{result.stderr}")
      end

      IO.puts("\nExit code: #{result.exit_code}")
    else
      {:error, reason} ->
        Mix.raise("CLI session failed: #{inspect(reason)}")
    end
  end

  defp close_input(session) do
    case Codex.CLI.Session.close_input(session) do
      :ok -> :ok
      {:error, :stdin_unavailable} -> :ok
      {:error, reason} -> {:error, reason}
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
end

CodexExamples.LiveCLISession.main(System.argv())

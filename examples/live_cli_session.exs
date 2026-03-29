Mix.Task.run("app.start")

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias CodexExamples.Support

Support.init!()

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

    case Support.ensure_remote_working_directory(
           "this SSH CLI session example requires --cwd <remote trusted directory> because raw prompt-mode codex sessions do not expose --skip-git-repo-check"
         ) do
      :ok ->
        :ok

      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")
        System.halt(0)
    end

    codex_opts =
      Support.codex_options!(%{})

    cli_opts =
      Support.command_opts(codex_opts: codex_opts)

    IO.puts("Launching prompt-mode `codex` session via PTY...")
    IO.puts("Prompt: #{prompt}\n")

    with {:ok, session} <-
           Codex.CLI.interactive(
             prompt,
             Keyword.merge(cli_opts, config_overrides: %{"model_reasoning_effort" => "low"})
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
end

CodexExamples.LiveCLISession.main(System.argv())

Mix.Task.run("app.start")

defmodule CodexExamples.LiveCLIPassthrough do
  @moduledoc """
  Demonstrates the raw Codex CLI passthrough helpers.

  Examples:

      mix run examples/live_cli_passthrough.exs completion zsh
      mix run examples/live_cli_passthrough.exs features-list
      mix run examples/live_cli_passthrough.exs login-status
      mix run examples/live_cli_passthrough.exs raw cloud list --json
  """

  def main(argv) do
    {:ok, codex_opts} =
      Codex.Options.new(%{
        codex_path_override: fetch_codex_path!()
      })

    case argv do
      ["completion", shell] ->
        run_and_print(fn -> Codex.CLI.completion(shell, codex_opts: codex_opts) end)

      ["features-list"] ->
        run_and_print(fn -> Codex.CLI.features_list(codex_opts: codex_opts) end)

      ["login-status"] ->
        run_and_print(fn -> Codex.CLI.login_status(codex_opts: codex_opts) end)

      ["raw" | args] when args != [] ->
        run_and_print(fn -> Codex.CLI.run(args, codex_opts: codex_opts) end)

      _ ->
        IO.puts("""
        Usage:
          mix run examples/live_cli_passthrough.exs completion <shell>
          mix run examples/live_cli_passthrough.exs features-list
          mix run examples/live_cli_passthrough.exs login-status
          mix run examples/live_cli_passthrough.exs raw <codex args...>
        """)
    end
  end

  defp run_and_print(fun) do
    case fun.() do
      {:ok, result} ->
        IO.puts("Exit code: #{result.exit_code}")

        if String.trim(result.stdout) != "" do
          IO.puts("\nstdout:\n#{result.stdout}")
        end

        if String.trim(result.stderr) != "" do
          IO.puts("\nstderr:\n#{result.stderr}")
        end

      {:error, reason} ->
        Mix.raise("CLI passthrough failed: #{inspect(reason)}")
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

CodexExamples.LiveCLIPassthrough.main(System.argv())

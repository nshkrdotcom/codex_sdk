Mix.Task.run("app.start")

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias CodexExamples.Support

Support.init!()

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
    codex_opts =
      Support.codex_options!(%{})

    cli_opts = Support.command_opts(codex_opts: codex_opts)

    case argv do
      ["completion", shell] ->
        run_and_print(fn -> Codex.CLI.completion(shell, cli_opts) end)

      ["features-list"] ->
        run_and_print(fn -> Codex.CLI.features_list(cli_opts) end)

      ["login-status"] ->
        run_and_print(fn -> Codex.CLI.login_status(cli_opts) end)

      ["raw" | args] when args != [] ->
        run_and_print(fn -> Codex.CLI.run(args, cli_opts) end)

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
end

CodexExamples.LiveCLIPassthrough.main(System.argv())

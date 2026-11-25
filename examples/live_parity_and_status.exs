Mix.Task.run("app.start")

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias CodexExamples.Support

Support.init!()

defmodule CodexExamples.LiveParityAndStatus do
  @moduledoc false

  def main(_argv) do
    case Support.codex_options(%{}, missing_cli: :skip) do
      {:ok, opts} ->
        case opts.execution_surface do
          %CliSubprocessCore.ExecutionSurface{
            surface_kind: :ssh_exec,
            transport_options: transport
          } ->
            IO.puts("codex CLI route: ssh_exec destination=#{transport[:destination]}")

          _other ->
            case Codex.Options.codex_path(opts) do
              {:ok, path} -> IO.puts("codex CLI detected at #{path}")
              {:error, reason} -> IO.puts("codex CLI not found (#{inspect(reason)})")
            end
        end

      {:skip, reason} ->
        IO.puts("codex CLI unavailable: #{reason}")

      {:error, reason} ->
        IO.puts("Unable to build options: #{inspect(reason)}")
    end

    IO.puts("""
    For CLI setup and authentication, see guides/01-getting-started.md.
    For supported app-server calls, see guides/05-app-server-transport.md.
    """)
  end

end

CodexExamples.LiveParityAndStatus.main(System.argv())

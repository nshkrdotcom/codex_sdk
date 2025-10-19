defmodule Mix.Tasks.Codex.Verify do
  @moduledoc """
  Runs the recommended verification steps (compile, format, test).
  """

  use Mix.Task

  @shortdoc "Run compile/format/test checks"
  @preferred_cli_env :test

  @impl Mix.Task
  def run(args) do
    dry_run? = Enum.any?(args, &(&1 == "--dry-run"))

    commands = [
      {"compile --warnings-as-errors",
       fn -> Mix.Task.rerun("compile", ["--warnings-as-errors"]) end},
      {"format --check-formatted", fn -> Mix.Task.run("format", ["--check-formatted"]) end},
      {"test", fn -> Mix.Task.run("test", []) end}
    ]

    Enum.each(commands, fn {label, fun} ->
      if dry_run? do
        Mix.shell().info("[dry-run] #{label}")
      else
        Mix.shell().info("Running #{label}...")
        fun.()
      end
    end)
  end
end

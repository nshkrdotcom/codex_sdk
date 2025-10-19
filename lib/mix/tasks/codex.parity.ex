defmodule Mix.Tasks.Codex.Parity do
  @moduledoc """
  Summarises harvested Python fixtures and highlights gaps.
  """

  use Mix.Task

  @shortdoc "Summarise parity fixtures"

  @impl Mix.Task
  def run(_args) do
    fixtures_dir = Path.join([File.cwd!(), "integration", "fixtures", "python"])

    fixtures =
      fixtures_dir
      |> File.ls!()
      |> Enum.sort()

    Mix.shell().info("Found #{length(fixtures)} Python fixtures:")

    Enum.each(fixtures, fn fixture ->
      Mix.shell().info("  - #{fixture}")
    end)
  end
end

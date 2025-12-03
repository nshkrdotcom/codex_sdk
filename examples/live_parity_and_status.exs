# Covers ADR-013 (parity fixtures + status)
Mix.Task.run("app.start")

defmodule CodexExamples.LiveParityAndStatus do
  @moduledoc false

  @adrs Path.expand("../docs/20251202/adrs", __DIR__)
  @parity_notes Path.expand("../docs/20251202/python-parity", __DIR__)
  @fixture_modules Path.expand("../test/support", __DIR__)

  def main(_argv) do
    IO.puts("""
    Parity snapshot (Elixir SDK vs Python):
      ADRs: #{count(@adrs)} files at docs/20251202/adrs
      Parity notes: #{count(@parity_notes)} documents at docs/20251202/python-parity
      Fixtures/helpers: #{fixture_modules()} under test/support
      Integration samples: integration/ and examples/ (live Codex CLI)
    """)

    case Codex.Options.new(%{}) do
      {:ok, opts} ->
        case Codex.Options.codex_path(opts) do
          {:ok, path} -> IO.puts("codex CLI detected at #{path}")
          {:error, reason} -> IO.puts("codex CLI not found (#{inspect(reason)})")
        end

      {:error, reason} ->
        IO.puts("Unable to build options: #{inspect(reason)}")
    end

    IO.puts("""
    For fixture details, see:
      - docs/20251202/python-parity/008-tests-and-fixtures.md
      - test/support/parity_matrix.ex for the latest parity coverage tags
    """)
  end

  defp count(path) do
    if File.dir?(path) do
      path |> File.ls!() |> length()
    else
      0
    end
  end

  defp fixture_modules do
    @fixture_modules
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".ex"))
    |> Enum.join(", ")
  end
end

CodexExamples.LiveParityAndStatus.main(System.argv())

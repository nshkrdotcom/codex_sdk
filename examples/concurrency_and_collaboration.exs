#!/usr/bin/env mix run

alias Codex.Items

defmodule Examples.Concurrency do
  @moduledoc false

  def parallel_analysis(files) do
    tasks =
      Enum.map(files, fn file ->
        Task.async(fn ->
          {:ok, thread} = Codex.start_thread()
          {:ok, result} = Codex.Thread.run(thread, "Analyze #{file} for potential issues.")
          {file, render(result.final_response)}
        end)
      end)

    Task.await_many(tasks, 60_000)
    |> Enum.each(fn {file, response} ->
      IO.puts("\n#{file}:\n#{response}")
    end)
  end

  def map_reduce(items) do
    responses =
      items
      |> Enum.map(fn item ->
        Task.async(fn ->
          {:ok, thread} = Codex.start_thread()
          {:ok, result} = Codex.Thread.run(thread, "Process #{item} and summarise it succinctly.")
          render(result.final_response)
        end)
      end)
      |> Task.await_many(60_000)

    {:ok, thread} = Codex.start_thread()

    prompt = """
    Summarise these analyses into a concise checklist:

    #{Enum.join(responses, "\n\n---\n\n")}
    """

    {:ok, result} = Codex.Thread.run(thread, prompt)
    IO.puts("\nSummary:\n#{render(result.final_response)}")
  end

  def collaboration(file) do
    {:ok, analyzer} = Codex.start_thread()
    {:ok, analysis} = Codex.Thread.run(analyzer, "Analyze #{file} for potential issues.")

    {:ok, security} = Codex.start_thread()

    {:ok, security_review} =
      Codex.Thread.run(
        security,
        """
        Review this code for security issues:

        Analysis: #{render(analysis.final_response)}
        """
      )

    {:ok, performance} = Codex.start_thread()

    {:ok, perf_review} =
      Codex.Thread.run(
        performance,
        """
        Review this code for performance issues:

        Analysis: #{render(analysis.final_response)}
        """
      )

    {:ok, synthesizer} = Codex.start_thread()

    prompt = """
    Synthesize these reviews into actionable recommendations:

    Security Review:
    #{render(security_review.final_response)}

    Performance Review:
    #{render(perf_review.final_response)}
    """

    {:ok, result} = Codex.Thread.run(synthesizer, prompt)

    IO.puts("\nFinal Recommendations:")
    IO.puts(render(result.final_response))
  end

  defp render(%Items.AgentMessage{text: text}), do: text
  defp render(_), do: "(no response produced)"
end

case System.argv() do
  ["parallel" | files] when files != [] ->
    Examples.Concurrency.parallel_analysis(files)

  ["parallel"] ->
    Examples.Concurrency.parallel_analysis(["lib/codex/thread.ex", "lib/codex/exec.ex"])

  ["map-reduce" | items] when items != [] ->
    Examples.Concurrency.map_reduce(items)

  ["map-reduce"] ->
    Examples.Concurrency.map_reduce(["State machine module", "Telemetry events", "Docs"])

  ["collaborate", file] ->
    Examples.Concurrency.collaboration(file)

  ["collaborate"] ->
    Examples.Concurrency.collaboration("lib/codex/thread.ex")

  ["help"] ->
    IO.puts("""
    mix run examples/concurrency_and_collaboration.exs [command]

      parallel [files...]    – run analysis concurrently
      map-reduce [items...]  – process items concurrently then summarise the results
      collaborate [file]     – run the multi-agent collaboration workflow
      help                   – show this usage
    """)

  _ ->
    Examples.Concurrency.parallel_analysis(["lib/codex/thread.ex"])
end

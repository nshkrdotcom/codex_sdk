#!/usr/bin/env mix run

alias Codex.Items

defmodule Examples.Concurrency do
  @moduledoc false

  def parallel_analysis(files) do
    tasks =
      Enum.map(files, fn file ->
        Task.async(fn ->
          {:ok, thread} = Codex.start_thread()

          prompt = """
          Analyze `#{file}` for potential issues based on common Elixir patterns.
          Read the file contents if you need them, and keep it to 4 bullets.
          """

          case Codex.Thread.run(thread, prompt, %{timeout_ms: 90_000}) do
            {:ok, result} -> {file, render(result.final_response)}
            {:error, reason} -> {file, "FAILED: #{inspect(reason)}"}
          end
        end)
      end)

    await_many_with_progress(tasks, timeout_ms: 180_000, tick_ms: 5_000, label: "parallel")
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
          prompt = "Process #{item} and summarise it succinctly (1-2 sentences)."

          case Codex.Thread.run(thread, prompt, %{timeout_ms: 45_000}) do
            {:ok, result} -> render(result.final_response)
            {:error, reason} -> "FAILED: #{inspect(reason)}"
          end
        end)
      end)
      |> await_many_with_progress(timeout_ms: 180_000, tick_ms: 5_000, label: "map-reduce")

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

    {:ok, analysis} =
      Codex.Thread.run(
        analyzer,
        "Analyze #{file} for potential issues. Read the file contents if needed."
      )

    {:ok, security} = Codex.start_thread()

    {:ok, security_review} =
      Codex.Thread.run(
        security,
        """
        Review #{file} for security issues. Read the file contents if needed.

        Analysis: #{render(analysis.final_response)}
        """
      )

    {:ok, performance} = Codex.start_thread()

    {:ok, perf_review} =
      Codex.Thread.run(
        performance,
        """
        Review #{file} for performance issues. Read the file contents if needed.

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

  defp await_many_with_progress(tasks, opts) do
    timeout_ms = Keyword.fetch!(opts, :timeout_ms)
    tick_ms = Keyword.fetch!(opts, :tick_ms)
    label = Keyword.get(opts, :label, "tasks")

    start = System.monotonic_time(:millisecond)
    do_await_many_with_progress(tasks, start, timeout_ms, tick_ms, label)
  end

  defp do_await_many_with_progress(tasks, start_ms, timeout_ms, tick_ms, label) do
    remaining_ms = timeout_ms - (System.monotonic_time(:millisecond) - start_ms)

    if remaining_ms <= 0 do
      Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
      raise "Timed out waiting for #{label} tasks (#{timeout_ms}ms)"
    end

    wait_ms = min(tick_ms, remaining_ms)

    yielded =
      tasks
      |> Task.yield_many(wait_ms)
      |> Enum.map(fn {task, res} ->
        {task, res || Task.yield(task, 0)}
      end)

    if Enum.all?(yielded, fn {_task, res} -> res != nil end) do
      Enum.map(yielded, fn
        {_task, {:ok, value}} -> value
        {_task, {:exit, reason}} -> raise "Task failed: #{inspect(reason)}"
      end)
    else
      elapsed_s = div(System.monotonic_time(:millisecond) - start_ms, 1000)
      done = Enum.count(yielded, fn {_task, res} -> res != nil end)
      total = length(yielded)
      IO.puts("… #{label} still running (#{elapsed_s}s) [#{done}/#{total}]")
      do_await_many_with_progress(tasks, start_ms, timeout_ms, tick_ms, label)
    end
  end
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

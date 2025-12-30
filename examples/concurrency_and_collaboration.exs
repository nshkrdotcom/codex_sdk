#!/usr/bin/env mix run

alias Codex.Items

defmodule Examples.Concurrency do
  @moduledoc false

  def parallel_analysis(files) do
    files = Enum.take(files, 2)
    timeout_ms = 20_000
    {:ok, supervisor} = Task.Supervisor.start_link()

    tasks =
      Enum.map(files, fn file ->
        Task.Supervisor.async_nolink(supervisor, fn ->
          {:ok, thread} = Codex.start_thread(%{reasoning_effort: :low})

          prompt =
            "Give 2 quick risk notes you'd flag for a module like #{file} based only on its path/name. " <>
              "Do not read the file or run shell commands; if you need to assume, say so."

          case Codex.Thread.run(thread, prompt, %{timeout_ms: timeout_ms, max_turns: 1}) do
            {:ok, result} -> {file, render(result.final_response)}
            {:error, reason} -> {file, "FAILED: #{inspect(reason)}"}
          end
        end)
      end)

    await_many_with_progress(tasks, timeout_ms: 60_000, tick_ms: 5_000, label: "parallel")
    |> Enum.each(fn {file, response} ->
      IO.puts("\n#{file}:\n#{response}")
    end)
  end

  def map_reduce(items) do
    timeout_ms = 20_000
    {:ok, supervisor} = Task.Supervisor.start_link()

    responses =
      items
      |> Enum.map(fn item ->
        Task.Supervisor.async_nolink(supervisor, fn ->
          {:ok, thread} = Codex.start_thread(%{reasoning_effort: :low})
          prompt = "Process #{item} and summarise it succinctly (1-2 sentences)."

          case Codex.Thread.run(thread, prompt, %{timeout_ms: timeout_ms, max_turns: 1}) do
            {:ok, result} -> render(result.final_response)
            {:error, reason} -> "FAILED: #{inspect(reason)}"
          end
        end)
      end)
      |> await_many_with_progress(timeout_ms: 60_000, tick_ms: 5_000, label: "map-reduce")

    {:ok, thread} = Codex.start_thread(%{reasoning_effort: :low})

    prompt = """
    Summarise these analyses into a concise checklist:

    #{Enum.join(responses, "\n\n---\n\n")}
    """

    {:ok, result} = Codex.Thread.run(thread, prompt, %{timeout_ms: timeout_ms, max_turns: 1})
    IO.puts("\nSummary:\n#{render(result.final_response)}")
  end

  def collaboration(file) do
    timeout_ms = 20_000
    {:ok, analyzer} = Codex.start_thread(%{reasoning_effort: :low})

    {:ok, analysis} =
      Codex.Thread.run(
        analyzer,
        "Analyze #{file} for potential issues based only on its path/name. " <>
          "Do not read the file or run shell commands; if you need to assume, say so.",
        %{timeout_ms: timeout_ms, max_turns: 1}
      )

    {:ok, security} = Codex.start_thread(%{reasoning_effort: :low})

    {:ok, security_review} =
      Codex.Thread.run(
        security,
        """
        Review #{file} for security issues based only on the prior analysis. Do not read the file.

        Analysis: #{render(analysis.final_response)}
        """,
        %{timeout_ms: timeout_ms, max_turns: 1}
      )

    {:ok, performance} = Codex.start_thread(%{reasoning_effort: :low})

    {:ok, perf_review} =
      Codex.Thread.run(
        performance,
        """
        Review #{file} for performance issues based only on the prior analysis. Do not read the file.

        Analysis: #{render(analysis.final_response)}
        """,
        %{timeout_ms: timeout_ms, max_turns: 1}
      )

    {:ok, synthesizer} = Codex.start_thread(%{reasoning_effort: :low})

    prompt = """
    Synthesize these reviews into actionable recommendations:

    Security Review:
    #{render(security_review.final_response)}

    Performance Review:
    #{render(perf_review.final_response)}
    """

    {:ok, result} = Codex.Thread.run(synthesizer, prompt, %{timeout_ms: timeout_ms, max_turns: 1})

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
    pending = MapSet.new(tasks)
    do_await_many_with_progress(tasks, pending, %{}, start, timeout_ms, tick_ms, label)
  end

  defp do_await_many_with_progress(tasks, pending, results, start_ms, timeout_ms, tick_ms, label) do
    remaining_ms = timeout_ms - (System.monotonic_time(:millisecond) - start_ms)

    if remaining_ms <= 0 do
      Enum.each(pending, &Task.shutdown(&1, :brutal_kill))

      results =
        Enum.reduce(pending, results, fn task, acc ->
          Map.put(acc, task, {:exit, :timeout})
        end)

      done = length(tasks) - MapSet.size(pending)
      IO.puts("… #{label} timed out (#{timeout_ms}ms) [#{done}/#{length(tasks)}]")
      collect_results(tasks, results)
    else
      wait_ms = min(tick_ms, remaining_ms)

      {pending, results} =
        pending
        |> MapSet.to_list()
        |> Task.yield_many(wait_ms)
        |> Enum.reduce({pending, results}, fn {task, res}, {pending, results} ->
          case res do
            nil -> {pending, results}
            _ -> {MapSet.delete(pending, task), Map.put(results, task, res)}
          end
        end)

      if MapSet.size(pending) == 0 do
        collect_results(tasks, results)
      else
        elapsed_s = div(System.monotonic_time(:millisecond) - start_ms, 1000)
        done = length(tasks) - MapSet.size(pending)
        IO.puts("… #{label} still running (#{elapsed_s}s) [#{done}/#{length(tasks)}]")
        do_await_many_with_progress(tasks, pending, results, start_ms, timeout_ms, tick_ms, label)
      end
    end
  end

  defp collect_results(tasks, results) do
    Enum.map(tasks, fn task ->
      case Map.get(results, task) do
        {:ok, value} -> value
        {:exit, reason} -> "FAILED: #{inspect(reason)}"
        nil -> "FAILED: :timeout"
      end
    end)
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
    Examples.Concurrency.parallel_analysis(["lib/codex/thread.ex", "lib/codex/exec.ex"])
end

#!/usr/bin/env mix run

alias Codex.Items

defmodule Examples.BasicUsage do
  @moduledoc false

  def ask_question do
    with {:ok, thread} <- Codex.start_thread(),
         {:ok, result} <- Codex.Thread.run(thread, "What is a GenServer in Elixir?") do
      IO.puts("Final response:\n#{render_response(result.final_response)}\n")
      IO.puts("Token usage: #{format_usage(result.usage)}")
    end
  end

  def list_completed_items do
    prompt = "Explain how Elixir processes work, and give me a simple example"

    with {:ok, thread} <- Codex.start_thread(),
         {:ok, result} <- Codex.Thread.run(thread, prompt) do
      Enum.each(result.events, &print_event/1)
    end
  end

  defp print_event(%Codex.Events.ItemCompleted{item: %Items.AgentMessage{text: text}}) do
    IO.puts("\n[Agent Message]\n#{text}")
  end

  defp print_event(%Codex.Events.ItemCompleted{item: %Items.Reasoning{text: text}}) do
    IO.puts("\n[Reasoning]\n#{text}")
  end

  defp print_event(%Codex.Events.ItemCompleted{
         item: %Items.CommandExecution{command: command, exit_code: exit_code, status: status}
       }) do
    IO.puts("\n[Command Execution]")
    IO.puts("  command:   #{command}")
    IO.puts("  exit_code: #{inspect(exit_code)}")
    IO.puts("  status:    #{status}")
  end

  defp print_event(%Codex.Events.ItemCompleted{
         item: %Items.FileChange{changes: changes, status: status}
       }) do
    IO.puts("\n[File Change] (#{status})")

    Enum.each(changes, fn %{path: path, kind: kind} ->
      IO.puts("  #{kind}: #{path}")
    end)
  end

  defp print_event(%Codex.Events.ItemCompleted{item: other}) do
    IO.puts("\n[Completed Item]")
    IO.inspect(other, label: "item")
  end

  defp print_event(_), do: :ok

  defp render_response(%Items.AgentMessage{text: text}), do: text
  defp render_response(_), do: "(no message produced)"

  defp format_usage(nil), do: "n/a"

  defp format_usage(usage) when is_map(usage) do
    input = Map.get(usage, "input_tokens") || Map.get(usage, :input_tokens) || 0
    output = Map.get(usage, "output_tokens") || Map.get(usage, :output_tokens) || 0
    total = Map.get(usage, "total_tokens") || Map.get(usage, :total_tokens) || input + output
    "input=#{input}, output=#{output}, total=#{total}"
  end
end

case System.argv() do
  ["items"] ->
    Examples.BasicUsage.list_completed_items()

  ["help"] ->
    IO.puts("""
    mix run examples/basic_usage.exs [command]

      (no arg)   – run the simple Q&A example
      items      – run the completed-items walkthrough
      help       – show this usage
    """)

  _ ->
    Examples.BasicUsage.ask_question()
end

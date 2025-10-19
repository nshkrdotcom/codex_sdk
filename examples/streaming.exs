#!/usr/bin/env mix run

alias Codex.Items
alias Codex.Events

defmodule Examples.Streaming do
  @moduledoc false

  def realtime_stream do
    {:ok, thread} = Codex.start_thread()

    {:ok, stream} =
      Codex.Thread.run_streamed(
        thread,
        "Inspect the project structure and call out any missing README sections"
      )

    Enum.each(stream, &handle_event/1)
  end

  def progressive_story do
    {:ok, thread} = Codex.start_thread()

    {:ok, stream} =
      Codex.Thread.run_streamed(thread, "Write a short story about a robot learning Elixir")

    stream
    |> Stream.filter(fn
      %Events.ItemCompleted{item: %Items.AgentMessage{}} -> true
      _ -> false
    end)
    |> Enum.each(fn %Events.ItemCompleted{item: %Items.AgentMessage{text: text}} ->
      text
      |> String.graphemes()
      |> Enum.each(fn char ->
        IO.write(char)
        Process.sleep(20)
      end)

      IO.puts("\n")
    end)
  end

  def stateful_stream do
    {:ok, thread} = Codex.start_thread()

    {:ok, stream} =
      Codex.Thread.run_streamed(thread, "Implement a new feature across the codebase")

    final_state =
      Enum.reduce(stream, initial_state(), fn event, state ->
        case event do
          %Events.ThreadStarted{thread_id: id} ->
            %{state | thread_id: id}

          %Events.ItemCompleted{item: %Items.CommandExecution{} = cmd} ->
            %{state | commands: [cmd | state.commands]}

          %Events.ItemCompleted{item: %Items.FileChange{} = file} ->
            %{state | files: [file | state.files]}

          %Events.ItemCompleted{item: %Items.AgentMessage{text: text}} ->
            %{state | messages: [text | state.messages]}

          %Events.TurnCompleted{usage: usage} when is_map(usage) ->
            %{state | usage: usage}

          _ ->
            state
        end
      end)

    IO.inspect(final_state, label: "stream summary")
  end

  defp handle_event(%Events.ThreadStarted{thread_id: id}) do
    IO.puts("Started thread #{id}")
  end

  defp handle_event(%Events.TurnStarted{}), do: IO.puts("Turn started…")

  defp handle_event(%Events.ItemStarted{item: %Items.CommandExecution{command: command}}) do
    IO.puts("Executing command: #{command}")
  end

  defp handle_event(%Events.ItemCompleted{item: %Items.AgentMessage{text: text}}) do
    IO.puts("\n=== Agent Message ===\n#{text}")
  end

  defp handle_event(%Events.TurnCompleted{usage: usage}) do
    IO.puts("\nTurn completed (usage=#{inspect(usage)})")
  end

  defp handle_event(_), do: :ok

  defp initial_state do
    %{
      thread_id: nil,
      commands: [],
      files: [],
      messages: [],
      usage: nil
    }
  end
end

case System.argv() do
  ["progressive"] ->
    Examples.Streaming.progressive_story()

  ["stateful"] ->
    Examples.Streaming.stateful_stream()

  ["help"] ->
    IO.puts("""
    mix run examples/streaming.exs [command]

      (no arg)    – run the real-time streaming example
      progressive – stream output character by character
      stateful    – accumulate streaming state in a map
      help        – show this usage
    """)

  _ ->
    Examples.Streaming.realtime_stream()
end

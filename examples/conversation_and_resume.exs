#!/usr/bin/env mix run

alias Codex.Items

defmodule Examples.Conversation do
  @moduledoc false

  def multi_turn do
    {:ok, codex_opts} = Codex.Options.new(%{model: "gpt-5.2-codex"})
    {:ok, thread} = Codex.start_thread(codex_opts)

    {:ok, result1} =
      Codex.Thread.run(thread, "I have a GenServer that crashes when I call {:stop, reason}.")

    thread = result1.thread

    IO.puts("Agent: #{render(result1.final_response)}")

    {:ok, result2} =
      Codex.Thread.run(thread, "Can you show me how to handle that message correctly?")

    thread = result2.thread

    IO.puts("\nAgent: #{render(result2.final_response)}")

    {:ok, result3} =
      Codex.Thread.run(thread, "What if I need to clean up resources before stopping?")

    thread = result3.thread

    IO.puts("\nAgent: #{render(result3.final_response)}")
    IO.puts("\nThread ID: #{thread.thread_id}")
  end

  def resume_existing(thread_id) do
    {:ok, codex_opts} = Codex.Options.new(%{model: "gpt-5.2-codex"})
    {:ok, thread} = Codex.resume_thread(thread_id, codex_opts)

    {:ok, result} =
      Codex.Thread.run(thread, "Can you remind me what we were discussing?")

    IO.puts("Agent (resumed): #{render(result.final_response)}")
  end

  def save_and_resume_demo do
    {:ok, codex_opts} = Codex.Options.new(%{model: "gpt-5.2-codex"})
    {:ok, thread} = Codex.start_thread(codex_opts)
    {:ok, result1} = Codex.Thread.run(thread, "Remember the number 42 for me.")
    thread = result1.thread

    IO.puts("Agent: #{render(result1.final_response)}")

    File.write!("thread_id.txt", thread.thread_id)

    saved_id = File.read!("thread_id.txt") |> String.trim()
    {:ok, resumed} = Codex.resume_thread(saved_id, codex_opts)

    {:ok, result2} = Codex.Thread.run(resumed, "What number should I remember?")
    IO.puts("Agent (after resume): #{render(result2.final_response)}")
  end

  defp render(%Items.AgentMessage{text: text}), do: text
  defp render(_), do: "(no response produced)"
end

case System.argv() do
  ["multi"] ->
    Examples.Conversation.multi_turn()

  ["resume", thread_id] ->
    Examples.Conversation.resume_existing(thread_id)

  ["save-resume"] ->
    Examples.Conversation.save_and_resume_demo()

  ["help"] ->
    IO.puts("""
    mix run examples/conversation_and_resume.exs [command]

      multi         – run the multi-turn conversation example
      resume ID     – resume an existing thread by ID
      save-resume   – demonstrate saving and resuming a thread id locally
      help          – show this usage
    """)

  _ ->
    Examples.Conversation.multi_turn()
end

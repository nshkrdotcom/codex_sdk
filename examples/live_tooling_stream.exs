Mix.Task.run("app.start")

alias Codex.{Events, Items, Options, RunResultStreaming, Thread}

defmodule CodexExamples.LiveToolingStream do
  @moduledoc false

  @default_prompt """
  Give me two quick observations about this repository. If you need more context,
  feel free to run one short shell command (like `ls`) and include the output.
  """

  def main(argv) do
    prompt = parse_prompt(argv)

    codex_opts =
      Options.new(%{codex_path_override: fetch_codex_path!()})
      |> unwrap!("codex options")

    thread_opts =
      Thread.Options.new(%{
        labels: %{example: "live-tooling-stream"},
        metadata: %{example: "live-tooling-stream"}
      })
      |> unwrap!("thread options")

    IO.puts("""
    Running against the live Codex CLI (uses CODEX_API_KEY if set, otherwise your CLI login).
    Prompt: #{prompt}
    """)

    with {:ok, thread} <- Codex.start_thread(codex_opts, thread_opts),
         {:ok, result} <- Thread.run_streamed(thread, prompt) do
      state =
        result
        |> RunResultStreaming.raw_events()
        |> Enum.reduce(%{final_response: nil, last_agent_message: nil}, fn event, acc ->
          handle_event(event)

          case event do
            %Events.TurnCompleted{final_response: resp} ->
              %{acc | final_response: resp || acc.last_agent_message}

            %Events.ItemCompleted{item: %Items.AgentMessage{} = msg} ->
              %{acc | last_agent_message: msg}

            _ ->
              acc
          end
        end)

      IO.puts("\nFinal response:")
      IO.puts(render_response(state.final_response || state.last_agent_message))
    else
      {:error, reason} ->
        Mix.raise("Failed to run live turn: #{inspect(reason)}")
    end
  end

  defp handle_event(%Events.ThreadStarted{thread_id: id}) do
    IO.puts("Thread started: #{id}")
  end

  defp handle_event(%Events.TurnStarted{}), do: IO.puts("Turn started…")

  defp handle_event(%Events.ItemStarted{item: %Items.CommandExecution{command: cmd}}) do
    IO.puts("Shell command requested: #{cmd}")
  end

  defp handle_event(%Events.ItemUpdated{item: %Items.CommandExecution{} = item}) do
    IO.puts("Command update (status=#{item.status}): #{safe_output(item.aggregated_output)}")
  end

  defp handle_event(%Events.ItemCompleted{item: %Items.CommandExecution{} = item}) do
    IO.puts("""
    Command completed (status=#{item.status}, exit=#{inspect(item.exit_code)}):
    #{safe_output(item.aggregated_output)}
    """)
  end

  defp handle_event(%Events.ItemStarted{item: %Items.McpToolCall{} = item}) do
    IO.puts("MCP tool started: #{item.server}/#{item.tool} args=#{inspect(item.arguments)}")
  end

  defp handle_event(%Events.ItemUpdated{item: %Items.McpToolCall{} = item}) do
    IO.puts("MCP tool update (status=#{item.status}): #{summarize_result(item.result)}")
  end

  defp handle_event(%Events.ItemCompleted{item: %Items.McpToolCall{} = item}) do
    IO.puts("""
    MCP tool completed (status=#{item.status}):
      server/tool: #{item.server}/#{item.tool}
      arguments: #{inspect(item.arguments)}
      result: #{summarize_result(item.result)}
      error: #{inspect(item.error)}
    """)
  end

  defp handle_event(%Events.ItemCompleted{item: %Items.AgentMessage{text: text}}) do
    IO.puts("\nAgent message:\n#{text}\n")
  end

  defp handle_event(%Events.TurnCompleted{usage: usage}) when is_map(usage) do
    IO.puts("Turn completed, usage: #{inspect(usage)}")
  end

  defp handle_event(_), do: :ok

  defp summarize_result(nil), do: "<none>"

  defp summarize_result(%{"content" => content} = result) do
    first =
      content
      |> List.wrap()
      |> Enum.map(&inspect/1)
      |> Enum.join(", ")

    "#{first} | structured=#{inspect(Map.get(result, "structured_content"))}"
  end

  defp summarize_result(other), do: inspect(other)

  defp safe_output(nil), do: "<no output yet>"
  defp safe_output(""), do: "<no output yet>"
  defp safe_output(output) when is_binary(output), do: String.slice(output, 0, 400)
  defp safe_output(other), do: inspect(other)

  defp render_response(%Items.AgentMessage{text: text}), do: text
  defp render_response(%{"text" => text}), do: text
  defp render_response(nil), do: "<no final response>"
  defp render_response(other), do: inspect(other)

  defp parse_prompt([prompt | rest]) do
    Enum.join([prompt | rest], " ")
  end

  defp parse_prompt(_), do: String.trim(@default_prompt)

  defp fetch_codex_path! do
    System.get_env("CODEX_PATH") ||
      System.find_executable("codex") ||
      Mix.raise("""
      Unable to locate the `codex` CLI.
      Install the Codex CLI and ensure it is on your PATH or set CODEX_PATH.
      """)
  end

  defp unwrap!({:ok, value}, _label), do: value

  defp unwrap!({:error, reason}, label),
    do: Mix.raise("Failed to build #{label}: #{inspect(reason)}")
end

CodexExamples.LiveToolingStream.main(System.argv())

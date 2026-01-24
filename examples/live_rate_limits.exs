Mix.Task.run("app.start")

alias Codex.{Error, Events, Items, Options, RunResultStreaming, Thread, TransportError}
alias Codex.Protocol.RateLimit, as: RateLimitSnapshot

defmodule LiveRateLimits do
  @moduledoc false

  @default_prompt "Summarize the top-level structure of this repository in 3 bullets."

  def main(argv) do
    prompt = parse_prompt(argv)
    codex_path = fetch_codex_path!()

    {:ok, codex_opts} = Options.new(%{codex_path_override: codex_path})
    {:ok, thread} = Codex.start_thread(codex_opts, %{working_directory: File.cwd!()})

    case Thread.run_streamed(thread, prompt) do
      {:ok, result} ->
        try do
          state =
            result
            |> RunResultStreaming.raw_events()
            |> Enum.reduce(%{last_snapshot: nil, final_response: nil}, &handle_event/2)

          IO.puts("\nFinal response:\n#{state.final_response || "<none>"}")
          IO.puts("\nLatest rate limit snapshot:")
          IO.inspect(state.last_snapshot || "<none>")
        rescue
          error in [Error, TransportError] ->
            render_transport_error(error)
        end

      {:error, reason} ->
        IO.puts("Failed to start streamed turn: #{inspect(reason)}")
    end
  end

  defp handle_event(
         %Events.ThreadTokenUsageUpdated{rate_limits: %RateLimitSnapshot.Snapshot{} = snapshot},
         state
       ) do
    IO.puts("thread/tokenUsage/updated rate limits: #{inspect(snapshot)}")
    %{state | last_snapshot: snapshot}
  end

  defp handle_event(
         %Events.AccountRateLimitsUpdated{rate_limits: %RateLimitSnapshot.Snapshot{} = snapshot},
         state
       ) do
    IO.puts("account/rateLimits/updated: #{inspect(snapshot)}")
    %{state | last_snapshot: snapshot}
  end

  defp handle_event(%Events.ItemCompleted{item: %Items.AgentMessage{text: text}}, state) do
    %{state | final_response: text}
  end

  defp handle_event(%Events.TurnCompleted{final_response: response}, state) do
    %{state | final_response: extract_text(response) || state.final_response}
  end

  defp handle_event(_event, state), do: state

  defp extract_text(%Items.AgentMessage{text: text}) when is_binary(text), do: text
  defp extract_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp extract_text(%{type: "text", text: text}) when is_binary(text), do: text
  defp extract_text(other) when is_binary(other), do: other
  defp extract_text(_), do: nil

  defp parse_prompt([prompt | _]), do: prompt
  defp parse_prompt(_argv), do: @default_prompt

  defp fetch_codex_path! do
    System.get_env("CODEX_PATH") ||
      System.find_executable("codex") ||
      Mix.raise("""
      Unable to locate the `codex` CLI.
      Install the Codex CLI and ensure it is on your PATH or set CODEX_PATH.
      """)
  end

  defp render_transport_error(%Error{} = error) do
    status = error.details[:exit_status]
    stderr = error.details[:stderr]

    IO.puts("""
    Failed to run codex#{format_exit_status(status)}.
    #{error.message}
    Ensure the codex CLI is installed on PATH and you're logged in (or set CODEX_API_KEY).
    stderr: #{String.trim(to_string(stderr || ""))}
    """)
  end

  defp render_transport_error(%TransportError{exit_status: status, stderr: stderr}) do
    IO.puts("""
    Failed to run codex (exit #{inspect(status)}).
    Ensure the codex CLI is installed on PATH and you're logged in (or set CODEX_API_KEY).
    stderr: #{String.trim(to_string(stderr || ""))}
    """)
  end

  defp format_exit_status(nil), do: ""
  defp format_exit_status(status), do: " (exit #{inspect(status)})"
end

LiveRateLimits.main(System.argv())

Mix.Task.run("app.start")

alias Codex.{Error, Events, Items, Options, RunResultStreaming, Thread, TransportError}

defmodule LiveWebSearchModes do
  @moduledoc false

  @default_prompt "Find the latest Elixir release and cite the source. Use web search if needed."
  @modes [:disabled, :cached, :live]

  def main(args) do
    {modes, prompt} = parse_args(args)
    codex_path = fetch_codex_path!()

    Enum.each(modes, fn mode ->
      run_mode(mode, prompt, codex_path)
    end)
  end

  defp run_mode(mode, prompt, codex_path) do
    IO.puts("\n--- web_search_mode=#{mode} ---")

    if mode == :disabled do
      IO.puts("Disabled mode is passed explicitly (web_search=\"disabled\").")
    end

    {:ok, codex_opts} = Options.new(%{codex_path_override: codex_path})
    {:ok, thread_opts} = Codex.Thread.Options.new(%{web_search_mode: mode})
    {:ok, thread} = Codex.start_thread(codex_opts, thread_opts)

    case Thread.run_streamed(thread, prompt) do
      {:ok, result} ->
        try do
          final_state =
            result
            |> RunResultStreaming.raw_events()
            |> Enum.reduce(%{web_search?: false, final_response: nil}, &handle_event/2)

          if final_state.web_search? do
            IO.puts("Observed web search events.")
          else
            IO.puts("No web search events observed.")
          end

          IO.puts("Final response: #{final_state.final_response || "<none>"}")
        rescue
          error in [Error, TransportError] ->
            render_transport_error(error)
        end

      {:error, reason} ->
        IO.puts("Failed to start streamed turn: #{inspect(reason)}")
    end
  end

  defp handle_event(%Events.ItemStarted{item: %Items.WebSearch{query: query}}, state) do
    IO.puts("Web search started: #{query}")
    %{state | web_search?: true}
  end

  defp handle_event(%Events.ItemCompleted{item: %Items.WebSearch{query: query}}, state) do
    IO.puts("Web search completed: #{query}")
    %{state | web_search?: true}
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

  defp parse_args([mode | rest]) when mode in ["disabled", "cached", "live"] do
    {[String.to_atom(mode)], parse_prompt(rest)}
  end

  defp parse_args(args), do: {@modes, parse_prompt(args)}

  defp parse_prompt([prompt | _]), do: prompt
  defp parse_prompt(_args), do: @default_prompt

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

LiveWebSearchModes.main(System.argv())

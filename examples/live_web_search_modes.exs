Mix.Task.run("app.start")

alias Codex.{Error, Events, Items, Options, RunResultStreaming, Thread, TransportError}

defmodule LiveWebSearchModes do
  @moduledoc false

  @default_prompt """
  Use web search to determine the latest stable Elixir release.
  Include at least one source URL in the answer.
  """
  @modes [:disabled, :cached, :live]
  @retry_prompt_suffix """
  You must use web search for this answer.
  """

  def main(args) do
    {modes, prompt} = parse_args(args)
    codex_path = fetch_codex_path!()
    failures = Enum.flat_map(modes, &run_mode(&1, prompt, codex_path))

    if failures != [] do
      IO.puts("\nWeb search mode validation failures:")
      Enum.each(failures, fn failure -> IO.puts("  - #{inspect(failure)}") end)
      System.halt(1)
    end
  end

  defp run_mode(mode, prompt, codex_path) do
    IO.puts("\n--- web_search_mode=#{mode} ---")

    if mode == :disabled do
      IO.puts("Disabled mode is passed explicitly (web_search=\"disabled\").")
    end

    case run_mode_once(mode, prompt, codex_path) do
      {:ok, final_state} ->
        report_final_state(final_state)
        []

      {:retry_required, reason} ->
        retry_prompt = String.trim("#{prompt}\n\n#{@retry_prompt_suffix}")
        IO.puts("Retrying with stricter prompt due to missing web search events.")
        IO.puts("Retry reason: #{inspect(reason)}")

        case run_mode_once(mode, retry_prompt, codex_path) do
          {:ok, final_state} ->
            report_final_state(final_state)
            []

          {:retry_required, retry_reason} ->
            [{mode, retry_reason}]

          {:error, retry_error} ->
            [{mode, retry_error}]
        end

      {:error, reason} ->
        [{mode, reason}]
    end
  end

  defp run_mode_once(mode, prompt, codex_path) do
    with {:ok, codex_opts} <- Options.new(%{codex_path_override: codex_path}),
         {:ok, thread_opts} <- Codex.Thread.Options.new(%{web_search_mode: mode}),
         {:ok, thread} <- Codex.start_thread(codex_opts, thread_opts),
         {:ok, result} <- Thread.run_streamed(thread, prompt),
         {:ok, final_state} <- consume_result(result) do
      validate_mode_expectation(mode, final_state)
    else
      {:error, reason} ->
        IO.puts("Failed to start streamed turn: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp consume_result(result) do
    try do
      final_state =
        result
        |> RunResultStreaming.raw_events()
        |> Enum.reduce(%{web_search?: false, final_response: nil}, &handle_event/2)

      {:ok, final_state}
    rescue
      error in [Error, TransportError] ->
        render_transport_error(error)
        {:error, error}
    end
  end

  defp validate_mode_expectation(mode, final_state) do
    expected_web_search? = mode in [:cached, :live]

    cond do
      expected_web_search? and final_state.web_search? ->
        {:ok, final_state}

      expected_web_search? and not final_state.web_search? ->
        {:retry_required, {:expected_web_search_events, :none_observed}}

      not expected_web_search? and final_state.web_search? ->
        {:error, {:unexpected_web_search_events, :observed_in_disabled_mode}}

      true ->
        {:ok, final_state}
    end
  end

  defp report_final_state(final_state) do
    if final_state.web_search? do
      IO.puts("Observed web search events.")
    else
      IO.puts("No web search events observed.")
    end

    IO.puts("Final response (illustrative only): #{final_state.final_response || "<none>"}")
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

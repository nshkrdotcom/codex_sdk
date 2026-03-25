Mix.Task.run("app.start")

defmodule CodexExamples.LiveExecControls do
  @moduledoc """
  Demonstrates live codex execution with per-turn env injection, cancellation tokens,
  and custom timeouts. Auth will use CODEX_API_KEY (or auth.json OPENAI_API_KEY) when set,
  otherwise your Codex CLI login.
  """

  @default_prompt "List three repo files, then print the value of CODEX_DEMO_ENV via a safe shell command."
  @default_env %{"CODEX_DEMO_ENV" => "from_readme"}
  @default_timeout_ms 45_000

  def main(argv) do
    {opts, args, _invalid} =
      OptionParser.parse(argv,
        switches: [env: :keep, timeout_ms: :integer, cancel: :string, no_cancel: :boolean],
        aliases: [e: :env, t: :timeout_ms, c: :cancel]
      )

    prompt =
      case args do
        [] -> @default_prompt
        values -> Enum.join(values, " ")
      end

    env_map = build_env(opts)

    cancellation_token =
      if opts[:no_cancel],
        do: nil,
        else: opts[:cancel]

    timeout_ms = opts[:timeout_ms] || @default_timeout_ms

    {:ok, codex_opts} =
      Codex.Options.new(%{
        codex_path_override: fetch_codex_path!()
      })

    {:ok, thread_opts} =
      Codex.Thread.Options.new(%{
        labels: %{example: "live-exec-controls"},
        metadata: %{origin: "mix run example"}
      })

    IO.puts("""
    Running against live codex exec.
    Prompt: #{prompt}
    Env overrides: #{inspect(env_map)}
    Cancellation token: #{cancellation_token || "disabled (--no-cancel)"}
    Timeout (ms): #{timeout_ms}
    """)

    {:ok, thread} = Codex.start_thread(codex_opts, thread_opts)

    turn_opts =
      %{
        env: env_map,
        timeout_ms: timeout_ms
      }
      |> maybe_put(:cancellation_token, cancellation_token)

    case Codex.Thread.run_streamed(thread, prompt, turn_opts) do
      {:ok, result} ->
        try do
          result
          |> Codex.RunResultStreaming.raw_events()
          |> Enum.each(&print_event/1)
        rescue
          error in [Codex.Error, Codex.TransportError] ->
            render_exec_error(error)
            reraise error, __STACKTRACE__
        end

      {:error, reason} ->
        Mix.raise("Exec failed to start: #{inspect(reason)}")
    end
  end

  defp print_event(%Codex.Events.ThreadStarted{thread_id: id}) do
    IO.puts("[thread.started] thread_id=#{id}")
  end

  defp print_event(%Codex.Events.ItemCompleted{item: %Codex.Items.AgentMessage{text: text}}) do
    IO.puts("\n[agent_message]\n#{text}\n")
  end

  defp print_event(%Codex.Events.ItemCompleted{item: %Codex.Items.CommandExecution{} = cmd}) do
    IO.puts(
      "[command_execution] #{cmd.command} status=#{cmd.status} exit=#{inspect(cmd.exit_code)}"
    )

    if cmd.aggregated_output != "", do: IO.puts(cmd.aggregated_output)
  end

  defp print_event(%Codex.Events.TurnCompleted{usage: usage, status: status}) do
    status = status || "completed"
    IO.puts("[turn.completed] status=#{inspect(status)} usage=#{inspect(usage)}")
  end

  defp print_event(%Codex.Events.ThreadTokenUsageUpdated{usage: usage, delta: delta}) do
    IO.puts("[usage.update] usage=#{inspect(usage)} delta=#{inspect(delta)}")
  end

  defp print_event(_other), do: :ok

  defp build_env(opts) do
    opts
    |> Keyword.get_values(:env)
    |> Enum.reduce(%{}, fn raw, acc ->
      case String.split(raw, "=", parts: 2) do
        [key, value] when key != "" -> Map.put(acc, key, value)
        _ -> acc
      end
    end)
    |> case do
      %{} = env when map_size(env) > 0 -> env
      _ -> @default_env
    end
  end

  defp fetch_codex_path! do
    System.get_env("CODEX_PATH") ||
      System.find_executable("codex") ||
      Mix.raise("""
      Unable to locate the `codex` CLI.
      Install the Codex CLI and ensure it is on your PATH or set CODEX_PATH.
      """)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp format_stderr(nil), do: ""

  defp format_stderr(stderr) do
    trimmed = String.trim(stderr || "")

    if trimmed == "" do
      ""
    else
      "stderr:\n" <> trimmed
    end
  end

  defp render_exec_error(%Codex.Error{} = error) do
    status = error.details[:exit_status]
    stderr = error.details[:stderr]

    IO.puts("""
    codex exec failed#{format_exit_status(status)}.
    #{error.message}
    #{format_stderr(stderr)}

    If your Codex CLI is older and does not support --cancellation-token,
    rerun with --no-cancel or upgrade via `npm install -g @openai/codex`.
    """)
  end

  defp render_exec_error(%Codex.TransportError{} = error) do
    IO.puts("""
    codex exec exited with status #{error.exit_status}
    #{format_stderr(error.stderr)}

    If your Codex CLI is older and does not support --cancellation-token,
    rerun with --no-cancel or upgrade via `npm install -g @openai/codex`.
    """)
  end

  defp format_exit_status(nil), do: ""
  defp format_exit_status(status), do: " (status #{status})"
end

CodexExamples.LiveExecControls.main(System.argv())

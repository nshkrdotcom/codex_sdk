alias Codex.{Models, Options, RunResultStreaming, Thread, TransportError}

defmodule LiveTelemetryStream do
  @moduledoc false

  @compaction_events [
    [:codex, :turn, :compaction, :started],
    [:codex, :turn, :compaction, :completed],
    [:codex, :turn, :compaction, :failed],
    [:codex, :turn, :compaction, :unknown]
  ]

  @events [
            [:codex, :thread, :start],
            [:codex, :thread, :stop],
            [:codex, :thread, :exception],
            [:codex, :thread, :token_usage, :updated],
            [:codex, :turn, :diff, :updated]
          ] ++ @compaction_events

  def main(args) do
    prompt = parse_prompt(args)
    handler_id = "codex-live-telemetry-#{System.unique_integer([:positive])}"

    model = Models.default_model()
    reasoning = :low

    IO.puts("""
    Streaming live Codex telemetry (thread/diff/usage/compaction).
    Auth will use CODEX_API_KEY if set, otherwise your Codex CLI login.
    Using model=#{model} reasoning_effort=#{reasoning}.
    Starting live stream; you should see a thread start notice shortly.
    Some telemetry (usage/diff/compaction) may only appear at completion, and
    tool-heavy prompts can take 30-60s.
    """)

    attach(handler_id)

    try do
      run(prompt, model, reasoning)
    after
      detach(handler_id)
    end
  end

  defp run(prompt, model, reasoning) do
    codex_opts =
      Options.new(%{
        model: model,
        reasoning_effort: reasoning,
        codex_path_override: fetch_codex_path!()
      })
      |> unwrap!("codex options")

    thread_opts =
      Thread.Options.new(%{})
      |> unwrap!("thread options")

    {:ok, thread} = Codex.start_thread(codex_opts, thread_opts)

    case Thread.run_streamed(thread, prompt) do
      {:ok, result} ->
        try do
          final =
            result
            |> RunResultStreaming.raw_events()
            |> Enum.reduce(%{final_response: nil}, fn
              %Codex.Events.ItemCompleted{item: %Codex.Items.AgentMessage{text: text}}, acc ->
                IO.puts("\n[agent message]\n#{text}\n")
                Map.put(acc, :final_response, text)

              %Codex.Events.TurnCompleted{final_response: %Codex.Items.AgentMessage{text: text}},
              acc ->
                Map.put(acc, :final_response, text)

              %Codex.Events.TurnCompleted{final_response: nil}, acc ->
                acc

              %Codex.Events.TurnCompleted{final_response: other}, acc ->
                Map.put(acc, :final_response, inspect(other))

              _event, acc ->
                acc
            end)

          IO.puts("\nFinal response:\n#{final.final_response || "<none>"}\n")
        rescue
          error in [TransportError] ->
            render_transport_error(error)
        end

      {:error, reason} ->
        IO.puts("Failed to run streamed turn: #{inspect(reason)}")
    end
  end

  def handle_event([:codex, :thread, :start], _measurements, metadata, _config) do
    IO.puts(
      "thread start thread_id=#{value(metadata, :thread_id)} turn_id=#{value(metadata, :turn_id)} source=#{inspect(Map.get(metadata, :source))}"
    )
  end

  def handle_event([:codex, :thread, :stop], measurements, metadata, _config) do
    IO.puts(
      "thread stop thread_id=#{value(metadata, :thread_id)} turn_id=#{value(metadata, :turn_id)} result=#{Map.get(metadata, :result, :ok)} duration_ms=#{Map.get(measurements, :duration_ms)} source=#{inspect(Map.get(metadata, :source))}"
    )
  end

  def handle_event([:codex, :thread, :exception], measurements, metadata, _config) do
    IO.puts(
      "thread exception thread_id=#{value(metadata, :thread_id)} turn_id=#{value(metadata, :turn_id)} duration_ms=#{Map.get(measurements, :duration_ms)} reason=#{inspect(Map.get(metadata, :reason))}"
    )
  end

  def handle_event([:codex, :thread, :token_usage, :updated], _measurements, metadata, _config) do
    IO.puts(
      "usage update thread_id=#{value(metadata, :thread_id)} turn_id=#{value(metadata, :turn_id)} usage=#{inspect(Map.get(metadata, :usage))} delta=#{inspect(Map.get(metadata, :delta))}"
    )
  end

  def handle_event([:codex, :turn, :diff, :updated], _measurements, metadata, _config) do
    IO.puts(
      "diff update thread_id=#{value(metadata, :thread_id)} turn_id=#{value(metadata, :turn_id)} diff=#{inspect(Map.get(metadata, :diff))}"
    )
  end

  def handle_event([:codex, :turn, :compaction, stage], measurements, metadata, _config) do
    IO.puts(
      "compaction #{stage} thread_id=#{value(metadata, :thread_id)} turn_id=#{value(metadata, :turn_id)} token_savings=#{Map.get(measurements, :token_savings) || "-"} compaction=#{inspect(Map.get(metadata, :compaction))}"
    )
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  defp parse_prompt([prompt | _]), do: prompt

  defp parse_prompt(_args), do: "Summarize telemetry signals."

  defp attach(handler_id) do
    :telemetry.attach_many(handler_id, @events, &__MODULE__.handle_event/4, %{})
  end

  defp detach(handler_id) do
    :telemetry.detach(handler_id)
  end

  defp fetch_codex_path! do
    System.get_env("CODEX_PATH") ||
      System.find_executable("codex") ||
      Mix.raise("""
      Unable to locate the `codex` CLI.
      Install the Codex CLI and ensure it is on your PATH or set CODEX_PATH.
      """)
  end

  defp render_transport_error(%TransportError{exit_status: status, stderr: stderr}) do
    IO.puts("""
    Failed to run codex (exit #{inspect(status)}).
    Ensure the codex CLI is installed on PATH and you're logged in (or set CODEX_API_KEY).
    stderr: #{String.trim(to_string(stderr || ""))}
    """)
  end

  defp unwrap!({:ok, value}, _label), do: value

  defp unwrap!({:error, reason}, label),
    do: Mix.raise("Failed to build #{label}: #{inspect(reason)}")

  defp value(metadata, key) do
    case Map.fetch(metadata, key) do
      {:ok, nil} -> "-"
      {:ok, value} -> value
      :error -> "-"
    end
  end
end

LiveTelemetryStream.main(System.argv())

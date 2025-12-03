# Covers ADR-008, ADR-009, ADR-010 (model settings, streaming cancel, tracing/usage)
Mix.Task.run("app.start")

alias Codex.{Agent, AgentRunner, ModelSettings, RunConfig}
alias Codex.Items.AgentMessage
alias Codex.StreamEvent
alias Codex.RunResultStreaming
alias Codex.Events

defmodule CodexExamples.LiveModelStreamingTracing do
  @moduledoc false

  def main(argv) do
    {opts, args, _} =
      OptionParser.parse(argv,
        switches: [cancel: :string, model: :string]
      )

    cancel_mode = parse_cancel(opts[:cancel])
    prompt = parse_prompt(args)

    {:ok, settings} =
      ModelSettings.new(%{
        temperature: 0.3,
        provider: :responses,
        max_tokens: 300,
        metadata: %{example: "streaming"},
        extra_headers: %{"x-trace-demo" => "true"}
      })

    {:ok, run_config} =
      RunConfig.new(%{
        model: opts[:model],
        model_settings: settings,
        workflow: "live-streaming",
        group: "examples",
        trace_id: "trace-#{System.unique_integer([:positive])}",
        trace_include_sensitive_data: false
      })

    {:ok, agent} =
      Agent.new(%{
        name: "StreamingTracer",
        instructions: "Stream a brief answer and mention the workflow id if present."
      })

    {:ok, codex_opts} =
      Codex.Options.new(%{
        codex_path_override: fetch_codex_path!()
      })

    {:ok, thread} = Codex.start_thread(codex_opts)

    IO.puts("""
    Streaming with model #{run_config.model || "<default>"} (provider=#{settings.provider})
      Cancel mode: #{cancel_mode || "none"}
      Trace: workflow=#{run_config.workflow} group=#{run_config.group} trace_id=#{run_config.trace_id}
    """)

    case AgentRunner.run_streamed(thread, prompt, %{agent: agent, run_config: run_config}) do
      {:ok, stream} ->
        final = consume_stream(stream, cancel_mode)
        IO.puts("Usage: #{inspect(RunResultStreaming.usage(stream))}")
        IO.puts("Final response: #{final || "<none>"}")

      {:error, reason} ->
        IO.puts("Streaming run failed: #{inspect(reason)}")
    end
  end

  defp consume_stream(stream, cancel_mode) do
    stream
    |> RunResultStreaming.events()
    |> Enum.reduce(%{final: nil, cancelled?: false}, fn
      %StreamEvent.AgentUpdated{run_config: rc}, acc ->
        IO.puts("Agent updated (model_settings=#{inspect(rc.model_settings)})")
        acc

      %StreamEvent.RunItem{event: %Events.ThreadTokenUsageUpdated{usage: usage, delta: delta}},
      acc ->
        IO.puts("Usage update: #{inspect(usage)} delta=#{inspect(delta)}")
        acc

      %StreamEvent.RunItem{
        event: %Events.ItemCompleted{item: %AgentMessage{text: text}}
      },
      %{cancelled?: false} = acc
      when cancel_mode in [:immediate, :after_turn] ->
        RunResultStreaming.cancel(stream, cancel_mode)
        IO.puts("Cancelling stream (mode=#{cancel_mode}) after first agent message")
        %{acc | final: text, cancelled?: true}

      %StreamEvent.RunItem{event: %Events.ItemCompleted{item: %AgentMessage{text: text}}}, acc ->
        IO.puts("Agent message chunk: #{String.slice(text || "", 0, 120)}")
        %{acc | final: text || acc.final}

      %StreamEvent.RunItem{
        event: %Events.TurnCompleted{final_response: %AgentMessage{text: text}, usage: usage}
      },
      acc ->
        IO.puts("Turn completed with usage #{inspect(usage)}")
        %{acc | final: text || acc.final}

      %StreamEvent.RunItem{
        event: %Events.TurnCompleted{final_response: %{"text" => text}, usage: usage}
      },
      acc ->
        IO.puts("Turn completed with usage #{inspect(usage)}")
        %{acc | final: text || acc.final}

      _other, acc ->
        acc
    end)
    |> Map.get(:final)
  end

  defp parse_cancel("immediate"), do: :immediate
  defp parse_cancel("after_turn"), do: :after_turn
  defp parse_cancel(_), do: nil

  defp parse_prompt([]),
    do:
      "Stream a two-sentence update on tracing and usage compaction. Mention that we may cancel mid-stream."

  defp parse_prompt(values), do: Enum.join(values, " ")

  defp fetch_codex_path! do
    System.get_env("CODEX_PATH") ||
      System.find_executable("codex") ||
      Mix.raise("""
      Unable to locate the `codex` CLI.
      Install the Codex CLI and ensure it is on your PATH or set CODEX_PATH.
      """)
  end
end

CodexExamples.LiveModelStreamingTracing.main(System.argv())

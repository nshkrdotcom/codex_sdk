alias Codex.{Events, Items, Models, Options, RunResultStreaming, Thread}
alias Codex.TransportError

defmodule LiveUsageAndCompaction do
  @moduledoc false

  def main(args) do
    prompt = parse_prompt(args)

    model = Models.default_model()
    reasoning = Models.default_reasoning_effort(model)
    tools? = Models.tool_enabled?(model)

    IO.puts("""
    Running against the live Codex CLI. Auth will use CODEX_API_KEY if set, otherwise your CLI login.
    Using model=#{model} reasoning_effort=#{reasoning || "none"} tools_enabled=#{tools?}
    """)

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
          final_state =
            result
            |> RunResultStreaming.raw_events()
            |> Enum.reduce(initial_state(), &handle_event/2)

          IO.puts("\nFinal response:\n#{final_state.final_response || "<none>"}")
          IO.inspect(final_state.usage, label: "Merged usage (includes deltas and compaction)")
        rescue
          error in [TransportError] ->
            render_transport_error(error)
        end

      {:error, reason} ->
        IO.puts("Failed to start streamed turn: #{inspect(reason)}")
    end
  end

  defp render_transport_error(%TransportError{exit_status: status, stderr: stderr}) do
    IO.puts("""
    Failed to run codex (exit #{inspect(status)}).
    Ensure the codex CLI is installed on PATH and you're logged in (or set CODEX_API_KEY).
    stderr: #{String.trim(to_string(stderr || ""))}
    """)
  end

  defp parse_prompt([prompt | _]), do: prompt

  defp parse_prompt(_args) do
    """
    Give me a concise plan for hardening this repository: mention tests, telemetry, and how to keep prompts compact.
    """
  end

  defp initial_state do
    %{
      usage: %{},
      compactions: [],
      diffs: [],
      final_response: nil
    }
  end

  defp handle_event(%Events.ThreadTokenUsageUpdated{} = event, state) do
    usage = merge_usage(state.usage, event.usage, event.delta)
    IO.puts("Usage update (#{context(event.thread_id, event.turn_id)}): #{inspect(usage)}")
    %{state | usage: usage}
  end

  defp handle_event(%Events.TurnCompaction{} = event, state) do
    usage =
      merge_usage(
        state.usage,
        compaction_usage(event.compaction),
        compaction_delta(event.compaction)
      )

    IO.puts(
      "Compaction #{event.stage} (#{context(event.thread_id, event.turn_id)}): #{inspect(event.compaction)}"
    )

    %{state | usage: usage, compactions: [event | state.compactions]}
  end

  defp handle_event(%Events.TurnDiffUpdated{diff: diff} = event, state) do
    IO.puts("Turn diff (#{context(event.thread_id, event.turn_id)}): #{inspect(diff)}")
    %{state | diffs: [diff | state.diffs]}
  end

  defp handle_event(%Events.ItemCompleted{item: %Items.AgentMessage{text: text}}, state) do
    IO.puts("\nAgent message:\n#{text}\n")
    state
  end

  defp handle_event(
         %Events.TurnCompleted{final_response: %Items.AgentMessage{text: text}, usage: usage} =
           event,
         state
       ) do
    merged_usage = merge_usage(state.usage, usage, nil)

    IO.puts(
      "Turn completed (#{context(event.thread_id, event.turn_id)}), usage=#{inspect(merged_usage)}"
    )

    %{state | final_response: text, usage: merged_usage}
  end

  defp handle_event(%Events.TurnCompleted{final_response: other, usage: usage} = event, state) do
    merged_usage = merge_usage(state.usage, usage, nil)

    IO.puts(
      "Turn completed (#{context(event.thread_id, event.turn_id)}), usage=#{inspect(merged_usage)}"
    )

    %{state | final_response: inspect(other), usage: merged_usage}
  end

  defp handle_event(_other, state), do: state

  defp merge_usage(current_usage, usage_map, delta_map) do
    usage_map = if is_map(usage_map), do: usage_map, else: nil
    delta_map = if is_map(delta_map), do: delta_map, else: nil

    base =
      case usage_map do
        nil -> current_usage || %{}
        map when map_size(map) == 0 -> current_usage || %{}
        map -> Map.merge(current_usage || %{}, map, fn _k, _l, r -> r end)
      end

    case delta_map do
      nil ->
        base

      delta ->
        Enum.reduce(delta, base, fn {key, value}, acc ->
          if usage_map && Map.has_key?(usage_map, key) do
            acc
          else
            previous = Map.get(current_usage || %{}, key)
            Map.put(acc, key, add_usage(previous, value))
          end
        end)
    end
  end

  defp add_usage(nil, value), do: value
  defp add_usage(value, nil), do: value

  defp add_usage(left, right) when is_number(left) and is_number(right), do: left + right
  defp add_usage(_left, right), do: right

  defp compaction_usage(compaction) do
    Map.get(compaction, "usage") ||
      Map.get(compaction, :usage) ||
      Map.get(compaction, "token_usage") ||
      Map.get(compaction, :token_usage)
  end

  defp compaction_delta(compaction) do
    Map.get(compaction, "usage_delta") ||
      Map.get(compaction, :usage_delta) ||
      Map.get(compaction, "usageDelta") ||
      Map.get(compaction, :usageDelta)
  end

  defp context(thread_id, turn_id) do
    ["thread", thread_id || "?", "turn", turn_id || "?"]
    |> Enum.chunk_every(2)
    |> Enum.map_join(" ", fn [label, id] -> "#{label}=#{id}" end)
  end

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

LiveUsageAndCompaction.main(System.argv())

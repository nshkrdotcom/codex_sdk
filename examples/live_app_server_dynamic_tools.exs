Mix.Task.run("app.start")

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias Codex.Events
alias Codex.Items
alias Codex.RunResultStreaming
alias CodexExamples.Support

Support.init!()

defmodule CodexExamples.LiveAppServerDynamicTools do
  @moduledoc false

  @default_prompt """
  Use the echo_json dynamic tool exactly once with message "codex dynamic tools live check".
  After the tool result is returned, reply with a one-sentence summary of the tool output.
  """

  @dynamic_tools [
    %{
      "name" => "echo_json",
      "description" => "Echoes the JSON arguments supplied by the model back to the turn.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "message" => %{"type" => "string", "description" => "Message to echo."}
        },
        "required" => ["message"],
        "additionalProperties" => false
      }
    }
  ]

  def main(argv) do
    case run(argv) do
      :ok ->
        :ok

      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")
    end
  end

  defp run(argv) do
    prompt =
      case argv do
        [] -> String.trim(@default_prompt)
        values -> Enum.join(values, " ")
      end

    with {:ok, codex_opts} <- Support.codex_options(%{}, missing_cli: :skip),
         :ok <- Support.ensure_auth_available(),
         :ok <- Support.ensure_app_server_supported(codex_opts),
         :ok <- Support.ensure_remote_working_directory(),
         {:ok, conn} <-
           Codex.AppServer.connect(codex_opts,
             experimental_api: true,
             init_timeout_ms: 30_000
           ) do
      try do
        {:ok, thread} =
          Codex.start_thread(
            codex_opts,
            Support.thread_opts!(%{
              transport: {:app_server, conn},
              working_directory: Support.example_working_directory(),
              dynamic_tools: @dynamic_tools
            })
          )

        IO.puts("""
        Dynamic tools over app-server.
          prompt: #{prompt}
          advertised_tools: #{Enum.map_join(@dynamic_tools, ", ", & &1["name"])}
        """)

        case Codex.Thread.run_streamed(thread, prompt, timeout_ms: 120_000) do
          {:ok, stream} ->
            stats =
              stream
              |> RunResultStreaming.raw_events()
              |> Enum.reduce(%{tool_calls: 0, final_message: nil, turn_status: nil}, fn event, acc ->
                handle_event(conn, event, acc)
              end)

            if stats.tool_calls == 0 do
              Mix.raise("dynamic tool live example completed without a DynamicToolCallRequested event")
            end

            IO.puts("""

            Dynamic tool run completed.
              tool_calls: #{stats.tool_calls}
              turn_status: #{inspect(stats.turn_status)}
              final_message: #{stats.final_message || "(none)"}
            """)

            :ok

          {:error, reason} ->
            Mix.raise("Dynamic tool streaming run failed: #{inspect(reason)}")
        end
      after
        :ok = Codex.AppServer.disconnect(conn)
      end
    end
  end

  defp handle_event(conn, %Events.DynamicToolCallRequested{} = event, acc) do
    IO.puts("""

    [dynamic_tool.requested]
      id: #{inspect(event.id)}
      call_id: #{inspect(event.call_id)}
      tool_name: #{event.tool_name}
      arguments: #{inspect(event.arguments)}
    """)

    response = echo_response(event)

    case Codex.AppServer.respond(conn, event.id, response) do
      :ok ->
        %{acc | tool_calls: acc.tool_calls + 1}

      {:error, reason} ->
        Mix.raise("failed to respond to dynamic tool request: #{inspect(reason)}")
    end
  end

  defp handle_event(_conn, %Events.ItemAgentMessageDelta{item: %{"text" => delta}}, acc)
       when is_binary(delta) do
    IO.write(delta)
    acc
  end

  defp handle_event(_conn, %Events.ItemCompleted{item: %Items.AgentMessage{text: text}}, acc)
       when is_binary(text) do
    %{acc | final_message: text}
  end

  defp handle_event(_conn, %Events.TurnCompleted{status: status}, acc) do
    %{acc | turn_status: status}
  end

  defp handle_event(_conn, _event, acc), do: acc

  defp echo_response(%Events.DynamicToolCallRequested{} = event) do
    output =
      Jason.encode!(%{
        "tool" => event.tool_name,
        "callId" => event.call_id,
        "arguments" => event.arguments
      })

    %{
      "success" => true,
      "output" => output,
      "contentItems" => [
        %{
          "type" => "inputText",
          "text" => output
        }
      ]
    }
  end
end

CodexExamples.LiveAppServerDynamicTools.main(System.argv())

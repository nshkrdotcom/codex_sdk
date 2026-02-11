# Covers ADR-006, ADR-007 (MCP hosted tool + session resume)
Mix.Task.run("app.start")

alias Codex.{AgentRunner, Events, RunConfig, Tools}
alias Codex.Agent, as: CodexAgent
alias Codex.Items.AgentMessage

defmodule CodexExamples.StubMcpTransport do
  @moduledoc false

  def start_link do
    Agent.start_link(fn -> %{last: nil, call_attempts: 0} end)
  end

  def send(pid, payload) do
    Agent.update(pid, &Map.put(&1, :last, payload))
    :ok
  end

  def recv(pid) do
    Agent.get_and_update(pid, fn %{last: request} = state ->
      case request["method"] do
        "initialize" ->
          response = %{
            "jsonrpc" => "2.0",
            "id" => request["id"],
            "result" => %{
              "capabilities" => %{"tools" => %{}},
              "protocolVersion" => "2025-06-18",
              "serverInfo" => %{"name" => "stub", "version" => "0.0.1"}
            }
          }

          {{:ok, response}, state}

        "tools/list" ->
          tools = [%{"name" => "stub.echo", "description" => "echoes arguments"}]

          response = %{
            "jsonrpc" => "2.0",
            "id" => request["id"],
            "result" => %{"tools" => tools}
          }

          {{:ok, response}, state}

        "tools/call" ->
          attempt = state.call_attempts + 1
          updated = %{state | call_attempts: attempt}
          params = Map.get(request, "params") || %{}

          response =
            if attempt == 1 do
              %{
                "jsonrpc" => "2.0",
                "id" => request["id"],
                "error" => %{"code" => -32_000, "message" => "transient"}
              }
            else
              args = Map.get(params, "arguments") || %{}

              %{
                "jsonrpc" => "2.0",
                "id" => request["id"],
                "result" => %{"echo" => args}
              }
            end

          {{:ok, response}, updated}

        _ ->
          {{:error, :unknown_request}, state}
      end
    end)
  end
end

defmodule CodexExamples.MemorySession do
  @moduledoc false
  @behaviour Codex.Session

  def start_link, do: Agent.start_link(fn -> [] end)

  @impl true
  def load(pid), do: {:ok, Agent.get(pid, & &1)}

  @impl true
  def save(pid, entry) do
    Agent.update(pid, &[entry | &1])
    :ok
  end

  @impl true
  def clear(pid) do
    Agent.update(pid, fn _ -> [] end)
    :ok
  end
end

defmodule CodexExamples.LiveMcpAndSessions do
  @moduledoc false

  def main(argv) do
    {prompt1, prompt2} = parse_prompts(argv)

    Tools.reset!()

    {:ok, transport} = CodexExamples.StubMcpTransport.start_link()

    {:ok, client} =
      Codex.MCP.Client.handshake({CodexExamples.StubMcpTransport, transport},
        client: "codex-elixir-demo",
        version: "0.1.0",
        server_name: "stub_server"
      )

    # Demonstrate tool discovery with filtering and qualification
    {:ok, tools, client} = Codex.MCP.Client.list_tools(client, allow: ["stub.echo"])
    IO.puts("MCP tools (filtered): #{inspect(Enum.map(tools, & &1["name"]))}")

    # Show qualified tool names (mcp__server__tool format)
    {:ok, qualified_tools, _} = Codex.MCP.Client.list_tools(client, qualify?: true)

    IO.puts(
      "MCP tools (qualified): #{inspect(Enum.map(qualified_tools, & &1["qualified_name"]))}"
    )

    # Demonstrate direct tool invocation with call_tool/4
    IO.puts("\n--- Direct MCP Tool Invocation ---")

    # Invocation with retry and approval callback
    demo_result =
      Codex.MCP.Client.call_tool(client, "stub.echo", %{"message" => "Hello from call_tool!"},
        retries: 2,
        backoff: &mcp_backoff/1,
        approval: fn tool, args, _ctx ->
          IO.puts("Approval check for tool=#{tool} args=#{inspect(args)}")
          :ok
        end,
        context: %{user: "demo_user"}
      )

    case demo_result do
      {:ok, result} -> IO.puts("call_tool success: #{inspect(result)}")
      {:error, reason} -> IO.puts("call_tool error: #{inspect(reason)}")
    end

    IO.puts("---\n")

    {:ok, _} =
      Codex.Tools.HostedMcpTool
      |> Tools.register(
        name: "hosted_mcp",
        client: client,
        tool: "stub.echo",
        retries: 1,
        backoff: &mcp_backoff/1
      )

    {:ok, agent} =
      CodexAgent.new(%{
        name: "McpSessionAgent",
        instructions: "Answer concisely. Use hosted_mcp only if it is available and helpful.",
        tools: ["hosted_mcp"],
        reset_tool_choice: true
      })

    {:ok, session_pid} = CodexExamples.MemorySession.start_link()

    {:ok, codex_opts} =
      Codex.Options.new(%{
        codex_path_override: fetch_codex_path!(),
        model: Codex.Models.default_model()
      })

    {:ok, thread} = Codex.start_thread(codex_opts)

    run_config =
      RunConfig.new(%{
        session: {CodexExamples.MemorySession, session_pid},
        conversation_id: "demo-conversation"
      })
      |> unwrap!("run config")

    {:ok, first} = AgentRunner.run(thread, prompt1, %{agent: agent, run_config: run_config})
    IO.puts("First response: #{render_response(first.final_response)}")
    maybe_demo_tool_invocation(first.events)

    resume_config =
      RunConfig.new(%{
        session: {CodexExamples.MemorySession, session_pid},
        conversation_id: "demo-conversation",
        previous_response_id: "demo-prev-response"
      })
      |> unwrap!("resume config")

    {:ok, second} =
      AgentRunner.run(first.thread, prompt2, %{agent: agent, run_config: resume_config})

    IO.puts("Resumed response: #{render_response(second.final_response)}")
    IO.puts("Session stored entries: #{inspect(Agent.get(session_pid, &Enum.reverse/1))}")
  end

  defp mcp_backoff(attempt) do
    delay = attempt * 100
    Process.sleep(delay)
    IO.puts("Retrying MCP call (attempt #{attempt}) after #{delay}ms")
  end

  defp parse_prompts([]) do
    {
      "Give me a short note about sessions.",
      "Resume the same session and give a one-line reminder."
    }
  end

  defp parse_prompts([first | rest]) do
    {first, Enum.join(rest, " ")}
  end

  defp maybe_demo_tool_invocation(events) do
    tool_events =
      Enum.filter(
        events,
        &(match?(%Events.ToolCallRequested{}, &1) or match?(%Events.ToolCallCompleted{}, &1))
      )

    if tool_events == [] do
      IO.puts("No MCP tool calls observed; invoking hosted_mcp directly.")

      case Tools.invoke("hosted_mcp", %{"note" => "session demo"}, %{}) do
        {:ok, output} -> IO.puts("hosted_mcp output: #{inspect(output)}")
        {:error, reason} -> IO.puts("hosted_mcp error: #{inspect(reason)}")
      end
    end
  end

  defp render_response(%AgentMessage{text: text}), do: text
  defp render_response(%{"text" => text}), do: text
  defp render_response(nil), do: "<no response>"
  defp render_response(other), do: inspect(other)

  defp unwrap!({:ok, value}, _label), do: value

  defp unwrap!({:error, reason}, label),
    do: Mix.raise("Failed to build #{label}: #{inspect(reason)}")

  defp fetch_codex_path! do
    System.get_env("CODEX_PATH") ||
      System.find_executable("codex") ||
      Mix.raise("""
      Unable to locate the `codex` CLI.
      Install the Codex CLI and ensure it is on your PATH or set CODEX_PATH.
      """)
  end
end

CodexExamples.LiveMcpAndSessions.main(System.argv())

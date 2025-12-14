defmodule Codex.MCPClientTest do
  use ExUnit.Case, async: true

  alias Codex.MCP.Client
  alias Codex.Tools

  @sdk_version to_string(Application.spec(:codex_sdk, :vsn))

  defmodule FakeTransport do
    use GenServer

    def start_link(response) do
      GenServer.start_link(__MODULE__, response)
    end

    @impl true
    def init(response) do
      {:ok, %{response: response, sent: []}}
    end

    def send(pid, message) do
      GenServer.cast(pid, {:send, message})
      :ok
    end

    def recv(pid) do
      GenServer.call(pid, :recv)
    end

    def sent(pid) do
      GenServer.call(pid, :sent)
    end

    @impl true
    def handle_cast({:send, message}, state) do
      {:noreply, %{state | sent: [message | state.sent]}}
    end

    @impl true
    def handle_call(:recv, _from, %{response: [next | rest]} = state) do
      {:reply, {:ok, next}, %{state | response: rest}}
    end

    def handle_call(:recv, _from, %{response: []} = state) do
      {:reply, {:error, :closed}, state}
    end

    @impl true
    def handle_call(:sent, _from, state) do
      {:reply, Enum.reverse(state.sent), state}
    end
  end

  test "handshake exchanges capability information" do
    {:ok, transport} =
      FakeTransport.start_link([
        %{"type" => "handshake.ack", "capabilities" => ["tools", "attachments"]}
      ])

    transport_ref = {FakeTransport, transport}

    assert {:ok, client} = Client.handshake(transport_ref, client: "codex", version: @sdk_version)

    assert Client.capabilities(client) == %{"attachments" => %{}, "tools" => %{}}

    assert [sent] = FakeTransport.sent(transport)
    assert sent["type"] == "handshake"
    assert sent["client"] == "codex"
  end

  test "handshake preserves capability metadata including elicitation support" do
    {:ok, transport} =
      FakeTransport.start_link([
        %{
          "type" => "handshake.ack",
          "capabilities" => %{
            "tools" => %{"listChanged" => true},
            "elicitation" => %{"server" => "shell"},
            "mcpServers" => [%{"name" => "shell-mcp", "capabilities" => %{"exec" => true}}]
          }
        }
      ])

    transport_ref = {FakeTransport, transport}

    assert {:ok, client} = Client.handshake(transport_ref, client: "codex", version: @sdk_version)

    assert Client.capabilities(client) == %{
             "tools" => %{"listChanged" => true},
             "elicitation" => %{"server" => "shell"},
             "mcpServers" => [%{"name" => "shell-mcp", "capabilities" => %{"exec" => true}}]
           }
  end

  test "list_tools caches responses and applies filters" do
    {:ok, transport} =
      FakeTransport.start_link([
        %{"type" => "handshake.ack", "capabilities" => %{}},
        %{
          "tools" => [
            %{"name" => "alpha"},
            %{"name" => "beta"}
          ]
        },
        %{
          "tools" => [
            %{"name" => "alpha"},
            %{"name" => "beta"}
          ]
        }
      ])

    transport_ref = {FakeTransport, transport}

    assert {:ok, client} = Client.handshake(transport_ref, client: "codex", version: @sdk_version)

    assert {:ok, tools, cached_client} = Client.list_tools(client)
    assert Enum.map(tools, & &1["name"]) == ["alpha", "beta"]

    assert {:ok, ^tools, cached_again} = Client.list_tools(cached_client)
    assert cached_again.tool_cache.tools == tools

    # Bypass cache and apply allow-list
    assert {:ok, [%{"name" => "beta"}], _} =
             Client.list_tools(cached_client, allow: ["beta"], cache?: false)

    sent = FakeTransport.sent(transport)
    assert Enum.count(sent, &(&1["type"] == "list_tools")) == 2
  end

  test "call_tool retries on failure with backoff" do
    {:ok, transport} =
      FakeTransport.start_link([
        %{"type" => "handshake.ack", "capabilities" => %{}},
        %{"error" => "transient"},
        %{"result" => %{"echo" => "ok"}}
      ])

    transport_ref = {FakeTransport, transport}
    {:ok, client} = Client.handshake(transport_ref, client: "codex", version: @sdk_version)

    backoffs =
      Agent.start_link(fn -> [] end)
      |> elem(1)

    backoff = fn attempt ->
      Agent.update(backoffs, &[attempt | &1])
      :ok
    end

    assert {:ok, %{"echo" => "ok"}} =
             Client.call_tool(client, "echo", %{"text" => "hi"}, retries: 1, backoff: backoff)

    assert Agent.get(backoffs, &Enum.reverse/1) == [1]
    sent = FakeTransport.sent(transport)
    assert Enum.count(sent, &(&1["type"] == "call_tool")) == 2
  end

  test "hosted MCP tool respects approval hook" do
    {:ok, transport} =
      FakeTransport.start_link([
        %{"type" => "handshake.ack", "capabilities" => %{}},
        %{"result" => %{"ok" => true}}
      ])

    transport_ref = {FakeTransport, transport}
    {:ok, client} = Client.handshake(transport_ref, client: "codex", version: @sdk_version)

    {:ok, _} =
      Tools.register(Codex.Tools.HostedMcpTool,
        name: "mcp_echo",
        client: client,
        tool: "echo",
        approval: fn _args, _ctx, _meta -> {:deny, "blocked"} end
      )

    assert {:error, {:approval_denied, "blocked"}} =
             Tools.invoke("mcp_echo", %{"arguments" => %{"text" => "hi"}}, %{})

    {:ok, _} =
      Tools.register(Codex.Tools.HostedMcpTool,
        name: "mcp_allow",
        client: client,
        tool: "echo"
      )

    assert {:ok, %{"ok" => true}} =
             Tools.invoke("mcp_allow", %{"arguments" => %{"text" => "hi"}}, %{})
  end
end

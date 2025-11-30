defmodule Codex.MCPClientTest do
  use ExUnit.Case, async: true

  alias Codex.MCP.Client

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

    assert {:ok, client} = Client.handshake(transport_ref, client: "codex", version: "0.2.1")

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

    assert {:ok, client} = Client.handshake(transport_ref, client: "codex", version: "0.2.1")

    assert Client.capabilities(client) == %{
             "tools" => %{"listChanged" => true},
             "elicitation" => %{"server" => "shell"},
             "mcpServers" => [%{"name" => "shell-mcp", "capabilities" => %{"exec" => true}}]
           }
  end
end

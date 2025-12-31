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

  describe "call_tool/4" do
    test "invokes tool and returns result" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}},
          %{"result" => %{"data" => "hello"}}
        ])

      transport_ref = {FakeTransport, transport}
      {:ok, client} = Client.handshake(transport_ref, client: "codex", version: @sdk_version)

      assert {:ok, %{"data" => "hello"}} =
               Client.call_tool(client, "echo", %{"text" => "hello"}, retries: 0)
    end

    test "retries on transient failure with default backoff" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}},
          %{"error" => "transient"},
          %{"error" => "transient"},
          %{"result" => %{"ok" => true}}
        ])

      transport_ref = {FakeTransport, transport}
      {:ok, client} = Client.handshake(transport_ref, client: "codex", version: @sdk_version)

      # Use a no-op backoff to avoid test delays
      backoff = fn _attempt -> :ok end

      assert {:ok, %{"ok" => true}} =
               Client.call_tool(client, "test_tool", %{}, retries: 2, backoff: backoff)

      sent = FakeTransport.sent(transport)
      assert Enum.count(sent, &(&1["type"] == "call_tool")) == 3
    end

    test "applies exponential backoff" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}},
          %{"error" => "fail1"},
          %{"error" => "fail2"},
          %{"result" => %{"ok" => true}}
        ])

      transport_ref = {FakeTransport, transport}
      {:ok, client} = Client.handshake(transport_ref, client: "codex", version: @sdk_version)

      {:ok, timings} = Agent.start_link(fn -> [] end)

      backoff = fn attempt ->
        Agent.update(timings, &[{attempt, System.monotonic_time()} | &1])
        # Skip actual sleep for test speed
        :ok
      end

      assert {:ok, %{"ok" => true}} =
               Client.call_tool(client, "test_tool", %{}, retries: 2, backoff: backoff)

      recorded = Agent.get(timings, &Enum.reverse/1)
      assert length(recorded) == 2
      assert [{1, _}, {2, _}] = recorded
    end

    test "respects approval callback - allows" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}},
          %{"result" => %{"ok" => true}}
        ])

      transport_ref = {FakeTransport, transport}
      {:ok, client} = Client.handshake(transport_ref, client: "codex", version: @sdk_version)

      approval = fn _tool, _args, _ctx -> :ok end

      assert {:ok, %{"ok" => true}} =
               Client.call_tool(client, "test_tool", %{}, approval: approval, retries: 0)
    end

    test "respects approval callback - denies" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}},
          %{"result" => %{"ok" => true}}
        ])

      transport_ref = {FakeTransport, transport}
      {:ok, client} = Client.handshake(transport_ref, client: "codex", version: @sdk_version)

      approval = fn _tool, _args, _ctx -> {:deny, "blocked"} end

      assert {:error, {:approval_denied, "blocked"}} =
               Client.call_tool(client, "test_tool", %{}, approval: approval, retries: 0)

      # Should not have sent any call_tool request
      sent = FakeTransport.sent(transport)
      refute Enum.any?(sent, &(&1["type"] == "call_tool"))
    end

    test "respects approval callback - denies with false" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}}
        ])

      transport_ref = {FakeTransport, transport}
      {:ok, client} = Client.handshake(transport_ref, client: "codex", version: @sdk_version)

      approval = fn _tool -> false end

      assert {:error, {:approval_denied, :denied}} =
               Client.call_tool(client, "test_tool", %{}, approval: approval, retries: 0)
    end

    test "emits telemetry events on success" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}},
          %{"result" => %{"data" => "test"}}
        ])

      transport_ref = {FakeTransport, transport}

      {:ok, client} =
        Client.handshake(transport_ref,
          client: "codex",
          version: @sdk_version,
          server_name: "test_server"
        )

      test_pid = self()

      :telemetry.attach_many(
        "test-mcp-tool-call-success",
        [
          [:codex, :mcp, :tool_call, :start],
          [:codex, :mcp, :tool_call, :success]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      assert {:ok, %{"data" => "test"}} =
               Client.call_tool(client, "my_tool", %{"arg" => "val"}, retries: 0)

      # Verify start event
      assert_receive {:telemetry, [:codex, :mcp, :tool_call, :start], start_measurements,
                      start_metadata}

      assert is_integer(start_measurements.system_time)
      assert start_metadata.tool == "my_tool"
      assert start_metadata.arguments == %{"arg" => "val"}
      assert start_metadata.server_name == "test_server"

      # Verify success event
      assert_receive {:telemetry, [:codex, :mcp, :tool_call, :success], success_measurements,
                      success_metadata}

      assert is_integer(success_measurements.duration)
      assert success_metadata.tool == "my_tool"
      assert success_metadata.server_name == "test_server"
      assert success_metadata.attempt == 1

      :telemetry.detach("test-mcp-tool-call-success")
    end

    test "emits telemetry events on failure" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}},
          %{"error" => "fatal_error"}
        ])

      transport_ref = {FakeTransport, transport}

      {:ok, client} =
        Client.handshake(transport_ref,
          client: "codex",
          version: @sdk_version,
          server_name: "fail_server"
        )

      test_pid = self()

      :telemetry.attach_many(
        "test-mcp-tool-call-failure",
        [
          [:codex, :mcp, :tool_call, :start],
          [:codex, :mcp, :tool_call, :failure]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      assert {:error, "fatal_error"} =
               Client.call_tool(client, "fail_tool", %{}, retries: 0)

      # Verify start event
      assert_receive {:telemetry, [:codex, :mcp, :tool_call, :start], _, _}

      # Verify failure event
      assert_receive {:telemetry, [:codex, :mcp, :tool_call, :failure], failure_measurements,
                      failure_metadata}

      assert is_integer(failure_measurements.duration)
      assert failure_metadata.tool == "fail_tool"
      assert failure_metadata.server_name == "fail_server"
      assert failure_metadata.reason == "fatal_error"
      assert failure_metadata.attempt == 1

      :telemetry.detach("test-mcp-tool-call-failure")
    end

    test "uses default retries of 3" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}},
          %{"error" => "fail1"},
          %{"error" => "fail2"},
          %{"error" => "fail3"},
          %{"result" => %{"ok" => true}}
        ])

      transport_ref = {FakeTransport, transport}
      {:ok, client} = Client.handshake(transport_ref, client: "codex", version: @sdk_version)

      # Use a no-op backoff to avoid test delays
      backoff = fn _attempt -> :ok end

      # Default retries is 3, so after initial attempt + 3 retries = 4 total attempts
      assert {:ok, %{"ok" => true}} = Client.call_tool(client, "test_tool", %{}, backoff: backoff)

      sent = FakeTransport.sent(transport)
      assert Enum.count(sent, &(&1["type"] == "call_tool")) == 4
    end

    test "fails after exhausting retries" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}},
          %{"error" => "fail1"},
          %{"error" => "fail2"},
          %{"error" => "final_fail"}
        ])

      transport_ref = {FakeTransport, transport}
      {:ok, client} = Client.handshake(transport_ref, client: "codex", version: @sdk_version)

      backoff = fn _attempt -> :ok end

      assert {:error, "final_fail"} =
               Client.call_tool(client, "test_tool", %{}, retries: 2, backoff: backoff)

      sent = FakeTransport.sent(transport)
      assert Enum.count(sent, &(&1["type"] == "call_tool")) == 3
    end

    test "supports 2-arity approval callbacks" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}},
          %{"result" => %{"ok" => true}}
        ])

      transport_ref = {FakeTransport, transport}
      {:ok, client} = Client.handshake(transport_ref, client: "codex", version: @sdk_version)

      approval = fn tool, args ->
        assert tool == "test_tool"
        assert args == %{"key" => "value"}
        :ok
      end

      assert {:ok, %{"ok" => true}} =
               Client.call_tool(client, "test_tool", %{"key" => "value"},
                 approval: approval,
                 retries: 0
               )
    end

    test "supports 1-arity approval callbacks" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}},
          %{"result" => %{"ok" => true}}
        ])

      transport_ref = {FakeTransport, transport}
      {:ok, client} = Client.handshake(transport_ref, client: "codex", version: @sdk_version)

      approval = fn tool ->
        assert tool == "test_tool"
        :ok
      end

      assert {:ok, %{"ok" => true}} =
               Client.call_tool(client, "test_tool", %{}, approval: approval, retries: 0)
    end

    test "passes context to approval callback" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}},
          %{"result" => %{"ok" => true}}
        ])

      transport_ref = {FakeTransport, transport}
      {:ok, client} = Client.handshake(transport_ref, client: "codex", version: @sdk_version)

      approval = fn tool, args, context ->
        assert tool == "test_tool"
        assert args == %{}
        assert context == %{user: "test_user", session: "sess123"}
        :ok
      end

      assert {:ok, %{"ok" => true}} =
               Client.call_tool(client, "test_tool", %{},
                 approval: approval,
                 context: %{user: "test_user", session: "sess123"},
                 retries: 0
               )
    end

    test "handles nil server_name in telemetry" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}},
          %{"result" => %{"data" => "test"}}
        ])

      transport_ref = {FakeTransport, transport}
      {:ok, client} = Client.handshake(transport_ref, client: "codex", version: @sdk_version)

      test_pid = self()

      :telemetry.attach(
        "test-mcp-nil-server",
        [:codex, :mcp, :tool_call, :success],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      assert {:ok, _} = Client.call_tool(client, "tool", %{}, retries: 0)

      assert_receive {:telemetry, [:codex, :mcp, :tool_call, :success], _, metadata}
      assert metadata.server_name == nil

      :telemetry.detach("test-mcp-nil-server")
    end
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

  describe "tool name qualification" do
    test "handshake accepts server_name option" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}}
        ])

      transport_ref = {FakeTransport, transport}

      assert {:ok, client} =
               Client.handshake(transport_ref,
                 client: "codex",
                 version: @sdk_version,
                 server_name: "my_server"
               )

      assert client.server_name == "my_server"
    end

    test "list_tools qualifies tool names with server prefix" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}},
          %{"tools" => [%{"name" => "tool_a"}, %{"name" => "tool_b"}]}
        ])

      transport_ref = {FakeTransport, transport}

      {:ok, client} =
        Client.handshake(transport_ref,
          client: "codex",
          version: @sdk_version,
          server_name: "server1"
        )

      assert {:ok, tools, _} = Client.list_tools(client, qualify?: true)
      qualified_names = Enum.map(tools, & &1["qualified_name"])
      assert "mcp__server1__tool_a" in qualified_names
      assert "mcp__server1__tool_b" in qualified_names
    end

    test "list_tools truncates long tool names with SHA1 suffix" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}},
          %{
            "tools" => [
              %{
                "name" =>
                  "extremely_lengthy_function_name_that_absolutely_surpasses_all_reasonable_limits"
              }
            ]
          }
        ])

      transport_ref = {FakeTransport, transport}

      {:ok, client} =
        Client.handshake(transport_ref,
          client: "codex",
          version: @sdk_version,
          server_name: "my_server"
        )

      assert {:ok, [tool], _} = Client.list_tools(client, qualify?: true)
      qualified_name = tool["qualified_name"]

      # Should be exactly 64 chars
      assert String.length(qualified_name) == 64

      # Should start with the expected prefix
      assert String.starts_with?(qualified_name, "mcp__my_server__extremel")

      # Should contain a SHA1 hash suffix (40 hex chars)
      suffix = String.slice(qualified_name, -40, 40)
      assert Regex.match?(~r/^[a-f0-9]{40}$/, suffix)
    end

    test "list_tools preserves original name alongside qualified name" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}},
          %{"tools" => [%{"name" => "echo", "description" => "echoes input"}]}
        ])

      transport_ref = {FakeTransport, transport}

      {:ok, client} =
        Client.handshake(transport_ref,
          client: "codex",
          version: @sdk_version,
          server_name: "shell"
        )

      assert {:ok, [tool], _} = Client.list_tools(client, qualify?: true)
      assert tool["name"] == "echo"
      assert tool["qualified_name"] == "mcp__shell__echo"
      assert tool["server_name"] == "shell"
    end

    test "list_tools without qualify? option returns original names only" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}},
          %{"tools" => [%{"name" => "tool_a"}]}
        ])

      transport_ref = {FakeTransport, transport}

      {:ok, client} =
        Client.handshake(transport_ref,
          client: "codex",
          version: @sdk_version,
          server_name: "server1"
        )

      assert {:ok, [tool], _} = Client.list_tools(client)
      assert tool["name"] == "tool_a"
      # qualified_name should not be present when qualify? is false
      refute Map.has_key?(tool, "qualified_name")
    end

    test "list_tools skips duplicate qualified names" do
      {:ok, transport} =
        FakeTransport.start_link([
          %{"type" => "handshake.ack", "capabilities" => %{}},
          %{"tools" => [%{"name" => "dup"}, %{"name" => "dup"}]}
        ])

      transport_ref = {FakeTransport, transport}

      {:ok, client} =
        Client.handshake(transport_ref,
          client: "codex",
          version: @sdk_version,
          server_name: "server1"
        )

      assert {:ok, tools, _} = Client.list_tools(client, qualify?: true)
      # Only one tool should remain after deduplication
      assert length(tools) == 1
    end
  end

  describe "qualify_tool_name/2" do
    test "qualifies short names correctly" do
      result = Client.qualify_tool_name("server1", "tool_a")
      assert result == "mcp__server1__tool_a"
    end

    test "truncates names exceeding 64 chars with SHA1 suffix" do
      long_tool =
        "extremely_lengthy_function_name_that_absolutely_surpasses_all_reasonable_limits"

      result = Client.qualify_tool_name("my_server", long_tool)

      assert String.length(result) == 64
      assert String.starts_with?(result, "mcp__my_server__extremel")
    end

    test "produces different hashes for different long names" do
      server = "my_server"

      result1 =
        Client.qualify_tool_name(
          server,
          "extremely_lengthy_function_name_that_absolutely_surpasses_all_reasonable_limits"
        )

      result2 =
        Client.qualify_tool_name(
          server,
          "yet_another_extremely_lengthy_function_name_that_absolutely_surpasses_all_reasonable_limits"
        )

      assert result1 != result2
      assert String.length(result1) == 64
      assert String.length(result2) == 64
    end

    test "matches Rust implementation output for known inputs" do
      # From Rust tests: mcp__my_server__extremely_lengthy -> truncated with specific hash
      result =
        Client.qualify_tool_name(
          "my_server",
          "extremely_lengthy_function_name_that_absolutely_surpasses_all_reasonable_limits"
        )

      assert result == "mcp__my_server__extremel119a2b97664e41363932dc84de21e2ff1b93b3e9"
    end
  end
end

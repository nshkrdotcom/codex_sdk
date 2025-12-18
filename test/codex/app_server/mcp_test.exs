defmodule Codex.AppServer.McpTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer.Connection
  alias Codex.AppServer.Mcp
  alias Codex.AppServer.Protocol
  alias Codex.Options
  alias Codex.TestSupport.AppServerSubprocess

  setup do
    bash = System.find_executable("bash") || "/bin/bash"
    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: bash})

    {:ok, conn} =
      Connection.start_link(codex_opts,
        subprocess: {AppServerSubprocess, owner: self()},
        init_timeout_ms: 200
      )

    assert_receive {:app_server_subprocess_started, ^conn, os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    send(conn, {:stdout, os_pid, Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"})})
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    {:ok, conn: conn, os_pid: os_pid}
  end

  describe "list_servers/2" do
    test "uses new method mcpServerStatus/list on new servers", %{conn: conn, os_pid: os_pid} do
      task = Task.async(fn -> Mcp.list_servers(conn) end)

      assert_receive {:app_server_subprocess_send, ^conn, request_line}

      assert {:ok, %{"id" => req_id, "method" => "mcpServerStatus/list"}} =
               Jason.decode(request_line)

      send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"data" => []})})

      assert {:ok, %{"data" => _}} = Task.await(task, 200)
    end

    test "falls back to mcpServers/list on old servers (-32601 method not found)", %{
      conn: conn,
      os_pid: os_pid
    } do
      task = Task.async(fn -> Mcp.list_servers(conn) end)

      assert_receive {:app_server_subprocess_send, ^conn, request_line1}

      assert {:ok, %{"id" => req_id1, "method" => "mcpServerStatus/list"}} =
               Jason.decode(request_line1)

      send(conn, {:stdout, os_pid, encode_error(req_id1, -32_601)})

      assert_receive {:app_server_subprocess_send, ^conn, request_line2}

      assert {:ok, %{"id" => req_id2, "method" => "mcpServers/list"}} =
               Jason.decode(request_line2)

      send(conn, {:stdout, os_pid, Protocol.encode_response(req_id2, %{"data" => []})})

      assert {:ok, %{"data" => _}} = Task.await(task, 200)
    end

    test "falls back to mcpServers/list on old servers (-32600 unknown variant)", %{
      conn: conn,
      os_pid: os_pid
    } do
      task = Task.async(fn -> Mcp.list_servers(conn) end)

      assert_receive {:app_server_subprocess_send, ^conn, request_line1}

      assert {:ok, %{"id" => req_id1, "method" => "mcpServerStatus/list"}} =
               Jason.decode(request_line1)

      send(
        conn,
        {:stdout, os_pid,
         encode_error(
           req_id1,
           -32_600,
           "Invalid request: unknown variant `mcpServerStatus/list`, expected one of `initialize`"
         )}
      )

      assert_receive {:app_server_subprocess_send, ^conn, request_line2}

      assert {:ok, %{"id" => req_id2, "method" => "mcpServers/list"}} =
               Jason.decode(request_line2)

      send(conn, {:stdout, os_pid, Protocol.encode_response(req_id2, %{"data" => []})})

      assert {:ok, %{"data" => _}} = Task.await(task, 200)
    end

    test "returns error when both methods fail", %{conn: conn, os_pid: os_pid} do
      task = Task.async(fn -> Mcp.list_servers(conn) end)

      assert_receive {:app_server_subprocess_send, ^conn, request_line1}

      assert {:ok, %{"id" => req_id1, "method" => "mcpServerStatus/list"}} =
               Jason.decode(request_line1)

      send(conn, {:stdout, os_pid, encode_error(req_id1, -32_601)})

      assert_receive {:app_server_subprocess_send, ^conn, request_line2}

      assert {:ok, %{"id" => req_id2, "method" => "mcpServers/list"}} =
               Jason.decode(request_line2)

      send(conn, {:stdout, os_pid, encode_error(req_id2, -32_601)})

      assert {:error, %{"code" => -32_601}} = Task.await(task, 200)
    end
  end

  describe "list_server_statuses/2" do
    test "delegates to list_servers/2", %{conn: conn, os_pid: os_pid} do
      task = Task.async(fn -> Mcp.list_server_statuses(conn) end)

      assert_receive {:app_server_subprocess_send, ^conn, request_line}

      assert {:ok, %{"id" => req_id, "method" => "mcpServerStatus/list"}} =
               Jason.decode(request_line)

      send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"data" => []})})

      assert {:ok, %{"data" => _}} = Task.await(task, 200)
    end
  end

  defp encode_error(id, code, message \\ "Method not found") do
    %{"id" => id, "error" => %{"code" => code, "message" => message}}
    |> Jason.encode_to_iodata!()
    |> then(&[&1, "\n"])
  end
end

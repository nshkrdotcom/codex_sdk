defmodule Codex.SubagentsTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer.Connection
  alias Codex.AppServer.Protocol
  alias Codex.Options
  alias Codex.Protocol.SessionSource
  alias Codex.Protocol.SubAgentSource
  alias Codex.Subagents
  alias Codex.TestSupport.AppServerSubprocess

  setup do
    harness =
      AppServerSubprocess.new!(owner: self())
      |> AppServerSubprocess.put_current!()

    on_exit(fn -> AppServerSubprocess.cleanup(harness) end)

    {:ok, base_opts} = Options.new(%{api_key: "test"})
    codex_opts = AppServerSubprocess.codex_opts(base_opts, harness)

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(harness),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(harness, conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)

    :ok =
      AppServerSubprocess.send_stdout(
        Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"})
      )

    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    {:ok, conn: conn}
  end

  test "subagents: list defaults to subagent source filtering", %{conn: conn} do
    task = Task.async(fn -> Subagents.list(conn, limit: 5) end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "thread/list", "params" => params}} =
             Jason.decode(request_line)

    assert params["limit"] == 5
    assert params["sourceKinds"] == ["subAgent"]

    :ok = AppServerSubprocess.send_stdout(Protocol.encode_response(req_id, %{"data" => []}))

    assert {:ok, []} = Task.await(task, 200)
  end

  test "subagents: list passes thread/list timeout overrides through to app-server", %{
    conn: conn
  } do
    assert {:error, {:timeout, "thread/list", 10}} =
             Subagents.list(conn, limit: 5, timeout_ms: 10)
  end

  test "subagents: lists children for parent thread", %{conn: conn} do
    task = Task.async(fn -> Subagents.children(conn, "thr_parent") end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "thread/list", "params" => params}} =
             Jason.decode(request_line)

    assert params["sourceKinds"] == ["subAgentThreadSpawn"]

    :ok =
      AppServerSubprocess.send_stdout(
        Protocol.encode_response(req_id, %{
          "data" => [
            %{
              "id" => "thr_child",
              "source" => %{
                "subAgent" => %{
                  "thread_spawn" => %{
                    "parent_thread_id" => "thr_parent",
                    "depth" => 1,
                    "agent_nickname" => "Atlas",
                    "agent_role" => "explorer"
                  }
                }
              }
            },
            %{
              "id" => "thr_other",
              "source" => %{
                "subAgent" => %{
                  "thread_spawn" => %{
                    "parent_thread_id" => "thr_elsewhere",
                    "depth" => 1
                  }
                }
              }
            }
          ]
        })
      )

    assert {:ok, [%{"id" => "thr_child"} = child]} = Task.await(task, 200)

    assert %SessionSource{
             kind: :sub_agent,
             sub_agent: %SubAgentSource{
               variant: :thread_spawn,
               parent_thread_id: "thr_parent",
               depth: 1,
               agent_nickname: "Atlas",
               agent_role: "explorer"
             }
           } = Subagents.source(child)

    assert Subagents.parent_thread_id(child) == "thr_parent"
    assert Subagents.child_thread?(child)
  end

  test "subagents: read returns a known child thread", %{conn: conn} do
    task = Task.async(fn -> Subagents.read(conn, "thr_child", include_turns: true) end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "thread/read", "params" => params}} =
             Jason.decode(request_line)

    assert params == %{"threadId" => "thr_child", "includeTurns" => true}

    thread = %{
      "id" => "thr_child",
      "status" => %{"type" => "notLoaded"},
      "source" => %{
        "subAgent" => %{
          "thread_spawn" => %{
            "parent_thread_id" => "thr_parent",
            "depth" => 1
          }
        }
      },
      "turns" => [%{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}]
    }

    :ok = AppServerSubprocess.send_stdout(Protocol.encode_response(req_id, %{"thread" => thread}))

    assert {:ok, ^thread} = Task.await(task, 200)
  end

  test "subagents: read passes thread/read timeout overrides through to app-server", %{
    conn: conn
  } do
    assert {:error, {:timeout, "thread/read", 10}} =
             Subagents.read(conn, "thr_child", timeout_ms: 10)
  end

  test "subagents: await returns completed child status", %{conn: conn} do
    task =
      Task.async(fn ->
        Subagents.await(conn, "thr_child", timeout: 1_000, interval: 0)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, first_line}

    assert {:ok, %{"id" => first_id, "method" => "thread/read", "params" => first_params}} =
             Jason.decode(first_line)

    assert first_params == %{"threadId" => "thr_child", "includeTurns" => true}

    :ok =
      AppServerSubprocess.send_stdout(
        Protocol.encode_response(first_id, %{
          "thread" => %{
            "id" => "thr_child",
            "status" => %{"type" => "active", "activeFlags" => []},
            "turns" => [
              %{"id" => "turn_1", "status" => "inProgress", "items" => [], "error" => nil}
            ]
          }
        })
      )

    assert_receive {:app_server_subprocess_send, ^conn, second_line}

    assert {:ok, %{"id" => second_id, "method" => "thread/read", "params" => second_params}} =
             Jason.decode(second_line)

    assert second_params == %{"threadId" => "thr_child", "includeTurns" => true}

    :ok =
      AppServerSubprocess.send_stdout(
        Protocol.encode_response(second_id, %{
          "thread" => %{
            "id" => "thr_child",
            "status" => %{"type" => "notLoaded"},
            "turns" => [
              %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
            ]
          }
        })
      )

    assert {:ok, :completed} = Task.await(task, 200)
  end

  test "subagents: await retries thread/read timeouts until a later poll succeeds", %{conn: conn} do
    task =
      Task.async(fn ->
        Subagents.await(conn, "thr_child", timeout: 1_000, interval: 0, read_timeout_ms: 100)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, first_line}

    assert {:ok, %{"method" => "thread/read", "params" => first_params}} =
             Jason.decode(first_line)

    assert first_params == %{"threadId" => "thr_child", "includeTurns" => true}

    assert_receive {:app_server_subprocess_send, ^conn, second_line}, 500

    assert {:ok, %{"id" => second_id, "method" => "thread/read", "params" => second_params}} =
             Jason.decode(second_line)

    assert second_params == %{"threadId" => "thr_child", "includeTurns" => true}

    :ok =
      AppServerSubprocess.send_stdout(
        Protocol.encode_response(second_id, %{
          "thread" => %{
            "id" => "thr_child",
            "status" => %{"type" => "notLoaded"},
            "turns" => [
              %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
            ]
          }
        })
      )

    assert {:ok, :completed} = Task.await(task, 1_000)
  end

  test "subagents: await always requests turns even when include_turns is false", %{
    conn: conn
  } do
    task =
      Task.async(fn ->
        Subagents.await(conn, "thr_child", timeout: 1_000, interval: 0, include_turns: false)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "thread/read", "params" => params}} =
             Jason.decode(request_line)

    assert params == %{"threadId" => "thr_child", "includeTurns" => true}

    :ok =
      AppServerSubprocess.send_stdout(
        Protocol.encode_response(req_id, %{
          "thread" => %{
            "id" => "thr_child",
            "status" => %{"type" => "notLoaded"},
            "turns" => [
              %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
            ]
          }
        })
      )

    assert {:ok, :completed} = Task.await(task, 200)
  end
end

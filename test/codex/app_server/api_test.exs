defmodule Codex.AppServer.ApiTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer
  alias Codex.AppServer.Connection
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

  test "turn_start/4 encodes UserInput blocks", %{conn: conn, os_pid: os_pid} do
    task =
      Task.async(fn ->
        AppServer.turn_start(conn, "thr_1", [
          %{type: :text, text: "hi"},
          %{type: :local_image, path: "/tmp/a.png"}
        ])
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "turn/start", "params" => params}} =
             Jason.decode(request_line)

    assert params["threadId"] == "thr_1"

    assert [
             %{"type" => "text", "text" => "hi"},
             %{"type" => "localImage", "path" => "/tmp/a.png"}
           ] = params["input"]

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(req_id, %{
         "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
       })}
    )

    assert {:ok, %{"turn" => %{"id" => "turn_1"}}} = Task.await(task, 200)
  end

  test "turn_start/4 encodes sandbox policy overrides", %{conn: conn, os_pid: os_pid} do
    task =
      Task.async(fn ->
        AppServer.turn_start(conn, "thr_1", "hi",
          sandbox_policy: %{
            type: :workspace_write,
            writable_roots: ["/tmp"],
            network_access: true
          }
        )
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "turn/start", "params" => params}} =
             Jason.decode(request_line)

    assert %{
             "type" => "workspaceWrite",
             "writableRoots" => ["/tmp"],
             "networkAccess" => true
           } = params["sandboxPolicy"]

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(req_id, %{
         "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
       })}
    )

    assert {:ok, %{"turn" => %{"id" => "turn_1"}}} = Task.await(task, 200)
  end

  test "thread_resume/3 encodes history and path", %{conn: conn, os_pid: os_pid} do
    history = [%{"type" => "ghost_snapshot", "ghost_commit" => %{"id" => "ghost_1"}}]

    task =
      Task.async(fn ->
        AppServer.thread_resume(conn, "thr_1", history: history, path: "/tmp/rollout.jsonl")
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "thread/resume", "params" => params}} =
             Jason.decode(request_line)

    assert params["threadId"] == "thr_1"
    assert params["history"] == history
    assert params["path"] == "/tmp/rollout.jsonl"

    send(
      conn,
      {:stdout, os_pid, Protocol.encode_response(req_id, %{"thread" => %{"id" => "thr_1"}})}
    )

    assert {:ok, %{"thread" => %{"id" => "thr_1"}}} = Task.await(task, 200)
  end

  test "thread_start/2 encodes none personality from atom", %{conn: conn, os_pid: os_pid} do
    task = Task.async(fn -> AppServer.thread_start(conn, personality: :none) end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "thread/start", "params" => params}} =
             Jason.decode(request_line)

    assert params["personality"] == "none"

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"thread" => %{}})})

    assert {:ok, %{"thread" => _}} = Task.await(task, 200)
  end

  test "thread_resume/3 encodes none personality from string", %{conn: conn, os_pid: os_pid} do
    task = Task.async(fn -> AppServer.thread_resume(conn, "thr_1", personality: "none") end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "thread/resume", "params" => params}} =
             Jason.decode(request_line)

    assert params["threadId"] == "thr_1"
    assert params["personality"] == "none"

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"thread" => %{}})})

    assert {:ok, %{"thread" => _}} = Task.await(task, 200)
  end

  test "thread_fork/3 encodes fork params", %{conn: conn, os_pid: os_pid} do
    task =
      Task.async(fn ->
        AppServer.thread_fork(conn, "thr_1", path: "/tmp/rollout.jsonl", model: "gpt-5.1-codex")
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "thread/fork", "params" => params}} =
             Jason.decode(request_line)

    assert params["threadId"] == "thr_1"
    assert params["path"] == "/tmp/rollout.jsonl"
    assert params["model"] == "gpt-5.1-codex"

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"thread" => %{}})})

    assert {:ok, %{"thread" => _}} = Task.await(task, 200)
  end

  test "thread_rollback/3 encodes numTurns", %{conn: conn, os_pid: os_pid} do
    task = Task.async(fn -> AppServer.thread_rollback(conn, "thr_1", 2) end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "thread/rollback", "params" => params}} =
             Jason.decode(request_line)

    assert params["threadId"] == "thr_1"
    assert params["numTurns"] == 2

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"status" => "ok"})})

    assert {:ok, %{"status" => "ok"}} = Task.await(task, 200)
  end

  test "thread_read/3 encodes includeTurns", %{conn: conn, os_pid: os_pid} do
    task = Task.async(fn -> AppServer.thread_read(conn, "thr_1", include_turns: true) end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "thread/read", "params" => params}} =
             Jason.decode(request_line)

    assert params["threadId"] == "thr_1"
    assert params["includeTurns"] == true

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"thread" => %{}})})

    assert {:ok, %{"thread" => _}} = Task.await(task, 200)
  end

  test "thread_loaded_list/2 encodes cursor and limit", %{conn: conn, os_pid: os_pid} do
    task = Task.async(fn -> AppServer.thread_loaded_list(conn, cursor: "cursor", limit: 10) end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "thread/loaded/list", "params" => params}} =
             Jason.decode(request_line)

    assert params["cursor"] == "cursor"
    assert params["limit"] == 10

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"data" => []})})

    assert {:ok, %{"data" => []}} = Task.await(task, 200)
  end

  test "skills_config_write/3 encodes path and enabled", %{conn: conn, os_pid: os_pid} do
    task = Task.async(fn -> AppServer.skills_config_write(conn, "/tmp/skill", true) end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "skills/config/write", "params" => params}} =
             Jason.decode(request_line)

    assert params["path"] == "/tmp/skill"
    assert params["enabled"] == true

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"status" => "ok"})})

    assert {:ok, %{"status" => "ok"}} = Task.await(task, 200)
  end

  test "config_requirements/1 encodes request", %{conn: conn, os_pid: os_pid} do
    task = Task.async(fn -> AppServer.config_requirements(conn) end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "configRequirements/read"}} =
             Jason.decode(request_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"data" => []})})

    assert {:ok, %{"data" => []}} = Task.await(task, 200)
  end

  test "collaboration_mode_list/1 encodes request", %{conn: conn, os_pid: os_pid} do
    task = Task.async(fn -> AppServer.collaboration_mode_list(conn) end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "collaborationMode/list"}} =
             Jason.decode(request_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"data" => []})})

    assert {:ok, %{"data" => []}} = Task.await(task, 200)
  end

  test "apps_list/2 encodes cursor and limit", %{conn: conn, os_pid: os_pid} do
    task = Task.async(fn -> AppServer.apps_list(conn, cursor: "c1", limit: 2) end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "app/list", "params" => params}} =
             Jason.decode(request_line)

    assert params["cursor"] == "c1"
    assert params["limit"] == 2

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"data" => []})})

    assert {:ok, %{"data" => []}} = Task.await(task, 200)
  end

  test "thread_list/2 encodes sort key and archived", %{conn: conn, os_pid: os_pid} do
    task =
      Task.async(fn -> AppServer.thread_list(conn, sort_key: :updated_at, archived: true) end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "thread/list", "params" => params}} =
             Jason.decode(request_line)

    assert params["sortKey"] == "updated_at"
    assert params["archived"] == true

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"data" => []})})

    assert {:ok, %{"data" => []}} = Task.await(task, 200)
  end

  test "turn_start/4 encodes personality and collaboration mode", %{conn: conn, os_pid: os_pid} do
    collab = %Codex.Protocol.CollaborationMode{
      mode: :plan,
      model: "gpt-5.1-codex",
      reasoning_effort: :high,
      developer_instructions: "Plan carefully."
    }

    task =
      Task.async(fn ->
        AppServer.turn_start(conn, "thr_1", "hi",
          personality: :friendly,
          output_schema: %{"type" => "object"},
          collaboration_mode: collab
        )
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "turn/start", "params" => params}} =
             Jason.decode(request_line)

    assert params["personality"] == "friendly"
    assert %{"type" => "object"} = params["outputSchema"]
    assert %{"mode" => "plan", "model" => "gpt-5.1-codex"} = params["collaborationMode"]

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(req_id, %{
         "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
       })}
    )

    assert {:ok, %{"turn" => %{"id" => "turn_1"}}} = Task.await(task, 200)
  end

  test "turn_start/4 encodes pair_programming collaboration mode", %{conn: conn, os_pid: os_pid} do
    collab = %Codex.Protocol.CollaborationMode{
      mode: :pair_programming,
      model: "gpt-5.3-codex",
      reasoning_effort: :medium,
      developer_instructions: "Keep output practical."
    }

    task =
      Task.async(fn ->
        AppServer.turn_start(conn, "thr_1", "hi", collaboration_mode: collab)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "turn/start", "params" => params}} =
             Jason.decode(request_line)

    assert %{"mode" => "pair_programming", "model" => "gpt-5.3-codex"} =
             params["collaborationMode"]

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(req_id, %{
         "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
       })}
    )

    assert {:ok, %{"turn" => %{"id" => "turn_1"}}} = Task.await(task, 200)
  end

  test "turn_start/4 encodes none personality", %{conn: conn, os_pid: os_pid} do
    task = Task.async(fn -> AppServer.turn_start(conn, "thr_1", "hi", personality: :none) end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "turn/start", "params" => params}} =
             Jason.decode(request_line)

    assert params["personality"] == "none"

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(req_id, %{
         "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
       })}
    )

    assert {:ok, %{"turn" => %{"id" => "turn_1"}}} = Task.await(task, 200)
  end

  test "skills_list/2 encodes force_reload", %{conn: conn, os_pid: os_pid} do
    task = Task.async(fn -> AppServer.skills_list(conn, cwds: ["/tmp"], force_reload: true) end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "skills/list", "params" => params}} =
             Jason.decode(request_line)

    assert params["cwds"] == ["/tmp"]
    assert params["forceReload"] == true

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"data" => []})})

    assert {:ok, %{"data" => []}} = Task.await(task, 200)
  end

  test "fuzzy_file_search/3 encodes query roots and cancellation token", %{
    conn: conn,
    os_pid: os_pid
  } do
    task =
      Task.async(fn ->
        AppServer.fuzzy_file_search(conn, "readme",
          roots: ["/tmp"],
          cancellation_token: "tok-1"
        )
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "fuzzyFileSearch", "params" => params}} =
             Jason.decode(request_line)

    assert params["query"] == "readme"
    assert params["roots"] == ["/tmp"]
    assert params["cancellationToken"] == "tok-1"

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"files" => []})})

    assert {:ok, %{"files" => []}} = Task.await(task, 200)
  end

  test "config_write/4 encodes merge strategy and key_path", %{conn: conn, os_pid: os_pid} do
    task =
      Task.async(fn ->
        AppServer.config_write(conn, "features.web_search_request", true, merge_strategy: :upsert)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "config/value/write", "params" => params}} =
             Jason.decode(request_line)

    assert params["keyPath"] == "features.web_search_request"
    assert params["value"] == true
    assert params["mergeStrategy"] == "upsert"

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(req_id, %{
         "status" => "ok",
         "version" => "v1",
         "filePath" => "/tmp/config.toml",
         "overriddenMetadata" => nil
       })}
    )

    assert {:ok, %{"status" => "ok"}} = Task.await(task, 200)
  end

  test "command_write_stdin/4 encodes process and stdin payloads", %{conn: conn, os_pid: os_pid} do
    task =
      Task.async(fn ->
        AppServer.command_write_stdin(conn, "proc_1", "y\n",
          thread_id: "thr_1",
          turn_id: "turn_1",
          item_id: "item_1",
          yield_time_ms: 120,
          max_output_tokens: 64
        )
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "command/writeStdin", "params" => params}} =
             Jason.decode(request_line)

    assert params["processId"] == "proc_1"
    assert params["stdin"] == "y\n"
    assert params["threadId"] == "thr_1"
    assert params["turnId"] == "turn_1"
    assert params["itemId"] == "item_1"
    assert params["yieldTimeMs"] == 120
    assert params["maxOutputTokens"] == 64

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"status" => "ok"})})

    assert {:ok, %{"status" => "ok"}} = Task.await(task, 200)
  end

  test "account login_start encodes apiKey and chatgpt variants", %{conn: conn, os_pid: os_pid} do
    task1 = Task.async(fn -> AppServer.Account.login_start(conn, {:api_key, "sk-test"}) end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line1}

    assert {:ok, %{"id" => req_id1, "method" => "account/login/start", "params" => params1}} =
             Jason.decode(request_line1)

    assert params1 == %{"type" => "apiKey", "apiKey" => "sk-test"}

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id1, %{"type" => "apiKey"})})
    assert {:ok, %{"type" => "apiKey"}} = Task.await(task1, 200)

    task2 = Task.async(fn -> AppServer.Account.login_start(conn, :chatgpt) end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line2}

    assert {:ok, %{"id" => req_id2, "method" => "account/login/start", "params" => params2}} =
             Jason.decode(request_line2)

    assert params2 == %{"type" => "chatgpt"}

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(req_id2, %{
         "type" => "chatgpt",
         "loginId" => "login_1",
         "authUrl" => "https://example.com"
       })}
    )

    assert {:ok, %{"type" => "chatgpt"}} = Task.await(task2, 200)
  end

  describe "thread_compact/2" do
    test "returns unsupported error for removed API without sending request", %{conn: conn} do
      task =
        Task.async(fn ->
          fun = Function.capture(AppServer, :thread_compact, 2)
          fun.(conn, "thr_123")
        end)

      refute_receive {:app_server_subprocess_send, ^conn, _request_line}, 100

      assert {:error, {:unsupported, message}} = Task.await(task, 200)
      assert message =~ "thread/compact"
      assert message =~ "removed"
    end
  end
end

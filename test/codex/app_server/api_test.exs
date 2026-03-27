defmodule Codex.AppServer.ApiTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer
  alias Codex.AppServer.Connection
  alias Codex.AppServer.Protocol
  alias Codex.Protocol.Plugin
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

  test "thread start and resume encode approvals reviewer", %{conn: conn, os_pid: os_pid} do
    start_task =
      Task.async(fn ->
        AppServer.thread_start(conn, approvals_reviewer: :guardian_subagent)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, start_line}

    assert {:ok, %{"id" => start_id, "method" => "thread/start", "params" => start_params}} =
             Jason.decode(start_line)

    assert start_params["approvalsReviewer"] == "guardian_subagent"

    send(conn, {:stdout, os_pid, Protocol.encode_response(start_id, %{"thread" => %{}})})
    assert {:ok, %{"thread" => _}} = Task.await(start_task, 200)

    resume_task =
      Task.async(fn ->
        AppServer.thread_resume(conn, "thr_1", approvals_reviewer: :user)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, resume_line}

    assert {:ok, %{"id" => resume_id, "method" => "thread/resume", "params" => resume_params}} =
             Jason.decode(resume_line)

    assert resume_params["threadId"] == "thr_1"
    assert resume_params["approvalsReviewer"] == "user"

    send(conn, {:stdout, os_pid, Protocol.encode_response(resume_id, %{"thread" => %{}})})
    assert {:ok, %{"thread" => _}} = Task.await(resume_task, 200)
  end

  test "thread and turn start encode granular approval policies with upstream external tagging",
       %{
         conn: conn,
         os_pid: os_pid
       } do
    approval_policy = %{
      type: :granular,
      sandbox_approval: true,
      rules: true,
      request_permissions: true
    }

    thread_task =
      Task.async(fn ->
        AppServer.thread_start(conn, approval_policy: approval_policy)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_line}

    assert {:ok, %{"id" => thread_id, "method" => "thread/start", "params" => thread_params}} =
             Jason.decode(thread_line)

    assert thread_params["approvalPolicy"] == %{
             "granular" => %{
               "sandbox_approval" => true,
               "rules" => true,
               "skill_approval" => false,
               "request_permissions" => true,
               "mcp_elicitations" => false
             }
           }

    send(conn, {:stdout, os_pid, Protocol.encode_response(thread_id, %{"thread" => %{}})})
    assert {:ok, %{"thread" => _}} = Task.await(thread_task, 200)

    turn_task =
      Task.async(fn ->
        AppServer.turn_start(conn, "thr_1", "hi", approval_policy: approval_policy)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, turn_line}

    assert {:ok, %{"id" => turn_id, "method" => "turn/start", "params" => turn_params}} =
             Jason.decode(turn_line)

    assert turn_params["threadId"] == "thr_1"
    assert turn_params["approvalPolicy"] == thread_params["approvalPolicy"]

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(turn_id, %{
         "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
       })}
    )

    assert {:ok, %{"turn" => %{"id" => "turn_1"}}} = Task.await(turn_task, 200)
  end

  test "experimental_feature_enablement_set/2 uses the upstream method and payload", %{
    conn: conn,
    os_pid: os_pid
  } do
    task =
      Task.async(fn ->
        AppServer.experimental_feature_enablement_set(conn, apps: true, plugins: false)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok,
            %{
              "id" => req_id,
              "method" => "experimentalFeature/enablement/set",
              "params" => params
            }} =
             Jason.decode(request_line)

    assert params == %{
             "enablement" => %{
               "apps" => true,
               "plugins" => false
             }
           }

    send(
      conn,
      {:stdout, os_pid, Protocol.encode_response(req_id, %{"enablement" => params["enablement"]})}
    )

    assert {:ok, %{"enablement" => %{"apps" => true, "plugins" => false}}} =
             Task.await(task, 200)
  end

  test "experimental_feature_enablement_set/2 allows an empty enablement map", %{
    conn: conn,
    os_pid: os_pid
  } do
    task =
      Task.async(fn ->
        AppServer.experimental_feature_enablement_set(conn, %{})
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok,
            %{
              "id" => req_id,
              "method" => "experimentalFeature/enablement/set",
              "params" => %{"enablement" => %{}}
            }} =
             Jason.decode(request_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"enablement" => %{}})})

    assert {:ok, %{"enablement" => %{}}} = Task.await(task, 200)
  end

  test "thread_start/2 rejects malformed granular approval policies without sending a request", %{
    conn: conn
  } do
    assert {:error, {:invalid_ask_for_approval, _reason}} =
             AppServer.thread_start(conn,
               approval_policy: %{granular: %{request_permissions: "yes"}}
             )

    refute_receive {:app_server_subprocess_send, ^conn, _request_line}, 50
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

  test "thread_fork/3 does not inject startup history or duplicate context params", %{
    conn: conn,
    os_pid: os_pid
  } do
    task = Task.async(fn -> AppServer.thread_fork(conn, "thr_1") end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "thread/fork", "params" => params}} =
             Jason.decode(request_line)

    assert params == %{"threadId" => "thr_1"}
    refute Map.has_key?(params, "history")
    refute Map.has_key?(params, "input")
    refute Map.has_key?(params, "baseInstructions")
    refute Map.has_key?(params, "developerInstructions")

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"thread" => %{}})})

    assert {:ok, %{"thread" => _}} = Task.await(task, 200)
  end

  test "thread start, resume, and fork encode service controls", %{conn: conn, os_pid: os_pid} do
    start_task =
      Task.async(fn ->
        AppServer.thread_start(conn,
          ephemeral: true,
          service_name: "codex-elixir-tests",
          service_tier: :flex
        )
      end)

    assert_receive {:app_server_subprocess_send, ^conn, start_line}

    assert {:ok, %{"id" => start_id, "method" => "thread/start", "params" => start_params}} =
             Jason.decode(start_line)

    assert start_params["ephemeral"] == true
    assert start_params["serviceName"] == "codex-elixir-tests"
    assert start_params["serviceTier"] == "flex"

    send(conn, {:stdout, os_pid, Protocol.encode_response(start_id, %{"thread" => %{}})})
    assert {:ok, %{"thread" => _}} = Task.await(start_task, 200)

    resume_task =
      Task.async(fn ->
        AppServer.thread_resume(conn, "thr_1", service_tier: "priority")
      end)

    assert_receive {:app_server_subprocess_send, ^conn, resume_line}

    assert {:ok, %{"id" => resume_id, "method" => "thread/resume", "params" => resume_params}} =
             Jason.decode(resume_line)

    assert resume_params["threadId"] == "thr_1"
    assert resume_params["serviceTier"] == "priority"

    send(conn, {:stdout, os_pid, Protocol.encode_response(resume_id, %{"thread" => %{}})})
    assert {:ok, %{"thread" => _}} = Task.await(resume_task, 200)

    fork_task =
      Task.async(fn ->
        AppServer.thread_fork(conn, "thr_1", ephemeral: true, service_tier: :auto)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, fork_line}

    assert {:ok, %{"id" => fork_id, "method" => "thread/fork", "params" => fork_params}} =
             Jason.decode(fork_line)

    assert fork_params["threadId"] == "thr_1"
    assert fork_params["ephemeral"] == true
    assert fork_params["serviceTier"] == "auto"

    send(conn, {:stdout, os_pid, Protocol.encode_response(fork_id, %{"thread" => %{}})})
    assert {:ok, %{"thread" => _}} = Task.await(fork_task, 200)
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

  test "thread lifecycle wrappers encode current upstream params", %{conn: conn, os_pid: os_pid} do
    list_task =
      Task.async(fn ->
        AppServer.thread_list(conn,
          sort_key: :updated_at,
          archived: false,
          source_kinds: [:app_server, :sub_agent_review],
          cwd: "/tmp/project",
          search_term: "checkout"
        )
      end)

    assert_receive {:app_server_subprocess_send, ^conn, list_line}

    assert {:ok, %{"id" => list_id, "method" => "thread/list", "params" => list_params}} =
             Jason.decode(list_line)

    assert list_params["sortKey"] == "updated_at"
    assert list_params["archived"] == false
    assert list_params["sourceKinds"] == ["appServer", "subAgentReview"]
    assert list_params["cwd"] == "/tmp/project"
    assert list_params["searchTerm"] == "checkout"

    send(conn, {:stdout, os_pid, Protocol.encode_response(list_id, %{"data" => []})})
    assert {:ok, %{"data" => []}} = Task.await(list_task, 200)

    unsubscribe_task = Task.async(fn -> AppServer.thread_unsubscribe(conn, "thr_1") end)
    assert_receive {:app_server_subprocess_send, ^conn, unsubscribe_line}

    assert {:ok,
            %{
              "id" => unsubscribe_id,
              "method" => "thread/unsubscribe",
              "params" => %{"threadId" => "thr_1"}
            }} = Jason.decode(unsubscribe_line)

    send(
      conn,
      {:stdout, os_pid, Protocol.encode_response(unsubscribe_id, %{"status" => "unsubscribed"})}
    )

    assert {:ok, %{"status" => "unsubscribed"}} = Task.await(unsubscribe_task, 200)

    rename_task = Task.async(fn -> AppServer.thread_name_set(conn, "thr_1", "Renamed") end)
    assert_receive {:app_server_subprocess_send, ^conn, rename_line}

    assert {:ok,
            %{
              "id" => rename_id,
              "method" => "thread/name/set",
              "params" => %{"threadId" => "thr_1", "name" => "Renamed"}
            }} = Jason.decode(rename_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(rename_id, %{"status" => "ok"})})
    assert {:ok, %{"status" => "ok"}} = Task.await(rename_task, 200)

    metadata_task =
      Task.async(fn ->
        AppServer.thread_metadata_update(conn, "thr_1",
          git_info: %{sha: nil, branch: "main", origin_url: nil}
        )
      end)

    assert_receive {:app_server_subprocess_send, ^conn, metadata_line}

    assert {:ok,
            %{
              "id" => metadata_id,
              "method" => "thread/metadata/update",
              "params" => metadata_params
            }} = Jason.decode(metadata_line)

    assert metadata_params["threadId"] == "thr_1"
    assert metadata_params["gitInfo"] == %{"sha" => nil, "branch" => "main", "originUrl" => nil}

    send(
      conn,
      {:stdout, os_pid, Protocol.encode_response(metadata_id, %{"thread" => %{"id" => "thr_1"}})}
    )

    assert {:ok, %{"thread" => %{"id" => "thr_1"}}} = Task.await(metadata_task, 200)

    unarchive_task = Task.async(fn -> AppServer.thread_unarchive(conn, "thr_1") end)
    assert_receive {:app_server_subprocess_send, ^conn, unarchive_line}

    assert {:ok,
            %{
              "id" => unarchive_id,
              "method" => "thread/unarchive",
              "params" => %{"threadId" => "thr_1"}
            }} = Jason.decode(unarchive_line)

    send(
      conn,
      {:stdout, os_pid, Protocol.encode_response(unarchive_id, %{"thread" => %{"id" => "thr_1"}})}
    )

    assert {:ok, %{"thread" => %{"id" => "thr_1"}}} = Task.await(unarchive_task, 200)
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

  test "apps_list/2 encodes thread gating and force refetch", %{conn: conn, os_pid: os_pid} do
    task =
      Task.async(fn ->
        AppServer.apps_list(conn, thread_id: "thr_1", force_refetch: true)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "app/list", "params" => params}} =
             Jason.decode(request_line)

    assert params["threadId"] == "thr_1"
    assert params["forceRefetch"] == true

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"data" => []})})
    assert {:ok, %{"data" => []}} = Task.await(task, 200)
  end

  test "thread_list/2 normalizes legacy source kind aliases", %{conn: conn, os_pid: os_pid} do
    task =
      Task.async(fn ->
        AppServer.thread_list(conn,
          source_kinds: [:mcp, "subagent", :sub_agent_thread_spawn]
        )
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "thread/list", "params" => params}} =
             Jason.decode(request_line)

    assert params["sourceKinds"] == ["appServer", "subAgent", "subAgentThreadSpawn"]

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

    assert %{
             "mode" => "plan",
             "settings" => %{
               "model" => "gpt-5.1-codex",
               "reasoning_effort" => "high",
               "developer_instructions" => "Plan carefully."
             }
           } = params["collaborationMode"]

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
      model: "gpt-5.4",
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

    assert %{
             "mode" => "pair_programming",
             "settings" => %{
               "model" => "gpt-5.4",
               "reasoning_effort" => "medium",
               "developer_instructions" => "Keep output practical."
             }
           } =
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

  test "turn APIs encode mention input and steering preconditions", %{conn: conn, os_pid: os_pid} do
    start_task =
      Task.async(fn ->
        AppServer.turn_start(conn, "thr_1", [%{type: :mention, name: "@docs", path: "app://docs"}])
      end)

    assert_receive {:app_server_subprocess_send, ^conn, start_line}

    assert {:ok, %{"id" => start_id, "method" => "turn/start", "params" => start_params}} =
             Jason.decode(start_line)

    assert start_params["input"] == [
             %{"type" => "mention", "name" => "@docs", "path" => "app://docs"}
           ]

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(start_id, %{
         "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
       })}
    )

    assert {:ok, %{"turn" => %{"id" => "turn_1"}}} = Task.await(start_task, 200)

    steer_task =
      Task.async(fn ->
        AppServer.turn_steer(conn, "thr_1", "continue", expected_turn_id: "turn_1")
      end)

    assert_receive {:app_server_subprocess_send, ^conn, steer_line}

    assert {:ok, %{"id" => steer_id, "method" => "turn/steer", "params" => steer_params}} =
             Jason.decode(steer_line)

    assert steer_params["threadId"] == "thr_1"
    assert steer_params["expectedTurnId"] == "turn_1"
    assert steer_params["input"] == [%{"type" => "text", "text" => "continue"}]

    send(conn, {:stdout, os_pid, Protocol.encode_response(steer_id, %{"turnId" => "turn_1"})})
    assert {:ok, %{"turnId" => "turn_1"}} = Task.await(steer_task, 200)
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

  test "turn_start/4 encodes service tier", %{conn: conn, os_pid: os_pid} do
    task = Task.async(fn -> AppServer.turn_start(conn, "thr_1", "hi", service_tier: :flex) end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "turn/start", "params" => params}} =
             Jason.decode(request_line)

    assert params["threadId"] == "thr_1"
    assert params["serviceTier"] == "flex"

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

  test "skills and plugin wrappers encode current upstream params", %{conn: conn, os_pid: os_pid} do
    skills_task =
      Task.async(fn ->
        AppServer.skills_list(conn,
          cwds: ["/tmp/project"],
          per_cwd_extra_user_roots: [
            %{cwd: "/tmp/project", extra_user_roots: ["/tmp/skills"]}
          ]
        )
      end)

    assert_receive {:app_server_subprocess_send, ^conn, skills_line}

    assert {:ok, %{"id" => skills_id, "method" => "skills/list", "params" => skills_params}} =
             Jason.decode(skills_line)

    assert skills_params["perCwdExtraUserRoots"] == [
             %{"cwd" => "/tmp/project", "extraUserRoots" => ["/tmp/skills"]}
           ]

    send(conn, {:stdout, os_pid, Protocol.encode_response(skills_id, %{"data" => []})})
    assert {:ok, %{"data" => []}} = Task.await(skills_task, 200)

    remote_list_task =
      Task.async(fn ->
        AppServer.skills_remote_list(conn,
          hazelnut_scope: :workspace_shared,
          product_surface: :codex,
          enabled: true
        )
      end)

    assert_receive {:app_server_subprocess_send, ^conn, remote_list_line}

    assert {:ok,
            %{
              "id" => remote_list_id,
              "method" => "skills/remote/list",
              "params" => remote_list_params
            }} = Jason.decode(remote_list_line)

    assert remote_list_params == %{
             "hazelnutScope" => "workspace-shared",
             "productSurface" => "codex",
             "enabled" => true
           }

    send(conn, {:stdout, os_pid, Protocol.encode_response(remote_list_id, %{"data" => []})})
    assert {:ok, %{"data" => []}} = Task.await(remote_list_task, 200)

    remote_export_task = Task.async(fn -> AppServer.skills_remote_export(conn, "hz_1") end)
    assert_receive {:app_server_subprocess_send, ^conn, remote_export_line}

    assert {:ok,
            %{
              "id" => remote_export_id,
              "method" => "skills/remote/export",
              "params" => %{"hazelnutId" => "hz_1"}
            }} = Jason.decode(remote_export_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(remote_export_id, %{"id" => "hz_1"})})
    assert {:ok, %{"id" => "hz_1"}} = Task.await(remote_export_task, 200)

    plugin_list_task =
      Task.async(fn ->
        AppServer.plugin_list(conn, cwds: ["/tmp/project"], force_remote_sync: true)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, plugin_list_line}

    assert {:ok,
            %{"id" => plugin_list_id, "method" => "plugin/list", "params" => plugin_list_params}} =
             Jason.decode(plugin_list_line)

    assert plugin_list_params["cwds"] == ["/tmp/project"]
    assert plugin_list_params["forceRemoteSync"] == true

    send(
      conn,
      {:stdout, os_pid, Protocol.encode_response(plugin_list_id, %{"marketplaces" => []})}
    )

    assert {:ok, %{"marketplaces" => []}} = Task.await(plugin_list_task, 200)

    install_task =
      Task.async(fn -> AppServer.plugin_install(conn, "/tmp/market", "demo-plugin") end)

    assert_receive {:app_server_subprocess_send, ^conn, install_line}

    assert {:ok,
            %{
              "id" => install_id,
              "method" => "plugin/install",
              "params" => %{"marketplacePath" => "/tmp/market", "pluginName" => "demo-plugin"}
            }} = Jason.decode(install_line)

    send(
      conn,
      {:stdout, os_pid, Protocol.encode_response(install_id, %{"appsNeedingAuth" => []})}
    )

    assert {:ok, %{"appsNeedingAuth" => []}} = Task.await(install_task, 200)

    uninstall_task = Task.async(fn -> AppServer.plugin_uninstall(conn, "plugin_1") end)
    assert_receive {:app_server_subprocess_send, ^conn, uninstall_line}

    assert {:ok,
            %{
              "id" => uninstall_id,
              "method" => "plugin/uninstall",
              "params" => %{"pluginId" => "plugin_1"}
            }} = Jason.decode(uninstall_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(uninstall_id, %{})})
    assert {:ok, %{}} = Task.await(uninstall_task, 200)

    install_sync_task =
      Task.async(fn ->
        AppServer.plugin_install(conn, "/tmp/market", "demo-plugin", force_remote_sync: true)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, install_sync_line}

    assert {:ok,
            %{
              "id" => install_sync_id,
              "method" => "plugin/install",
              "params" => %{
                "marketplacePath" => "/tmp/market",
                "pluginName" => "demo-plugin",
                "forceRemoteSync" => true
              }
            }} = Jason.decode(install_sync_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(install_sync_id, %{})})
    assert {:ok, %{}} = Task.await(install_sync_task, 200)

    uninstall_sync_task =
      Task.async(fn ->
        AppServer.plugin_uninstall(conn, "plugin_1", force_remote_sync: true)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, uninstall_sync_line}

    assert {:ok,
            %{
              "id" => uninstall_sync_id,
              "method" => "plugin/uninstall",
              "params" => %{"pluginId" => "plugin_1", "forceRemoteSync" => true}
            }} = Jason.decode(uninstall_sync_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(uninstall_sync_id, %{})})
    assert {:ok, %{}} = Task.await(uninstall_sync_task, 200)

    plugin_read_task =
      Task.async(fn -> AppServer.plugin_read(conn, "/tmp/marketplace.json", "demo-plugin") end)

    assert_receive {:app_server_subprocess_send, ^conn, plugin_read_line}

    assert {:ok,
            %{
              "id" => plugin_read_id,
              "method" => "plugin/read",
              "params" => %{
                "marketplacePath" => "/tmp/marketplace.json",
                "pluginName" => "demo-plugin"
              }
            }} = Jason.decode(plugin_read_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(plugin_read_id, %{"plugin" => %{}})})
    assert {:ok, %{"plugin" => %{}}} = Task.await(plugin_read_task, 200)

    experimental_task =
      Task.async(fn -> AppServer.experimental_feature_list(conn, cursor: "cur", limit: 5) end)

    assert_receive {:app_server_subprocess_send, ^conn, experimental_line}

    assert {:ok,
            %{
              "id" => experimental_id,
              "method" => "experimentalFeature/list",
              "params" => %{"cursor" => "cur", "limit" => 5}
            }} = Jason.decode(experimental_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(experimental_id, %{"data" => []})})
    assert {:ok, %{"data" => []}} = Task.await(experimental_task, 200)
  end

  test "request_typed/5 encodes param structs and parses typed responses", %{
    conn: conn,
    os_pid: os_pid
  } do
    task =
      Task.async(fn ->
        AppServer.request_typed(
          conn,
          "plugin/read",
          %Plugin.ReadParams{
            marketplace_path: "/tmp/marketplace.json",
            plugin_name: "demo-plugin"
          },
          Plugin.ReadResponse,
          timeout_ms: 30_000
        )
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok,
            %{
              "id" => req_id,
              "method" => "plugin/read",
              "params" => %{
                "marketplacePath" => "/tmp/marketplace.json",
                "pluginName" => "demo-plugin"
              }
            }} = Jason.decode(request_line)

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(req_id, %{
         "plugin" => %{
           "marketplaceName" => "codex-curated",
           "marketplacePath" => "/tmp/marketplace.json",
           "summary" => %{
             "id" => "demo-plugin@codex-curated",
             "name" => "demo-plugin",
             "source" => %{"type" => "local", "path" => "/tmp/plugins/demo-plugin"},
             "installed" => false,
             "enabled" => false,
             "installPolicy" => "AVAILABLE",
             "authPolicy" => "ON_INSTALL"
           },
           "skills" => [],
           "apps" => [],
           "mcpServers" => []
         }
       })}
    )

    assert {:ok, %Plugin.ReadResponse{plugin: %Plugin.Detail{marketplace_name: "codex-curated"}}} =
             Task.await(task, 200)
  end

  test "request_typed/5 returns adapted parse errors for invalid typed payloads", %{
    conn: conn,
    os_pid: os_pid
  } do
    task =
      Task.async(fn ->
        AppServer.request_typed(
          conn,
          "plugin/list",
          %Plugin.ListParams{},
          Plugin.ListResponse,
          timeout_ms: 30_000
        )
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => req_id, "method" => "plugin/list"}} = Jason.decode(request_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"marketplaces" => "bad"})})

    assert {:error, {:invalid_plugin_list_response, details}} = Task.await(task, 200)
    assert is_binary(details.message)
    assert is_map(details.errors)
    assert is_list(details.issues)
  end

  test "typed plugin wrappers preserve wire parity and return typed structs", %{
    conn: conn,
    os_pid: os_pid
  } do
    plugin_list_task =
      Task.async(fn ->
        AppServer.plugin_list_typed(conn, cwds: ["/tmp/project"], force_remote_sync: true)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, plugin_list_line}

    assert {:ok,
            %{"id" => plugin_list_id, "method" => "plugin/list", "params" => plugin_list_params}} =
             Jason.decode(plugin_list_line)

    assert plugin_list_params["cwds"] == ["/tmp/project"]
    assert plugin_list_params["forceRemoteSync"] == true

    send(
      conn,
      {:stdout, os_pid, Protocol.encode_response(plugin_list_id, %{"marketplaces" => []})}
    )

    assert {:ok, %Plugin.ListResponse{marketplaces: []}} = Task.await(plugin_list_task, 200)

    install_task =
      Task.async(fn ->
        AppServer.plugin_install_typed(conn, "/tmp/market", "demo-plugin",
          force_remote_sync: true
        )
      end)

    assert_receive {:app_server_subprocess_send, ^conn, install_line}

    assert {:ok,
            %{
              "id" => install_id,
              "method" => "plugin/install",
              "params" => %{
                "marketplacePath" => "/tmp/market",
                "pluginName" => "demo-plugin",
                "forceRemoteSync" => true
              }
            }} = Jason.decode(install_line)

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(install_id, %{
         "authPolicy" => "ON_INSTALL",
         "appsNeedingAuth" => []
       })}
    )

    assert {:ok, %Plugin.InstallResponse{auth_policy: :on_install, apps_needing_auth: []}} =
             Task.await(install_task, 200)

    uninstall_task =
      Task.async(fn ->
        AppServer.plugin_uninstall_typed(conn, "plugin_1", force_remote_sync: true)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, uninstall_line}

    assert {:ok,
            %{
              "id" => uninstall_id,
              "method" => "plugin/uninstall",
              "params" => %{"pluginId" => "plugin_1", "forceRemoteSync" => true}
            }} = Jason.decode(uninstall_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(uninstall_id, %{})})
    assert {:ok, %Plugin.UninstallResponse{}} = Task.await(uninstall_task, 200)

    plugin_read_task =
      Task.async(fn ->
        AppServer.plugin_read_typed(conn, "/tmp/marketplace.json", "demo-plugin")
      end)

    assert_receive {:app_server_subprocess_send, ^conn, plugin_read_line}

    assert {:ok,
            %{
              "id" => plugin_read_id,
              "method" => "plugin/read",
              "params" => %{
                "marketplacePath" => "/tmp/marketplace.json",
                "pluginName" => "demo-plugin"
              }
            }} = Jason.decode(plugin_read_line)

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(plugin_read_id, %{
         "plugin" => %{
           "marketplaceName" => "codex-curated",
           "marketplacePath" => "/tmp/marketplace.json",
           "summary" => %{
             "id" => "demo-plugin@codex-curated",
             "name" => "demo-plugin",
             "source" => %{"type" => "local", "path" => "/tmp/plugins/demo-plugin"},
             "installed" => false,
             "enabled" => false,
             "installPolicy" => "AVAILABLE",
             "authPolicy" => "ON_INSTALL"
           },
           "skills" => [],
           "apps" => [],
           "mcpServers" => []
         }
       })}
    )

    assert {:ok, %Plugin.ReadResponse{plugin: %Plugin.Detail{marketplace_name: "codex-curated"}}} =
             Task.await(plugin_read_task, 200)
  end

  test "thread_shell_command/3 encodes request", %{conn: conn, os_pid: os_pid} do
    task =
      Task.async(fn ->
        AppServer.thread_shell_command(conn, "thr_1", "git status --short")
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok,
            %{
              "id" => req_id,
              "method" => "thread/shellCommand",
              "params" => %{"threadId" => "thr_1", "command" => "git status --short"}
            }} = Jason.decode(request_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{})})
    assert {:ok, %{}} = Task.await(task, 200)
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

  test "filesystem wrappers encode current upstream params", %{conn: conn, os_pid: os_pid} do
    read_task = Task.async(fn -> AppServer.fs_read_file(conn, "/tmp/demo.txt") end)
    assert_receive {:app_server_subprocess_send, ^conn, read_line}

    assert {:ok,
            %{
              "id" => read_id,
              "method" => "fs/readFile",
              "params" => %{"path" => "/tmp/demo.txt"}
            }} = Jason.decode(read_line)

    send(
      conn,
      {:stdout, os_pid, Protocol.encode_response(read_id, %{"dataBase64" => "aGVsbG8="})}
    )

    assert {:ok, %{"dataBase64" => "aGVsbG8="}} = Task.await(read_task, 200)

    write_task =
      Task.async(fn -> AppServer.fs_write_file(conn, "/tmp/demo.txt", "aGVsbG8=") end)

    assert_receive {:app_server_subprocess_send, ^conn, write_line}

    assert {:ok,
            %{
              "id" => write_id,
              "method" => "fs/writeFile",
              "params" => %{"path" => "/tmp/demo.txt", "dataBase64" => "aGVsbG8="}
            }} = Jason.decode(write_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(write_id, %{})})
    assert {:ok, %{}} = Task.await(write_task, 200)

    create_task =
      Task.async(fn ->
        AppServer.fs_create_directory(conn, "/tmp/demo/nested", recursive: true)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, create_line}

    assert {:ok,
            %{
              "id" => create_id,
              "method" => "fs/createDirectory",
              "params" => %{"path" => "/tmp/demo/nested", "recursive" => true}
            }} = Jason.decode(create_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(create_id, %{})})
    assert {:ok, %{}} = Task.await(create_task, 200)

    metadata_task = Task.async(fn -> AppServer.fs_get_metadata(conn, "/tmp/demo.txt") end)
    assert_receive {:app_server_subprocess_send, ^conn, metadata_line}

    assert {:ok,
            %{
              "id" => metadata_id,
              "method" => "fs/getMetadata",
              "params" => %{"path" => "/tmp/demo.txt"}
            }} = Jason.decode(metadata_line)

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(metadata_id, %{
         "isDirectory" => false,
         "isFile" => true,
         "createdAtMs" => 1,
         "modifiedAtMs" => 2
       })}
    )

    assert {:ok,
            %{
              "isDirectory" => false,
              "isFile" => true,
              "createdAtMs" => 1,
              "modifiedAtMs" => 2
            }} = Task.await(metadata_task, 200)

    read_directory_task = Task.async(fn -> AppServer.fs_read_directory(conn, "/tmp/demo") end)
    assert_receive {:app_server_subprocess_send, ^conn, read_directory_line}

    assert {:ok,
            %{
              "id" => read_directory_id,
              "method" => "fs/readDirectory",
              "params" => %{"path" => "/tmp/demo"}
            }} = Jason.decode(read_directory_line)

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(read_directory_id, %{
         "entries" => [
           %{"fileName" => "demo.txt", "isDirectory" => false, "isFile" => true}
         ]
       })}
    )

    assert {:ok,
            %{
              "entries" => [%{"fileName" => "demo.txt", "isDirectory" => false, "isFile" => true}]
            }} = Task.await(read_directory_task, 200)

    remove_task =
      Task.async(fn -> AppServer.fs_remove(conn, "/tmp/demo", recursive: true, force: true) end)

    assert_receive {:app_server_subprocess_send, ^conn, remove_line}

    assert {:ok,
            %{
              "id" => remove_id,
              "method" => "fs/remove",
              "params" => %{"path" => "/tmp/demo", "recursive" => true, "force" => true}
            }} = Jason.decode(remove_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(remove_id, %{})})
    assert {:ok, %{}} = Task.await(remove_task, 200)

    copy_task =
      Task.async(fn ->
        AppServer.fs_copy(conn, "/tmp/demo.txt", "/tmp/demo-copy.txt", recursive: false)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, copy_line}

    assert {:ok,
            %{
              "id" => copy_id,
              "method" => "fs/copy",
              "params" => %{
                "sourcePath" => "/tmp/demo.txt",
                "destinationPath" => "/tmp/demo-copy.txt",
                "recursive" => false
              }
            }} = Jason.decode(copy_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(copy_id, %{})})
    assert {:ok, %{}} = Task.await(copy_task, 200)
  end

  test "fuzzy file search session wrappers encode current upstream params", %{
    conn: conn,
    os_pid: os_pid
  } do
    start_task =
      Task.async(fn -> AppServer.fuzzy_file_search_session_start(conn, "sess_1", ["/tmp"]) end)

    assert_receive {:app_server_subprocess_send, ^conn, start_line}

    assert {:ok,
            %{
              "id" => start_id,
              "method" => "fuzzyFileSearch/sessionStart",
              "params" => %{"sessionId" => "sess_1", "roots" => ["/tmp"]}
            }} = Jason.decode(start_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(start_id, %{})})
    assert {:ok, %{}} = Task.await(start_task, 200)

    update_task =
      Task.async(fn -> AppServer.fuzzy_file_search_session_update(conn, "sess_1", "readme") end)

    assert_receive {:app_server_subprocess_send, ^conn, update_line}

    assert {:ok,
            %{
              "id" => update_id,
              "method" => "fuzzyFileSearch/sessionUpdate",
              "params" => %{"sessionId" => "sess_1", "query" => "readme"}
            }} = Jason.decode(update_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(update_id, %{})})
    assert {:ok, %{}} = Task.await(update_task, 200)

    stop_task = Task.async(fn -> AppServer.fuzzy_file_search_session_stop(conn, "sess_1") end)
    assert_receive {:app_server_subprocess_send, ^conn, stop_line}

    assert {:ok,
            %{
              "id" => stop_id,
              "method" => "fuzzyFileSearch/sessionStop",
              "params" => %{"sessionId" => "sess_1"}
            }} = Jason.decode(stop_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(stop_id, %{})})
    assert {:ok, %{}} = Task.await(stop_task, 200)
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

  test "config and external-agent wrappers encode reload and import params", %{
    conn: conn,
    os_pid: os_pid
  } do
    batch_task =
      Task.async(fn ->
        AppServer.config_batch_write(
          conn,
          [%{key_path: "apps.demo.enabled", value: true}],
          reload_user_config: true
        )
      end)

    assert_receive {:app_server_subprocess_send, ^conn, batch_line}

    assert {:ok, %{"id" => batch_id, "method" => "config/batchWrite", "params" => batch_params}} =
             Jason.decode(batch_line)

    assert batch_params["reloadUserConfig"] == true

    send(conn, {:stdout, os_pid, Protocol.encode_response(batch_id, %{"status" => "ok"})})
    assert {:ok, %{"status" => "ok"}} = Task.await(batch_task, 200)

    detect_task =
      Task.async(fn ->
        AppServer.external_agent_config_detect(conn, include_home: true, cwds: ["/tmp/project"])
      end)

    assert_receive {:app_server_subprocess_send, ^conn, detect_line}

    assert {:ok,
            %{
              "id" => detect_id,
              "method" => "externalAgentConfig/detect",
              "params" => %{"includeHome" => true, "cwds" => ["/tmp/project"]}
            }} = Jason.decode(detect_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(detect_id, %{"items" => []})})
    assert {:ok, %{"items" => []}} = Task.await(detect_task, 200)

    import_task =
      Task.async(fn ->
        AppServer.external_agent_config_import(conn, [
          %{"itemType" => "CONFIG", "description" => "Import", "cwd" => "/tmp/project"}
        ])
      end)

    assert_receive {:app_server_subprocess_send, ^conn, import_line}

    assert {:ok,
            %{
              "id" => import_id,
              "method" => "externalAgentConfig/import",
              "params" => %{
                "migrationItems" => [
                  %{"itemType" => "CONFIG", "description" => "Import", "cwd" => "/tmp/project"}
                ]
              }
            }} = Jason.decode(import_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(import_id, %{})})
    assert {:ok, %{}} = Task.await(import_task, 200)
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

    assert {:ok, %{"id" => req_id, "method" => "command/exec/write", "params" => params}} =
             Jason.decode(request_line)

    assert params["processId"] == "proc_1"
    assert params["deltaBase64"] == Base.encode64("y\n")
    refute Map.has_key?(params, "threadId")
    refute Map.has_key?(params, "yieldTimeMs")

    send(conn, {:stdout, os_pid, Protocol.encode_response(req_id, %{"status" => "ok"})})

    assert {:ok, %{"status" => "ok"}} = Task.await(task, 200)
  end

  test "command exec wrappers encode streaming fields and follow-up requests", %{
    conn: conn,
    os_pid: os_pid
  } do
    exec_task =
      Task.async(fn ->
        AppServer.command_exec(conn, ["bash", "-lc", "echo hi"],
          process_id: "proc_1",
          tty: true,
          stream_stdin: true,
          stream_stdout_stderr: true,
          output_bytes_cap: 4_096,
          disable_output_cap: false,
          disable_timeout: true,
          cwd: "/tmp",
          env: %{"FOO" => "bar", "DROP" => nil},
          size: %{rows: 24, cols: 80},
          sandbox_policy: %{type: :workspace_write, writable_roots: ["/tmp"]}
        )
      end)

    assert_receive {:app_server_subprocess_send, ^conn, exec_line}

    assert {:ok, %{"id" => exec_id, "method" => "command/exec", "params" => exec_params}} =
             Jason.decode(exec_line)

    assert exec_params["processId"] == "proc_1"
    assert exec_params["tty"] == true
    assert exec_params["streamStdin"] == true
    assert exec_params["streamStdoutStderr"] == true
    assert exec_params["outputBytesCap"] == 4096
    assert exec_params["disableTimeout"] == true
    assert exec_params["cwd"] == "/tmp"
    assert exec_params["env"] == %{"FOO" => "bar", "DROP" => nil}
    assert exec_params["size"] == %{"rows" => 24, "cols" => 80}

    assert exec_params["sandboxPolicy"] == %{
             "type" => "workspaceWrite",
             "writableRoots" => ["/tmp"]
           }

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(exec_id, %{"exitCode" => 0, "stdout" => "", "stderr" => ""})}
    )

    assert {:ok, %{"exitCode" => 0}} = Task.await(exec_task, 200)

    write_task =
      Task.async(fn ->
        AppServer.command_exec_write(conn, "proc_1", delta: "abc", close_stdin: true)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, write_line}

    assert {:ok,
            %{
              "id" => write_id,
              "method" => "command/exec/write",
              "params" => %{
                "processId" => "proc_1",
                "deltaBase64" => write_delta,
                "closeStdin" => true
              }
            }} = Jason.decode(write_line)

    assert write_delta == Base.encode64("abc")
    send(conn, {:stdout, os_pid, Protocol.encode_response(write_id, %{})})
    assert {:ok, %{}} = Task.await(write_task, 200)

    terminate_task = Task.async(fn -> AppServer.command_exec_terminate(conn, "proc_1") end)
    assert_receive {:app_server_subprocess_send, ^conn, terminate_line}

    assert {:ok,
            %{
              "id" => terminate_id,
              "method" => "command/exec/terminate",
              "params" => %{"processId" => "proc_1"}
            }} = Jason.decode(terminate_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(terminate_id, %{})})
    assert {:ok, %{}} = Task.await(terminate_task, 200)

    resize_task =
      Task.async(fn -> AppServer.command_exec_resize(conn, "proc_1", rows: 40, cols: 120) end)

    assert_receive {:app_server_subprocess_send, ^conn, resize_line}

    assert {:ok,
            %{
              "id" => resize_id,
              "method" => "command/exec/resize",
              "params" => %{"processId" => "proc_1", "size" => %{"rows" => 40, "cols" => 120}}
            }} = Jason.decode(resize_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(resize_id, %{})})
    assert {:ok, %{}} = Task.await(resize_task, 200)
  end

  test "account login_start encodes apiKey, chatgpt, and chatgptAuthTokens variants", %{
    conn: conn,
    os_pid: os_pid
  } do
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

    task3 =
      Task.async(fn ->
        AppServer.Account.login_start(conn, %{
          "type" => "chatgptAuthTokens",
          "accessToken" => "token",
          "chatgptAccountId" => "acct_1",
          "chatgptPlanType" => "pro"
        })
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line3}

    assert {:ok, %{"id" => req_id3, "method" => "account/login/start", "params" => params3}} =
             Jason.decode(request_line3)

    assert params3 == %{
             "type" => "chatgptAuthTokens",
             "accessToken" => "token",
             "chatgptAccountId" => "acct_1",
             "chatgptPlanType" => "pro"
           }

    send(
      conn,
      {:stdout, os_pid, Protocol.encode_response(req_id3, %{"type" => "chatgptAuthTokens"})}
    )

    assert {:ok, %{"type" => "chatgptAuthTokens"}} = Task.await(task3, 200)
  end

  test "model, realtime, and windows sandbox wrappers encode current params", %{
    conn: conn,
    os_pid: os_pid
  } do
    model_task = Task.async(fn -> AppServer.model_list(conn, include_hidden: true, limit: 3) end)
    assert_receive {:app_server_subprocess_send, ^conn, model_line}

    assert {:ok,
            %{
              "id" => model_id,
              "method" => "model/list",
              "params" => %{"includeHidden" => true, "limit" => 3}
            }} = Jason.decode(model_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(model_id, %{"data" => []})})
    assert {:ok, %{"data" => []}} = Task.await(model_task, 200)

    realtime_start_task =
      Task.async(fn ->
        AppServer.thread_realtime_start(conn, "thr_1", "Listen", session_id: "rt_1")
      end)

    assert_receive {:app_server_subprocess_send, ^conn, realtime_start_line}

    assert {:ok,
            %{
              "id" => realtime_start_id,
              "method" => "thread/realtime/start",
              "params" => %{"threadId" => "thr_1", "prompt" => "Listen", "sessionId" => "rt_1"}
            }} = Jason.decode(realtime_start_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(realtime_start_id, %{})})
    assert {:ok, %{}} = Task.await(realtime_start_task, 200)

    realtime_audio_task =
      Task.async(fn ->
        AppServer.thread_realtime_append_audio(conn, "thr_1",
          data: "YmFzZTY0",
          sample_rate: 24_000,
          num_channels: 1,
          samples_per_channel: 512
        )
      end)

    assert_receive {:app_server_subprocess_send, ^conn, realtime_audio_line}

    assert {:ok,
            %{
              "id" => realtime_audio_id,
              "method" => "thread/realtime/appendAudio",
              "params" => %{
                "threadId" => "thr_1",
                "audio" => %{
                  "data" => "YmFzZTY0",
                  "sampleRate" => 24_000,
                  "numChannels" => 1,
                  "samplesPerChannel" => 512
                }
              }
            }} = Jason.decode(realtime_audio_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(realtime_audio_id, %{})})
    assert {:ok, %{}} = Task.await(realtime_audio_task, 200)

    realtime_text_task =
      Task.async(fn -> AppServer.thread_realtime_append_text(conn, "thr_1", "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, realtime_text_line}

    assert {:ok,
            %{
              "id" => realtime_text_id,
              "method" => "thread/realtime/appendText",
              "params" => %{"threadId" => "thr_1", "text" => "hello"}
            }} = Jason.decode(realtime_text_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(realtime_text_id, %{})})
    assert {:ok, %{}} = Task.await(realtime_text_task, 200)

    realtime_stop_task = Task.async(fn -> AppServer.thread_realtime_stop(conn, "thr_1") end)
    assert_receive {:app_server_subprocess_send, ^conn, realtime_stop_line}

    assert {:ok,
            %{
              "id" => realtime_stop_id,
              "method" => "thread/realtime/stop",
              "params" => %{"threadId" => "thr_1"}
            }} = Jason.decode(realtime_stop_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(realtime_stop_id, %{})})
    assert {:ok, %{}} = Task.await(realtime_stop_task, 200)

    windows_task =
      Task.async(fn -> AppServer.windows_sandbox_setup_start(conn, :unelevated, cwd: "/tmp") end)

    assert_receive {:app_server_subprocess_send, ^conn, windows_line}

    assert {:ok,
            %{
              "id" => windows_id,
              "method" => "windowsSandbox/setupStart",
              "params" => %{"mode" => "unelevated", "cwd" => "/tmp"}
            }} = Jason.decode(windows_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(windows_id, %{"started" => true})})
    assert {:ok, %{"started" => true}} = Task.await(windows_task, 200)
  end

  describe "thread_compact/2" do
    test "encodes thread/compact/start requests", %{conn: conn, os_pid: os_pid} do
      task =
        Task.async(fn ->
          AppServer.thread_compact(conn, "thr_123")
        end)

      assert_receive {:app_server_subprocess_send, ^conn, request_line}

      assert {:ok,
              %{
                "id" => req_id,
                "method" => "thread/compact/start",
                "params" => %{"threadId" => "thr_123"}
              }} = Jason.decode(request_line)

      send(
        conn,
        {:stdout, os_pid, Protocol.encode_response(req_id, %{"status" => "started"})}
      )

      assert {:ok, %{"status" => "started"}} = Task.await(task, 200)
    end
  end
end

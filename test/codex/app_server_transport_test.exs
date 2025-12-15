defmodule Codex.AppServerTransportTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer.Connection
  alias Codex.AppServer.Protocol
  alias Codex.Items
  alias Codex.Options
  alias Codex.TestSupport.AppServerSubprocess
  alias Codex.Thread
  alias Codex.Thread.Options, as: ThreadOptions

  defmodule ExecpolicyApprovalHook do
    @behaviour Codex.Approvals.Hook

    @impl true
    def review_tool(_event, _context, _opts), do: :allow

    @impl true
    def review_command(_event, _context, _opts) do
      {:allow, execpolicy_amendment: ["npm", "install"]}
    end
  end

  defmodule AllowApprovalHook do
    @behaviour Codex.Approvals.Hook

    @impl true
    def review_tool(_event, _context, _opts), do: :allow

    @impl true
    def review_command(_event, _context, _opts), do: :allow

    @impl true
    def review_file(_event, _context, _opts), do: :allow
  end

  defmodule DenyApprovalHook do
    @behaviour Codex.Approvals.Hook

    @impl true
    def review_tool(_event, _context, _opts), do: :allow

    @impl true
    def review_command(_event, _context, _opts), do: {:deny, "no"}
  end

  defmodule TimeoutApprovalHook do
    @behaviour Codex.Approvals.Hook

    @impl true
    def review_tool(_event, _context, _opts), do: :allow

    @impl true
    def review_command(_event, _context, _opts), do: {:async, make_ref()}

    @impl true
    def await(_ref, _timeout), do: {:error, :timeout}
  end

  test "Thread.run_turn/3 via app-server transport collects notifications and returns Turn.Result" do
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

    {:ok, thread_opts} =
      ThreadOptions.new(%{transport: {:app_server, conn}, working_directory: "/tmp"})

    thread = Thread.build(codex_opts, thread_opts)

    task = Task.async(fn -> Thread.run_turn(thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start"}} =
             Jason.decode(thread_start_line)

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})}
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok,
            %{"id" => turn_start_id, "method" => "turn/start", "params" => turn_start_params}} =
             Jason.decode(turn_start_line)

    assert turn_start_params["threadId"] == "thr_1"

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(turn_start_id, %{
         "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
       })}
    )

    notifications = [
      Protocol.encode_notification("turn/started", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "inProgress", "items" => [], "error" => nil}
      }),
      Protocol.encode_notification("item/agentMessage/delta", %{
        "threadId" => "thr_1",
        "turnId" => "turn_1",
        "itemId" => "msg_1",
        "delta" => "hi"
      }),
      Protocol.encode_notification("item/completed", %{
        "threadId" => "thr_1",
        "turnId" => "turn_1",
        "item" => %{"type" => "agentMessage", "id" => "msg_1", "text" => "hi"}
      }),
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ]

    send(conn, {:stdout, os_pid, notifications})

    assert {:ok, result} = Task.await(task, 500)
    assert result.thread.thread_id == "thr_1"
    assert %Items.AgentMessage{text: "hi"} = result.final_response
  end

  test "app-server transport auto-responds to command approvals using approval_hook" do
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

    {:ok, thread_opts} =
      ThreadOptions.new(%{
        transport: {:app_server, conn},
        working_directory: "/tmp",
        approval_hook: ExecpolicyApprovalHook
      })

    thread = Thread.build(codex_opts, thread_opts)

    task = Task.async(fn -> Thread.run_turn(thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start"}} =
             Jason.decode(thread_start_line)

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})}
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(turn_start_id, %{
         "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
       })}
    )

    approval_request_params = %{
      "threadId" => "thr_1",
      "turnId" => "turn_1",
      "itemId" => "item_1",
      "reason" => "needs approval",
      "proposedExecpolicyAmendment" => ["npm", "install"]
    }

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_request(
         7,
         "item/commandExecution/requestApproval",
         approval_request_params
       )}
    )

    assert_receive {:app_server_subprocess_send, ^conn, approval_response_line}, 200

    assert {:ok, %{"id" => 7, "result" => %{"decision" => decision}}} =
             Jason.decode(approval_response_line)

    assert %{
             "acceptWithExecpolicyAmendment" => %{
               "execpolicyAmendment" => ["npm", "install"]
             }
           } = decision

    notifications = [
      Protocol.encode_notification("turn/started", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "inProgress", "items" => [], "error" => nil}
      }),
      Protocol.encode_notification("item/agentMessage/delta", %{
        "threadId" => "thr_1",
        "turnId" => "turn_1",
        "itemId" => "msg_1",
        "delta" => "ok"
      }),
      Protocol.encode_notification("item/completed", %{
        "threadId" => "thr_1",
        "turnId" => "turn_1",
        "item" => %{"type" => "agentMessage", "id" => "msg_1", "text" => "ok"}
      }),
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ]

    send(conn, {:stdout, os_pid, notifications})

    assert {:ok, _result} = Task.await(task, 500)
  end

  test "app-server transport auto-responds to file change approvals using approval_hook" do
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

    {:ok, thread_opts} =
      ThreadOptions.new(%{
        transport: {:app_server, conn},
        working_directory: "/tmp",
        approval_hook: AllowApprovalHook
      })

    thread = Thread.build(codex_opts, thread_opts)

    task = Task.async(fn -> Thread.run_turn(thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start"}} =
             Jason.decode(thread_start_line)

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})}
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(turn_start_id, %{
         "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
       })}
    )

    approval_request_params = %{
      "threadId" => "thr_1",
      "turnId" => "turn_1",
      "itemId" => "item_1",
      "reason" => "needs approval",
      "grantRoot" => "/tmp"
    }

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_request(9, "item/fileChange/requestApproval", approval_request_params)}
    )

    assert_receive {:app_server_subprocess_send, ^conn, approval_response_line}, 200

    assert {:ok, %{"id" => 9, "result" => %{"decision" => "accept"}}} =
             Jason.decode(approval_response_line)

    send(
      conn,
      {:stdout, os_pid,
       [
         Protocol.encode_notification("turn/completed", %{
           "threadId" => "thr_1",
           "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
         })
       ]}
    )

    assert {:ok, _result} = Task.await(task, 500)
  end

  test "app-server transport declines when approval_hook times out" do
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

    {:ok, thread_opts} =
      ThreadOptions.new(%{
        transport: {:app_server, conn},
        working_directory: "/tmp",
        approval_hook: TimeoutApprovalHook
      })

    thread = Thread.build(codex_opts, thread_opts)

    task = Task.async(fn -> Thread.run_turn(thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start"}} =
             Jason.decode(thread_start_line)

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})}
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(turn_start_id, %{
         "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
       })}
    )

    approval_request_params = %{
      "threadId" => "thr_1",
      "turnId" => "turn_1",
      "itemId" => "item_1"
    }

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_request(
         13,
         "item/commandExecution/requestApproval",
         approval_request_params
       )}
    )

    assert_receive {:app_server_subprocess_send, ^conn, approval_response_line}, 200

    assert {:ok, %{"id" => 13, "result" => %{"decision" => "decline"}}} =
             Jason.decode(approval_response_line)

    send(
      conn,
      {:stdout, os_pid,
       [
         Protocol.encode_notification("turn/completed", %{
           "threadId" => "thr_1",
           "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
         })
       ]}
    )

    assert {:ok, _result} = Task.await(task, 500)
  end
end

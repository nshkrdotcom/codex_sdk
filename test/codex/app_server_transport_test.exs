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

  defmodule GrantRootApprovalHook do
    @behaviour Codex.Approvals.Hook

    @impl true
    def review_tool(_event, _context, _opts), do: :allow

    @impl true
    def review_command(_event, _context, _opts), do: :allow

    @impl true
    def review_file(_event, _context, _opts), do: {:allow, grant_root: "/tmp"}
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

  test "Thread.run/3 via app-server accepts multimodal input blocks" do
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

    input = [
      %{type: :text, text: "hello"},
      %{type: :local_image, path: "/tmp/image.png"}
    ]

    task = Task.async(fn -> Thread.run(thread, input) end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start"}} =
             Jason.decode(thread_start_line)

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})}
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start", "params" => params}} =
             Jason.decode(turn_start_line)

    assert [
             %{"type" => "text", "text" => "hello"},
             %{"type" => "localImage", "path" => "/tmp/image.png"}
           ] = params["input"]

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
    assert %Items.AgentMessage{text: "hi"} = result.final_response
  end

  test "Thread.run_turn/3 resets threads on structured /new input via app-server" do
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

    thread =
      Thread.build(codex_opts, thread_opts,
        thread_id: "thr_old",
        labels: %{"topic" => "legacy"}
      )

    input = [
      %{type: :text, text: "/new"},
      %{type: :local_image, path: "/tmp/example.png"}
    ]

    task = Task.async(fn -> Thread.run_turn(thread, input) end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start"}} =
             Jason.decode(thread_start_line)

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_new"}})}
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok,
            %{"id" => turn_start_id, "method" => "turn/start", "params" => turn_start_params}} =
             Jason.decode(turn_start_line)

    assert turn_start_params["threadId"] == "thr_new"

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(turn_start_id, %{
         "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
       })}
    )

    notifications = [
      Protocol.encode_notification("turn/started", %{
        "threadId" => "thr_new",
        "turn" => %{"id" => "turn_1", "status" => "inProgress", "items" => [], "error" => nil}
      }),
      Protocol.encode_notification("item/agentMessage/delta", %{
        "threadId" => "thr_new",
        "turnId" => "turn_1",
        "itemId" => "msg_1",
        "delta" => "hi"
      }),
      Protocol.encode_notification("item/completed", %{
        "threadId" => "thr_new",
        "turnId" => "turn_1",
        "item" => %{"type" => "agentMessage", "id" => "msg_1", "text" => "hi"}
      }),
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_new",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ]

    send(conn, {:stdout, os_pid, notifications})

    assert {:ok, result} = Task.await(task, 500)
    assert result.thread.thread_id == "thr_new"
    assert %Items.AgentMessage{text: "hi"} = result.final_response
  end

  test "Thread.run_streamed/3 via app-server accepts multimodal input blocks" do
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

    input = [
      %{type: :text, text: "hello"},
      %{type: :local_image, path: "/tmp/image.png"}
    ]

    {:ok, stream} = Thread.run_streamed(thread, input)
    task = Task.async(fn -> stream |> Codex.RunResultStreaming.raw_events() |> Enum.to_list() end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start"}} =
             Jason.decode(thread_start_line)

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})}
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start", "params" => params}} =
             Jason.decode(turn_start_line)

    assert [
             %{"type" => "text", "text" => "hello"},
             %{"type" => "localImage", "path" => "/tmp/image.png"}
           ] = params["input"]

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

    assert events = Task.await(task, 500)
    assert Enum.any?(events, &match?(%Codex.Events.TurnCompleted{}, &1))
  end

  test "app-server thread start includes model/provider/config/instructions flags" do
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
        model: "gpt-5.1-codex-mini",
        model_provider: "openai",
        config: %{"features.remote_models" => true},
        base_instructions: "base",
        developer_instructions: "dev",
        experimental_raw_events: true
      })

    thread = Thread.build(codex_opts, thread_opts)

    task = Task.async(fn -> Thread.run_turn(thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start", "params" => params}} =
             Jason.decode(thread_start_line)

    assert params["model"] == "gpt-5.1-codex-mini"
    assert params["modelProvider"] == "openai"
    assert %{"features.remote_models" => true} = params["config"]
    assert params["config"]["model_reasoning_effort"] == "medium"
    assert params["baseInstructions"] == "base"
    assert params["developerInstructions"] == "dev"
    assert params["experimentalRawEvents"] == true

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

  test "app-server transport applies codex defaults for model and reasoning effort" do
    bash = System.find_executable("bash") || "/bin/bash"

    {:ok, codex_opts} =
      Options.new(%{
        api_key: "test",
        codex_path_override: bash,
        model: "gpt-5.1-codex-mini",
        reasoning_effort: :high
      })

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

    {:ok, thread_opts} = ThreadOptions.new(%{transport: {:app_server, conn}})
    thread = Thread.build(codex_opts, thread_opts)

    task = Task.async(fn -> Thread.run_turn(thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start", "params" => params}} =
             Jason.decode(thread_start_line)

    assert params["model"] == "gpt-5.1-codex-mini"
    assert %{"model_reasoning_effort" => "high"} = params["config"]
    refute Map.has_key?(params, "sandbox")

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

  test "app-server turn start includes sandbox policy overrides" do
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
        sandbox_policy: %{
          type: :workspace_write,
          writable_roots: ["/tmp"],
          network_access: true
        }
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

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start", "params" => params}} =
             Jason.decode(turn_start_line)

    assert %{
             "type" => "workspaceWrite",
             "writableRoots" => ["/tmp"],
             "networkAccess" => true
           } = params["sandboxPolicy"]

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_response(turn_start_id, %{
         "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
       })}
    )

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

  test "app-server transport supports grant-root approvals" do
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
        approval_hook: GrantRootApprovalHook
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

    assert {:ok, %{"id" => 9, "result" => %{"decision" => "acceptForSession"}}} =
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

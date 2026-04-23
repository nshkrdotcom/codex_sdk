defmodule Codex.AppServerTransportTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer.Connection
  alias Codex.AppServer.Protocol
  alias Codex.Items
  alias Codex.Options
  alias Codex.Protocol.RequestPermissions
  alias Codex.TestSupport.AppServerSubprocess
  alias Codex.Thread
  alias Codex.Thread.Options, as: ThreadOptions

  setup do
    harness =
      AppServerSubprocess.new!(owner: self())
      |> AppServerSubprocess.put_current!()

    on_exit(fn -> AppServerSubprocess.cleanup(harness) end)
    :ok
  end

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

  defmodule AllowPermissionsApprovalHook do
    @behaviour Codex.Approvals.Hook

    @impl true
    def review_tool(_event, _context, _opts), do: :allow

    @impl true
    def review_command(_event, _context, _opts), do: :allow

    @impl true
    def review_file(_event, _context, _opts), do: :allow

    @impl true
    def review_permissions(_event, _context, _opts), do: :allow
  end

  defmodule SessionPermissionsApprovalHook do
    @behaviour Codex.Approvals.Hook

    @impl true
    def review_tool(_event, _context, _opts), do: :allow

    @impl true
    def review_command(_event, _context, _opts), do: :allow

    @impl true
    def review_file(_event, _context, _opts), do: :allow

    @impl true
    def review_permissions(_event, _context, _opts) do
      {:allow,
       permissions: %{
         network: %{enabled: true},
         file_system: %{write: ["/tmp/project", "/tmp/ignored"]}
       },
       scope: :session}
    end
  end

  defmodule DenyPermissionsApprovalHook do
    @behaviour Codex.Approvals.Hook

    @impl true
    def review_tool(_event, _context, _opts), do: :allow

    @impl true
    def review_command(_event, _context, _opts), do: :allow

    @impl true
    def review_file(_event, _context, _opts), do: :allow

    @impl true
    def review_permissions(_event, _context, _opts), do: {:deny, "no"}
  end

  defmodule DenyApprovalHook do
    @behaviour Codex.Approvals.Hook

    @impl true
    def review_tool(_event, _context, _opts), do: :allow

    @impl true
    def review_command(_event, _context, _opts), do: {:deny, "no"}
  end

  defmodule CaptureCommandApprovalHook do
    @behaviour Codex.Approvals.Hook

    @impl true
    def review_tool(_event, _context, _opts), do: :allow

    @impl true
    def review_command(event, context, _opts) do
      send(context.metadata.test_pid, {:captured_command_approval, event})
      {:deny, "no"}
    end
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
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        experimental_api: true,
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    {:ok, thread_opts} =
      ThreadOptions.new(%{transport: {:app_server, conn}, working_directory: "/tmp"})

    thread = Thread.build(codex_opts, thread_opts)

    task = Task.async(fn -> Thread.run_turn(thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start"}} =
             Jason.decode(thread_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok,
            %{"id" => turn_start_id, "method" => "turn/start", "params" => turn_start_params}} =
             Jason.decode(turn_start_line)

    assert turn_start_params["threadId"] == "thr_1"

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
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

    AppServerSubprocess.send_stdout(notifications)

    assert {:ok, result} = Task.await(task, 500)
    assert result.thread.thread_id == "thr_1"
    assert %Items.AgentMessage{text: "hi"} = result.final_response
  end

  test "Thread.run_turn/3 via app-server transport returns turn failures as errors" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        experimental_api: true,
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    {:ok, thread_opts} =
      ThreadOptions.new(%{transport: {:app_server, conn}, working_directory: "/tmp"})

    thread = Thread.build(codex_opts, thread_opts)

    task = Task.async(fn -> Thread.run_turn(thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start"}} =
             Jason.decode(thread_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok,
            %{"id" => turn_start_id, "method" => "turn/start", "params" => turn_start_params}} =
             Jason.decode(turn_start_line)

    assert turn_start_params["threadId"] == "thr_1"

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    AppServerSubprocess.send_stdout([
      Protocol.encode_notification("error", %{
        "message" => "boom",
        "threadId" => "thr_1",
        "turnId" => "turn_1"
      }),
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{
          "id" => "turn_1",
          "status" => "failed",
          "items" => [],
          "error" => %{"message" => "boom"}
        }
      })
    ])

    assert {:error, {:turn_failed, _}} = Task.await(task, 500)
  end

  test "app-server transport emits request user input events" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    {:ok, thread_opts} =
      ThreadOptions.new(%{transport: {:app_server, conn}, working_directory: "/tmp"})

    thread = Thread.build(codex_opts, thread_opts)

    task = Task.async(fn -> Thread.run_turn(thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start"}} =
             Jason.decode(thread_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    request_params = %{
      "threadId" => "thr_1",
      "turnId" => "turn_1",
      "itemId" => "item_1",
      "questions" => [
        %{
          "id" => "q1",
          "header" => "Pick one",
          "question" => "Which?",
          "isOther" => true,
          "isSecret" => true,
          "options" => [%{"label" => "A", "description" => "Option A"}]
        }
      ]
    }

    AppServerSubprocess.send_stdout(
      Protocol.encode_request(5, "item/tool/requestUserInput", request_params)
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

    AppServerSubprocess.send_stdout(notifications)

    assert {:ok, result} = Task.await(task, 500)

    assert Enum.any?(result.events, fn
             %Codex.Events.RequestUserInput{
               id: 5,
               thread_id: "thr_1",
               turn_id: "turn_1",
               item_id: "item_1",
               questions: [
                 %Codex.Protocol.RequestUserInput.Question{
                   id: "q1",
                   is_other: true,
                   is_secret: true
                 }
               ]
             } ->
               true

             _ ->
               false
           end)
  end

  test "app-server transport emits typed request events for current upstream request methods" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    {:ok, thread_opts} =
      ThreadOptions.new(%{transport: {:app_server, conn}, working_directory: "/tmp"})

    thread = Thread.build(codex_opts, thread_opts)

    task = Task.async(fn -> Thread.run_turn(thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start"}} =
             Jason.decode(thread_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    ignored_tool_call = %{
      "threadId" => "thr_other",
      "turnId" => "turn_1",
      "callId" => "call_ignored",
      "tool" => "echo",
      "arguments" => %{"text" => "ignore me"}
    }

    dynamic_tool_call = %{
      "threadId" => "thr_1",
      "turnId" => "turn_1",
      "callId" => "call_1",
      "tool" => "echo",
      "arguments" => %{"text" => "hello"}
    }

    elicitation_request = %{
      "threadId" => "thr_1",
      "turnId" => "turn_1",
      "serverName" => "filesystem",
      "mode" => "form",
      "message" => "Need a root path",
      "requestedSchema" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "title" => "Path"}
        },
        "required" => ["path"]
      }
    }

    permissions_request = %{
      "threadId" => "thr_1",
      "turnId" => "turn_1",
      "itemId" => "perm_1",
      "reason" => "Need additional permissions",
      "permissions" => %{
        "network" => %{"enabled" => true},
        "fileSystem" => %{
          "read" => ["/tmp/readable"],
          "write" => ["/tmp"]
        }
      }
    }

    command_approval_request = %{
      "threadId" => "thr_1",
      "turnId" => "turn_1",
      "itemId" => "cmd_1",
      "approvalId" => "approval_1",
      "reason" => "Need network access",
      "command" => "curl https://example.com",
      "cwd" => "/tmp/project",
      "commandActions" => [%{"type" => "search", "command" => "curl", "path" => nil}],
      "networkApprovalContext" => %{"host" => "example.com", "protocol" => "https"},
      "additionalPermissions" => %{
        "network" => %{"enabled" => true},
        "fileSystem" => %{"write" => ["/tmp/project"]},
        "macos" => %{"accessibility" => true}
      },
      "skillMetadata" => %{"pathToSkillsMd" => "/tmp/project/SKILL.md"},
      "proposedExecpolicyAmendment" => ["curl", "https://example.com"],
      "proposedNetworkPolicyAmendments" => [%{"host" => "example.com", "action" => "allow"}],
      "availableDecisions" => ["accept", %{"applyNetworkPolicyAmendment" => %{}}]
    }

    file_approval_request = %{
      "threadId" => "thr_1",
      "turnId" => "turn_1",
      "itemId" => "file_1",
      "reason" => "Need extra write access",
      "grantRoot" => "/tmp/project"
    }

    auth_refresh_request = %{
      "reason" => "unauthorized",
      "previousAccountId" => "acct_1"
    }

    AppServerSubprocess.send_stdout([
      Protocol.encode_request(
        5,
        "item/commandExecution/requestApproval",
        command_approval_request
      ),
      Protocol.encode_request(6, "item/fileChange/requestApproval", file_approval_request),
      Protocol.encode_request(7, "item/tool/call", ignored_tool_call),
      Protocol.encode_request(8, "item/tool/call", dynamic_tool_call),
      Protocol.encode_request(9, "mcpServer/elicitation/request", elicitation_request),
      Protocol.encode_request(
        10,
        "item/permissions/requestApproval",
        permissions_request
      ),
      Protocol.encode_request(
        11,
        "account/chatgptAuthTokens/refresh",
        auth_refresh_request
      )
    ])

    notifications = [
      Protocol.encode_notification("turn/started", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "inProgress", "items" => [], "error" => nil}
      }),
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ]

    AppServerSubprocess.send_stdout(notifications)

    assert {:ok, result} = Task.await(task, 500)

    assert Enum.any?(result.events, fn
             %Codex.Events.CommandApprovalRequested{
               id: 5,
               thread_id: "thr_1",
               turn_id: "turn_1",
               item_id: "cmd_1",
               approval_id: "approval_1",
               reason: "Need network access",
               command: "curl https://example.com",
               cwd: "/tmp/project",
               command_actions: [%{"type" => "search", "command" => "curl", "path" => nil}],
               network_approval_context: %{"host" => "example.com", "protocol" => "https"},
               additional_permissions: %RequestPermissions.RequestPermissionProfile{
                 network: %RequestPermissions.AdditionalNetworkPermissions{enabled: true},
                 file_system: %RequestPermissions.AdditionalFileSystemPermissions{
                   write: ["/tmp/project"]
                 },
                 macos: %RequestPermissions.AdditionalMacOsPermissions{
                   accessibility: true
                 }
               },
               skill_metadata: %{"pathToSkillsMd" => "/tmp/project/SKILL.md"},
               proposed_execpolicy_amendment: ["curl", "https://example.com"],
               proposed_network_policy_amendments: [
                 %{"host" => "example.com", "action" => "allow"}
               ],
               available_decisions: ["accept", %{"applyNetworkPolicyAmendment" => %{}}]
             } ->
               true

             _ ->
               false
           end)

    assert Enum.any?(result.events, fn
             %Codex.Events.FileApprovalRequested{
               id: 6,
               thread_id: "thr_1",
               turn_id: "turn_1",
               item_id: "file_1",
               reason: "Need extra write access",
               grant_root: "/tmp/project"
             } ->
               true

             _ ->
               false
           end)

    assert Enum.any?(result.events, fn
             %Codex.Events.DynamicToolCallRequested{
               id: 8,
               thread_id: "thr_1",
               turn_id: "turn_1",
               call_id: "call_1",
               tool_name: "echo",
               arguments: %{"text" => "hello"}
             } ->
               true

             _ ->
               false
           end)

    assert Enum.any?(result.events, fn
             %Codex.Events.McpElicitationRequested{
               id: 9,
               thread_id: "thr_1",
               turn_id: "turn_1",
               server_name: "filesystem",
               request_mode: "form",
               message: "Need a root path"
             } ->
               true

             _ ->
               false
           end)

    assert Enum.any?(result.events, fn
             %Codex.Events.PermissionsApprovalRequested{
               id: 10,
               thread_id: "thr_1",
               turn_id: "turn_1",
               item_id: "perm_1",
               reason: "Need additional permissions",
               permissions: %RequestPermissions.RequestPermissionProfile{
                 network: %RequestPermissions.AdditionalNetworkPermissions{enabled: true},
                 file_system: %RequestPermissions.AdditionalFileSystemPermissions{
                   read: ["/tmp/readable"],
                   write: ["/tmp"]
                 }
               }
             } ->
               true

             _ ->
               false
           end)

    assert Enum.any?(result.events, fn
             %Codex.Events.ChatgptAuthTokensRefreshRequested{
               id: 11,
               reason: "unauthorized",
               previous_account_id: "acct_1"
             } ->
               true

             _ ->
               false
           end)

    refute Enum.any?(result.events, fn
             %Codex.Events.DynamicToolCallRequested{call_id: "call_ignored"} -> true
             _ -> false
           end)
  end

  test "app-server transport forwards approvals reviewer through thread start and resume params" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    {:ok, start_opts} =
      ThreadOptions.new(%{
        transport: {:app_server, conn},
        working_directory: "/tmp",
        approvals_reviewer: :guardian_subagent,
        ask_for_approval: %{
          type: :granular,
          sandbox_approval: true,
          rules: true,
          request_permissions: true
        }
      })

    start_thread = Thread.build(codex_opts, start_opts)

    start_task = Task.async(fn -> Thread.run_turn(start_thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, start_line}

    assert {:ok, %{"id" => start_id, "method" => "thread/start", "params" => start_params}} =
             Jason.decode(start_line)

    assert start_params["approvalsReviewer"] == "guardian_subagent"
    assert start_params["approvalPolicy"]["granular"]["sandbox_approval"] == true
    assert start_params["approvalPolicy"]["granular"]["rules"] == true
    assert start_params["approvalPolicy"]["granular"]["request_permissions"] == true
    assert start_params["approvalPolicy"]["granular"]["skill_approval"] == false
    assert start_params["approvalPolicy"]["granular"]["mcp_elicitations"] == false

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(start_id, %{"thread" => %{"id" => "thr_start"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, start_turn_line}

    assert {:ok, %{"id" => start_turn_id, "method" => "turn/start"}} =
             Jason.decode(start_turn_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(start_turn_id, %{
        "turn" => %{
          "id" => "turn_start",
          "items" => [],
          "status" => "inProgress",
          "error" => nil
        }
      })
    )

    AppServerSubprocess.send_stdout([
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_start",
        "turn" => %{
          "id" => "turn_start",
          "status" => "completed",
          "items" => [],
          "error" => nil
        }
      })
    ])

    assert {:ok, _result} = Task.await(start_task, 500)

    {:ok, resume_opts} =
      ThreadOptions.new(%{
        transport: {:app_server, conn},
        working_directory: "/tmp",
        approvals_reviewer: :user,
        ask_for_approval: %{
          type: :granular,
          sandbox_approval: true,
          rules: true,
          request_permissions: true
        }
      })

    resume_thread = Thread.build(codex_opts, resume_opts, thread_id: "thr_resume")

    resume_task = Task.async(fn -> Thread.run_turn(resume_thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, resume_line}

    assert {:ok, %{"id" => resume_id, "method" => "thread/resume", "params" => resume_params}} =
             Jason.decode(resume_line)

    assert resume_params["threadId"] == "thr_resume"
    assert resume_params["approvalsReviewer"] == "user"
    assert resume_params["approvalPolicy"]["granular"]["request_permissions"] == true

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(resume_id, %{"thread" => %{"id" => "thr_resume"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, resume_turn_line}

    assert {:ok, %{"id" => resume_turn_id, "method" => "turn/start"}} =
             Jason.decode(resume_turn_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(resume_turn_id, %{
        "turn" => %{
          "id" => "turn_resume",
          "items" => [],
          "status" => "inProgress",
          "error" => nil
        }
      })
    )

    AppServerSubprocess.send_stdout([
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_resume",
        "turn" => %{
          "id" => "turn_resume",
          "status" => "completed",
          "items" => [],
          "error" => nil
        }
      })
    ])

    assert {:ok, _result} = Task.await(resume_task, 500)
  end

  test "Thread.run_turn/3 collects guardian review and resolved request notifications in order" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    {:ok, thread_opts} =
      ThreadOptions.new(%{transport: {:app_server, conn}, working_directory: "/tmp"})

    thread = Thread.build(codex_opts, thread_opts)

    task = Task.async(fn -> Thread.run_turn(thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start"}} =
             Jason.decode(thread_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    AppServerSubprocess.send_stdout([
      Protocol.encode_notification("item/autoApprovalReview/started", %{
        "threadId" => "thr_1",
        "turnId" => "turn_1",
        "targetItemId" => "perm_1",
        "review" => %{"status" => "inProgress", "riskLevel" => "medium"},
        "action" => %{"type" => "allow"}
      }),
      Protocol.encode_notification("serverRequest/resolved", %{
        "threadId" => "thr_1",
        "requestId" => 77
      }),
      Protocol.encode_notification("item/autoApprovalReview/completed", %{
        "threadId" => "thr_1",
        "turnId" => "turn_1",
        "targetItemId" => "perm_1",
        "review" => %{"status" => "approved"}
      }),
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ])

    assert {:ok, result} = Task.await(task, 500)

    started_index =
      Enum.find_index(result.events, &match?(%Codex.Events.GuardianApprovalReviewStarted{}, &1))

    resolved_index =
      Enum.find_index(result.events, &match?(%Codex.Events.ServerRequestResolved{}, &1))

    completed_index =
      Enum.find_index(result.events, &match?(%Codex.Events.GuardianApprovalReviewCompleted{}, &1))

    turn_completed_index =
      Enum.find_index(result.events, &match?(%Codex.Events.TurnCompleted{}, &1))

    assert is_integer(started_index)
    assert is_integer(resolved_index)
    assert is_integer(completed_index)
    assert is_integer(turn_completed_index)
    assert started_index < resolved_index
    assert resolved_index < turn_completed_index
    assert completed_index < turn_completed_index
  end

  test "Thread.run/3 via app-server accepts multimodal input blocks" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
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

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start", "params" => params}} =
             Jason.decode(turn_start_line)

    assert [
             %{"type" => "text", "text" => "hello"},
             %{"type" => "localImage", "path" => "/tmp/image.png"}
           ] = params["input"]

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
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

    AppServerSubprocess.send_stdout(notifications)

    assert {:ok, result} = Task.await(task, 500)
    assert %Items.AgentMessage{text: "hi"} = result.final_response
  end

  test "Thread.run_turn/3 resets threads on structured /new input via app-server" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
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

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_new"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok,
            %{"id" => turn_start_id, "method" => "turn/start", "params" => turn_start_params}} =
             Jason.decode(turn_start_line)

    assert turn_start_params["threadId"] == "thr_new"

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
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

    AppServerSubprocess.send_stdout(notifications)

    assert {:ok, result} = Task.await(task, 500)
    assert result.thread.thread_id == "thr_new"
    assert %Items.AgentMessage{text: "hi"} = result.final_response
  end

  test "Thread.run_streamed/3 via app-server accepts multimodal input blocks" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
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

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start", "params" => params}} =
             Jason.decode(turn_start_line)

    assert [
             %{"type" => "text", "text" => "hello"},
             %{"type" => "localImage", "path" => "/tmp/image.png"}
           ] = params["input"]

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
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

    AppServerSubprocess.send_stdout(notifications)

    assert events = Task.await(task, 500)
    assert Enum.any?(events, &match?(%Codex.Events.TurnCompleted{}, &1))
  end

  test "Thread.run_streamed/3 via app-server subscribes to the active thread only" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    {:ok, thread_opts} =
      ThreadOptions.new(%{transport: {:app_server, conn}, working_directory: "/tmp"})

    thread = Thread.build(codex_opts, thread_opts)

    {:ok, stream} = Thread.run_streamed(thread, "hello")
    task = Task.async(fn -> stream |> Codex.RunResultStreaming.raw_events() |> Enum.to_list() end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start"}} =
             Jason.decode(thread_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    assert %{subscribers: subscribers} = :sys.get_state(conn)
    assert map_size(subscribers) == 1

    assert Enum.any?(subscribers, fn {_pid, filters} ->
             filters.thread_id == "thr_1"
           end)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    notifications = [
      Protocol.encode_notification("turn/started", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "inProgress", "items" => [], "error" => nil}
      }),
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ]

    AppServerSubprocess.send_stdout(notifications)

    assert [_ | _] = Task.await(task, 500)
    assert %{subscribers: %{}} = :sys.get_state(conn)
  end

  test "app-server thread start includes model/provider/config/instructions flags" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    {:ok, thread_opts} =
      ThreadOptions.new(%{
        transport: {:app_server, conn},
        working_directory: "/tmp",
        model: "gpt-5.4-mini",
        model_provider: "openai",
        permission_profile: %{
          "network" => %{"enabled" => false},
          "fileSystem" => %{"entries" => []}
        },
        config: %{"features.remote_models" => true},
        base_instructions: "base",
        developer_instructions: "dev",
        persist_extended_history: true,
        experimental_raw_events: true
      })

    thread = Thread.build(codex_opts, thread_opts)

    task = Task.async(fn -> Thread.run_turn(thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start", "params" => params}} =
             Jason.decode(thread_start_line)

    assert params["model"] == "gpt-5.4-mini"
    assert params["modelProvider"] == "openai"

    assert params["permissionProfile"] == %{
             "network" => %{"enabled" => false},
             "fileSystem" => %{"entries" => []}
           }

    assert %{"features.remote_models" => true} = params["config"]
    assert params["config"]["model_reasoning_effort"] == "medium"
    assert params["baseInstructions"] == "base"
    assert params["developerInstructions"] == "dev"
    assert params["persistExtendedHistory"] == true
    assert params["experimentalRawEvents"] == true

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    AppServerSubprocess.send_stdout([
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ])

    assert {:ok, _result} = Task.await(task, 500)
  end

  test "app-server transport forwards ephemeral and service tier controls" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    {:ok, thread_opts} =
      ThreadOptions.new(%{
        transport: {:app_server, conn},
        ephemeral: true,
        service_name: "codex-elixir-tests",
        service_tier: :flex,
        permission_profile: %{
          "network" => %{"enabled" => false},
          "fileSystem" => %{"entries" => []}
        }
      })

    thread = Thread.build(codex_opts, thread_opts)

    turn_permission_profile = %{
      "network" => %{"enabled" => true},
      "fileSystem" => %{"entries" => []}
    }

    environments = [%{"id" => "remote_1", "kind" => "remote"}]

    task =
      Task.async(fn ->
        Thread.run_turn(thread, "hello",
          service_tier: :priority,
          permission_profile: turn_permission_profile,
          environments: environments
        )
      end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start", "params" => params}} =
             Jason.decode(thread_start_line)

    assert params["ephemeral"] == true
    assert params["serviceName"] == "codex-elixir-tests"
    assert params["serviceTier"] == "flex"

    assert params["permissionProfile"] == %{
             "network" => %{"enabled" => false},
             "fileSystem" => %{"entries" => []}
           }

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok,
            %{
              "id" => turn_start_id,
              "method" => "turn/start",
              "params" => turn_params
            }} = Jason.decode(turn_start_line)

    assert turn_params["serviceTier"] == "priority"
    assert turn_params["permissionProfile"] == turn_permission_profile
    assert turn_params["environments"] == environments

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    AppServerSubprocess.send_stdout([
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ])

    assert {:ok, _result} = Task.await(task, 500)
  end

  test "app-server transport omits implicit default model overrides but preserves reasoning effort" do
    codex_opts =
      new_codex_opts!(%{
        reasoning_effort: :high
      })

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    {:ok, thread_opts} = ThreadOptions.new(%{transport: {:app_server, conn}})
    thread = Thread.build(codex_opts, thread_opts)

    task = Task.async(fn -> Thread.run_turn(thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start", "params" => params}} =
             Jason.decode(thread_start_line)

    refute Map.has_key?(params, "model")
    assert %{"model_reasoning_effort" => "high"} = params["config"]
    refute Map.has_key?(params, "sandbox")

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    AppServerSubprocess.send_stdout([
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ])

    assert {:ok, _result} = Task.await(task, 500)
  end

  test "app-server turn start includes sandbox policy overrides" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
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

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start", "params" => params}} =
             Jason.decode(turn_start_line)

    assert %{
             "type" => "workspaceWrite",
             "writableRoots" => ["/tmp"],
             "networkAccess" => true
           } = params["sandboxPolicy"]

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    AppServerSubprocess.send_stdout([
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ])

    assert {:ok, _result} = Task.await(task, 500)
  end

  test "app-server transport auto-responds to command approvals using approval_hook" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
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

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    approval_request_params = %{
      "threadId" => "thr_1",
      "turnId" => "turn_1",
      "itemId" => "item_1",
      "reason" => "needs approval",
      "proposedExecpolicyAmendment" => ["npm", "install"]
    }

    AppServerSubprocess.send_stdout(
      Protocol.encode_request(
        7,
        "item/commandExecution/requestApproval",
        approval_request_params
      )
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

    AppServerSubprocess.send_stdout(notifications)

    assert {:ok, _result} = Task.await(task, 500)
  end

  test "app-server command approval hooks receive additional permissions and network context" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    {:ok, thread_opts} =
      ThreadOptions.new(%{
        transport: {:app_server, conn},
        working_directory: "/tmp",
        metadata: %{test_pid: self()},
        approval_hook: CaptureCommandApprovalHook
      })

    thread = Thread.build(codex_opts, thread_opts)

    task = Task.async(fn -> Thread.run_turn(thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start"}} =
             Jason.decode(thread_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    approval_request_params = %{
      "threadId" => "thr_1",
      "turnId" => "turn_1",
      "itemId" => "item_1",
      "approvalId" => "approval_1",
      "reason" => "needs approval",
      "command" => "curl https://example.com",
      "cwd" => "/tmp/project",
      "commandActions" => [%{"type" => "search", "command" => "curl", "path" => nil}],
      "networkApprovalContext" => %{"host" => "example.com", "protocol" => "https"},
      "additionalPermissions" => %{
        "network" => %{"enabled" => true},
        "fileSystem" => %{"write" => ["/tmp/project"]},
        "macos" => %{"accessibility" => true}
      },
      "skillMetadata" => %{"pathToSkillsMd" => "/tmp/project/SKILL.md"},
      "proposedExecpolicyAmendment" => ["curl", "https://example.com"],
      "proposedNetworkPolicyAmendments" => [%{"host" => "example.com", "action" => "allow"}],
      "availableDecisions" => ["accept", %{"applyNetworkPolicyAmendment" => %{}}]
    }

    AppServerSubprocess.send_stdout(
      Protocol.encode_request(
        12,
        "item/commandExecution/requestApproval",
        approval_request_params
      )
    )

    assert_receive {:captured_command_approval, event}, 200

    assert event.additional_permissions ==
             RequestPermissions.RequestPermissionProfile.from_map(
               approval_request_params["additionalPermissions"]
             )

    assert event.network_approval_context == %{"host" => "example.com", "protocol" => "https"}
    assert event.approval_id == "approval_1"
    assert event.command == "curl https://example.com"
    assert event.cwd == "/tmp/project"
    assert event.command_actions == [%{"type" => "search", "command" => "curl", "path" => nil}]
    assert event.skill_metadata == %{"pathToSkillsMd" => "/tmp/project/SKILL.md"}
    assert event.proposed_execpolicy_amendment == ["curl", "https://example.com"]

    assert event.proposed_network_policy_amendments == [
             %{"host" => "example.com", "action" => "allow"}
           ]

    assert event.available_decisions == ["accept", %{"applyNetworkPolicyAmendment" => %{}}]

    assert_receive {:app_server_subprocess_send, ^conn, approval_response_line}, 200

    assert {:ok, %{"id" => 12, "result" => %{"decision" => "decline"}}} =
             Jason.decode(approval_response_line)

    AppServerSubprocess.send_stdout([
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ])

    assert {:ok, _result} = Task.await(task, 500)
  end

  test "app-server transport ignores foreign-thread approval requests" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
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

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    foreign_approval_request = %{
      "threadId" => "thr_other",
      "turnId" => "turn_1",
      "itemId" => "item_1",
      "reason" => "needs approval"
    }

    AppServerSubprocess.send_stdout(
      Protocol.encode_request(
        14,
        "item/commandExecution/requestApproval",
        foreign_approval_request
      )
    )

    refute_receive {:app_server_subprocess_send, ^conn, _approval_response_line}

    AppServerSubprocess.send_stdout([
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ])

    assert {:ok, _result} = Task.await(task, 500)
  end

  test "app-server transport ignores mismatched-turn permissions approvals" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    {:ok, thread_opts} =
      ThreadOptions.new(%{
        transport: {:app_server, conn},
        working_directory: "/tmp",
        approval_hook: AllowPermissionsApprovalHook
      })

    thread = Thread.build(codex_opts, thread_opts)

    task = Task.async(fn -> Thread.run_turn(thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start"}} =
             Jason.decode(thread_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    approval_request_params = %{
      "threadId" => "thr_1",
      "turnId" => "turn_other",
      "itemId" => "perm_1",
      "permissions" => %{"network" => %{"enabled" => true}}
    }

    AppServerSubprocess.send_stdout(
      Protocol.encode_request(
        18,
        "item/permissions/requestApproval",
        approval_request_params
      )
    )

    refute_receive {:app_server_subprocess_send, ^conn, _approval_response_line}

    AppServerSubprocess.send_stdout([
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ])

    assert {:ok, _result} = Task.await(task, 500)
  end

  test "app-server transport auto-responds to permissions approvals using the requested turn grants" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    {:ok, thread_opts} =
      ThreadOptions.new(%{
        transport: {:app_server, conn},
        working_directory: "/tmp",
        approval_hook: AllowPermissionsApprovalHook
      })

    thread = Thread.build(codex_opts, thread_opts)

    task = Task.async(fn -> Thread.run_turn(thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start"}} =
             Jason.decode(thread_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    approval_request_params = %{
      "threadId" => "thr_1",
      "turnId" => "turn_1",
      "itemId" => "perm_1",
      "reason" => "Need additional permissions",
      "permissions" => %{
        "network" => %{"enabled" => true},
        "fileSystem" => %{
          "read" => ["/tmp/read-only"],
          "write" => ["/tmp/project"]
        }
      }
    }

    AppServerSubprocess.send_stdout(
      Protocol.encode_request(
        15,
        "item/permissions/requestApproval",
        approval_request_params
      )
    )

    assert_receive {:app_server_subprocess_send, ^conn, approval_response_line}, 200

    assert {:ok,
            %{
              "id" => 15,
              "result" => %{
                "permissions" => %{
                  "network" => %{"enabled" => true},
                  "fileSystem" => %{
                    "read" => ["/tmp/read-only"],
                    "write" => ["/tmp/project"]
                  }
                },
                "scope" => "turn"
              }
            }} = Jason.decode(approval_response_line)

    AppServerSubprocess.send_stdout([
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ])

    assert {:ok, _result} = Task.await(task, 500)
  end

  test "app-server transport supports partial session permission grants" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    {:ok, thread_opts} =
      ThreadOptions.new(%{
        transport: {:app_server, conn},
        working_directory: "/tmp",
        approval_hook: SessionPermissionsApprovalHook
      })

    thread = Thread.build(codex_opts, thread_opts)

    task = Task.async(fn -> Thread.run_turn(thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start"}} =
             Jason.decode(thread_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    approval_request_params = %{
      "threadId" => "thr_1",
      "turnId" => "turn_1",
      "itemId" => "perm_1",
      "permissions" => %{
        "network" => %{"enabled" => true},
        "fileSystem" => %{
          "read" => ["/tmp/read-only"],
          "write" => ["/tmp/project"]
        }
      }
    }

    AppServerSubprocess.send_stdout(
      Protocol.encode_request(
        16,
        "item/permissions/requestApproval",
        approval_request_params
      )
    )

    assert_receive {:app_server_subprocess_send, ^conn, approval_response_line}, 200

    assert {:ok,
            %{
              "id" => 16,
              "result" => %{
                "permissions" => %{
                  "network" => %{"enabled" => true},
                  "fileSystem" => %{"write" => ["/tmp/project"]}
                },
                "scope" => "session"
              }
            }} = Jason.decode(approval_response_line)

    AppServerSubprocess.send_stdout([
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ])

    assert {:ok, _result} = Task.await(task, 500)
  end

  test "app-server transport denies permissions approvals with an empty turn grant profile" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    {:ok, thread_opts} =
      ThreadOptions.new(%{
        transport: {:app_server, conn},
        working_directory: "/tmp",
        approval_hook: DenyPermissionsApprovalHook
      })

    thread = Thread.build(codex_opts, thread_opts)

    task = Task.async(fn -> Thread.run_turn(thread, "hello") end)

    assert_receive {:app_server_subprocess_send, ^conn, thread_start_line}

    assert {:ok, %{"id" => thread_start_id, "method" => "thread/start"}} =
             Jason.decode(thread_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    approval_request_params = %{
      "threadId" => "thr_1",
      "turnId" => "turn_1",
      "itemId" => "perm_1",
      "permissions" => %{"network" => %{"enabled" => true}}
    }

    AppServerSubprocess.send_stdout(
      Protocol.encode_request(
        17,
        "item/permissions/requestApproval",
        approval_request_params
      )
    )

    assert_receive {:app_server_subprocess_send, ^conn, approval_response_line}, 200

    assert {:ok,
            %{
              "id" => 17,
              "result" => %{"permissions" => %{}, "scope" => "turn"}
            }} = Jason.decode(approval_response_line)

    AppServerSubprocess.send_stdout([
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ])

    assert {:ok, _result} = Task.await(task, 500)
  end

  test "app-server transport auto-responds to file change approvals using approval_hook" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
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

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    approval_request_params = %{
      "threadId" => "thr_1",
      "turnId" => "turn_1",
      "itemId" => "item_1",
      "reason" => "needs approval",
      "grantRoot" => "/tmp"
    }

    AppServerSubprocess.send_stdout(
      Protocol.encode_request(9, "item/fileChange/requestApproval", approval_request_params)
    )

    assert_receive {:app_server_subprocess_send, ^conn, approval_response_line}, 200

    assert {:ok, %{"id" => 9, "result" => %{"decision" => "accept"}}} =
             Jason.decode(approval_response_line)

    AppServerSubprocess.send_stdout([
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ])

    assert {:ok, _result} = Task.await(task, 500)
  end

  test "app-server transport supports grant-root approvals" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
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

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    approval_request_params = %{
      "threadId" => "thr_1",
      "turnId" => "turn_1",
      "itemId" => "item_1",
      "reason" => "needs approval",
      "grantRoot" => "/tmp"
    }

    AppServerSubprocess.send_stdout(
      Protocol.encode_request(9, "item/fileChange/requestApproval", approval_request_params)
    )

    assert_receive {:app_server_subprocess_send, ^conn, approval_response_line}, 200

    assert {:ok, %{"id" => 9, "result" => %{"decision" => "acceptForSession"}}} =
             Jason.decode(approval_response_line)

    AppServerSubprocess.send_stdout([
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ])

    assert {:ok, _result} = Task.await(task, 500)
  end

  test "app-server transport declines when approval_hook times out" do
    codex_opts = new_codex_opts!()

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(AppServerSubprocess.current!()),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(AppServerSubprocess.current!(), conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"}))
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

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(thread_start_id, %{"thread" => %{"id" => "thr_1"}})
    )

    assert_receive {:app_server_subprocess_send, ^conn, turn_start_line}

    assert {:ok, %{"id" => turn_start_id, "method" => "turn/start"}} =
             Jason.decode(turn_start_line)

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(turn_start_id, %{
        "turn" => %{"id" => "turn_1", "items" => [], "status" => "inProgress", "error" => nil}
      })
    )

    approval_request_params = %{
      "threadId" => "thr_1",
      "turnId" => "turn_1",
      "itemId" => "item_1"
    }

    AppServerSubprocess.send_stdout(
      Protocol.encode_request(
        13,
        "item/commandExecution/requestApproval",
        approval_request_params
      )
    )

    assert_receive {:app_server_subprocess_send, ^conn, approval_response_line}, 200

    assert {:ok, %{"id" => 13, "result" => %{"decision" => "decline"}}} =
             Jason.decode(approval_response_line)

    AppServerSubprocess.send_stdout([
      Protocol.encode_notification("turn/completed", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "completed", "items" => [], "error" => nil}
      })
    ])

    assert {:ok, _result} = Task.await(task, 500)
  end

  defp new_codex_opts!(attrs \\ %{}) do
    attrs = Map.put_new(Map.new(attrs), :api_key, "test")
    {:ok, base_opts} = Options.new(attrs)
    AppServerSubprocess.codex_opts(base_opts, AppServerSubprocess.current!())
  end
end

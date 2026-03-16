Mix.Task.run("app.start")

alias Codex.Events
alias Codex.Items
alias Codex.Protocol.RequestPermissions
alias Codex.RunResultStreaming

defmodule CodexExamples.LiveAppServerApprovals do
  @moduledoc false

  @command_file_prompt """
  Run `pwd` and `ls -la` in the current working directory, then create `tmp/approval_demo.txt`
  (create `tmp/` first if needed) containing the current directory path. If you choose shell
  commands, keep them separate so approval events stay easy to read, then report exactly what
  completed.
  """

  @permissions_prompt """
  Before doing anything else, explicitly request additional write permission for
  `/tmp/codex_sdk_permissions_demo.txt` outside the current working directory. After the permission
  decision resolves, do not write the file. Reply with one short sentence describing whether the
  permission request was granted.
  """

  @command_approval_method "item/commandExecution/requestApproval"
  @file_approval_method "item/fileChange/requestApproval"
  @permissions_approval_method "item/permissions/requestApproval"

  def main(argv) do
    command_file_prompt =
      case argv do
        [] -> @command_file_prompt
        values -> Enum.join(values, " ")
      end

    codex_path = fetch_codex_path!()
    ensure_app_server_supported!(codex_path)

    {:ok, codex_opts} =
      Codex.Options.new(%{
        codex_path_override: codex_path,
        reasoning_effort: :low
      })

    {:ok, conn, experimental_api?, init_fallback_reason} =
      connect_for_approvals_demo(codex_opts)

    try do
      parent = self()

      {:ok, approval_pid} =
        Task.start_link(fn ->
          # Subscribe without method filters so request logging stays useful if method names evolve.
          :ok = Codex.AppServer.subscribe(conn)
          send(parent, {:approvals_ready, self()})
          approval_loop(conn, parent)
        end)

      :ok = await_approvals_ready!(approval_pid)

      IO.puts("""
      Streaming over app-server with manual approvals.
        command/file prompt: #{command_file_prompt}
        permissions prompt: #{@permissions_prompt}

      This run prints:
        - proposed commandExecution/fileChange items
        - permissions approval requests with structured grant responses
        - incoming app-server request methods
        - guardian review started/completed notifications when emitted by Codex
        - serverRequest/resolved notifications
        - approval responses sent
        - completion status for command/file items
        - a deterministic permissions-response fallback if the connected build/model never emits
          item/permissions/requestApproval
        - a reconnect without `initialize.capabilities.experimentalApi` when the connected build
          rejects experimental app-server fields
        - an automatic retry with legacy `:untrusted` approvals if the connected Codex build
          does not produce usable live events under the granular policy

      Live guardian review routing and live request-permissions prompts require an app-server
      connection initialized with `experimentalApi = true`. This script tries that first and
      reconnects without it when the connected build rejects the capability.
      """)

      if not experimental_api? do
        IO.puts("""

        The connected Codex build rejected `initialize.capabilities.experimentalApi`:
          #{format_connect_reason(init_fallback_reason)}
        Reconnected without experimental app-server fields. This run will show legacy
        command/file approvals and the exact structured permissions fallback payload instead of
        live guardian/request-permissions events.
        """)
      end

      {thread, audit} =
        if experimental_api? do
          {:ok, granular_thread} =
            start_demo_thread(codex_opts, conn, granular_approval_policy(), :user)

          granular_audit =
            new_audit_state()
            |> run_demo_turn!(granular_thread, command_file_prompt, parent, "command/file")

          if granular_audit == new_audit_state() do
            IO.puts("""

            The connected Codex build did not produce usable live events under the granular
            approval policy. Retrying the command/file demo with legacy `:untrusted` approvals for
            backwards compatibility, while keeping the structured permissions fallback below.
            """)

            {:ok, legacy_thread} = start_demo_thread(codex_opts, conn, :untrusted, nil)

            {legacy_thread,
             new_audit_state()
             |> run_demo_turn!(
               legacy_thread,
               command_file_prompt,
               parent,
               "command/file (legacy policy)"
             )}
          else
            {granular_thread, granular_audit}
          end
        else
          {:ok, legacy_thread} = start_demo_thread(codex_opts, conn, :untrusted, nil)

          {legacy_thread,
           new_audit_state()
           |> run_demo_turn!(
             legacy_thread,
             command_file_prompt,
             parent,
             "command/file (legacy policy)"
           )}
        end

      audit =
        if experimental_api? do
          maybe_run_permissions_turn!(audit, thread, parent)
        else
          print_permissions_response_fallback()
          audit
        end

      print_audit_summary(audit)

      send(approval_pid, :stop)
    after
      :ok = Codex.AppServer.disconnect(conn)
    end
  end

  defp run_demo_turn!(audit, thread, prompt, parent, label) do
    case Codex.Thread.run_streamed(thread, prompt, %{timeout_ms: 120_000}) do
      {:ok, stream} ->
        IO.puts("\n--- #{label} turn ---")

        stream
        |> RunResultStreaming.raw_events()
        |> Enum.each(&print_event(&1, parent))

        IO.puts("\nusage: #{inspect(RunResultStreaming.usage(stream))}")
        drain_audit_messages(audit)

      {:error, reason} ->
        Mix.raise("#{label} streaming run failed: #{inspect(reason)}")
    end
  end

  defp start_demo_thread(codex_opts, conn, approval_policy, approvals_reviewer) do
    %{
      transport: {:app_server, conn},
      working_directory: File.cwd!(),
      ask_for_approval: approval_policy
    }
    |> maybe_put(:approvals_reviewer, approvals_reviewer)
    |> then(&Codex.start_thread(codex_opts, &1))
  end

  defp maybe_run_permissions_turn!(audit, thread, parent) do
    if MapSet.member?(audit.approval_request_methods, @permissions_approval_method) do
      audit
    else
      IO.puts("""

      No live permissions approval was observed in the first turn.
      Running a supplemental turn that explicitly asks for out-of-cwd write permission.
      """)

      updated_audit = run_demo_turn!(audit, thread, @permissions_prompt, parent, "permissions")

      if MapSet.member?(updated_audit.approval_request_methods, @permissions_approval_method) do
        updated_audit
      else
        print_permissions_response_fallback()
        updated_audit
      end
    end
  end

  defp approval_loop(conn, parent) do
    receive do
      :stop ->
        :ok

      {:codex_request, id, method, params} ->
        IO.puts("\n[codex_request] method=#{method}")
        send(parent, {:audit, {:request_received, method}})

        case method do
          @command_approval_method ->
            maybe_log_execpolicy_hint(params)
            :ok = Codex.AppServer.respond(conn, id, %{decision: "acceptForSession"})
            IO.puts("[approval] responded to commandExecution request")
            send(parent, {:audit, {:response_sent, method}})

          @file_approval_method ->
            :ok = Codex.AppServer.respond(conn, id, %{decision: "accept"})
            IO.puts("[approval] responded to fileChange request")
            send(parent, {:audit, {:response_sent, method}})

          @permissions_approval_method ->
            response = build_permissions_response(params)
            IO.puts("[approval] requested permissions: #{describe_permissions_request(params)}")
            :ok = Codex.AppServer.respond(conn, id, response)
            IO.puts("[approval] responded to permissions request with structured grant payload")
            send(parent, {:audit, {:permissions_granted, response}})
            send(parent, {:audit, {:response_sent, method}})

          _other ->
            IO.puts("[codex_request] no handler configured for #{method}")
        end

        approval_loop(conn, parent)

      _other ->
        approval_loop(conn, parent)
    end
  end

  defp maybe_log_execpolicy_hint(%{"proposedExecpolicyAmendment" => argv})
       when is_list(argv) and argv != [] do
    IO.puts(
      "[approval] server proposed execpolicy amendment #{inspect(argv)}; accepting for session for demo stability"
    )
  end

  defp maybe_log_execpolicy_hint(_params), do: :ok

  defp connect_for_approvals_demo(codex_opts) do
    experimental_opts = [init_timeout_ms: 30_000, experimental_api: true]

    case Codex.AppServer.connect(codex_opts, experimental_opts) do
      {:ok, conn} ->
        {:ok, conn, true, nil}

      {:error, {:init_failed, reason}} ->
        if experimental_api_rejected?(reason) do
          case Codex.AppServer.connect(codex_opts, init_timeout_ms: 30_000) do
            {:ok, conn} ->
              {:ok, conn, false, reason}

            {:error, retry_reason} ->
              {:error, {:experimental_api_init_failed, reason, retry_reason}}
          end
        else
          {:error, {:init_failed, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp granular_approval_policy do
    %{
      type: :granular,
      sandbox_approval: true,
      rules: true,
      skill_approval: true,
      request_permissions: true,
      mcp_elicitations: true
    }
  end

  defp build_permissions_response(%{} = params) do
    requested =
      params
      |> Map.get("permissions", %{})
      |> RequestPermissions.RequestPermissionProfile.from_map()

    %RequestPermissions.Response{
      permissions:
        requested
        |> RequestPermissions.RequestPermissionProfile.to_map()
        |> RequestPermissions.GrantedPermissionProfile.from_map(),
      scope: :turn
    }
    |> RequestPermissions.Response.to_map()
  end

  defp describe_permissions_request(%{} = params) do
    requested =
      params
      |> Map.get("permissions", %{})
      |> RequestPermissions.RequestPermissionProfile.from_map()

    network = get_in(requested, [:network, :enabled])
    reads = get_in(requested, [:file_system, :read]) || []
    writes = get_in(requested, [:file_system, :write]) || []

    "network=#{inspect(network)} read=#{inspect(reads)} write=#{inspect(writes)}"
  end

  defp print_permissions_response_fallback do
    params = %{
      "permissions" => %{
        "network" => %{"enabled" => false},
        "fileSystem" => %{"write" => ["/tmp/codex_sdk_permissions_demo.txt"]}
      }
    }

    response = build_permissions_response(params)

    IO.puts("""

    [permissions.fallback]
      The connected build/model did not emit `item/permissions/requestApproval`, so this example
      is printing the exact SDK response shape it would send for a structured grant:
      request: #{inspect(params["permissions"])}
      response: #{inspect(response)}
    """)
  end

  defp format_connect_reason(%{} = reason) do
    reason
    |> Map.take(["code", "message"])
    |> inspect()
  end

  defp format_connect_reason(reason), do: inspect(reason)

  defp experimental_api_rejected?(%{} = reason) do
    message =
      reason
      |> Map.get("message", Map.get(reason, :message, ""))
      |> to_string()
      |> String.downcase()

    String.contains?(message, "experimentalapi") or
      String.contains?(message, "experimental api") or
      (String.contains?(message, "capabilities") and
         (String.contains?(message, "unknown field") or
            String.contains?(message, "unexpected field") or
            String.contains?(message, "invalid params")))
  end

  defp experimental_api_rejected?(_reason), do: false

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp await_approvals_ready!(task_pid) when is_pid(task_pid) do
    receive do
      {:approvals_ready, ^task_pid} -> :ok
    after
      5_000 -> Mix.raise("Timed out waiting for approval subscription")
    end
  end

  defp print_event(%Events.ItemAgentMessageDelta{item: %{"text" => delta}}, _parent)
       when is_binary(delta) do
    IO.write(delta)
  end

  defp print_event(%Events.ItemStarted{item: %Items.CommandExecution{} = item}, parent) do
    IO.puts("""

    [item.started commandExecution]
      command: #{item.command}
      cwd: #{inspect(item.cwd)}
      status: #{inspect(item.status)}
    """)

    send(parent, {:audit, :command_proposed})
  end

  defp print_event(%Events.ItemStarted{item: %Items.FileChange{} = item}, parent) do
    IO.puts("""

    [item.started fileChange]
      changes: #{length(item.changes)}
      status: #{inspect(item.status)}
    """)

    send(parent, {:audit, :file_proposed})
  end

  defp print_event(%Events.ItemCompleted{item: %Items.CommandExecution{} = item}, parent) do
    IO.puts("""

    [item.completed commandExecution]
      status: #{inspect(item.status)}
      exit_code: #{inspect(item.exit_code)}
      command: #{item.command}
    """)

    send(parent, {:audit, {:command_completed, item.status}})
  end

  defp print_event(%Events.ItemCompleted{item: %Items.FileChange{} = item}, parent) do
    IO.puts("""

    [item.completed fileChange]
      status: #{inspect(item.status)}
      changes: #{length(item.changes)}
    """)

    send(parent, {:audit, {:file_completed, item.status}})
  end

  defp print_event(%Events.ItemCompleted{item: %Items.AgentMessage{text: text}}, _parent) do
    if is_binary(text) and String.trim(text) != "" do
      IO.puts("\n\n[agent_message.completed]\n#{text}\n")
    end
  end

  defp print_event(%Events.GuardianApprovalReviewStarted{} = event, parent) do
    IO.puts("""

    [guardian.review.started]
      target_item_id: #{event.target_item_id}
      status: #{inspect(event.review.status)}
      risk_level: #{inspect(event.review.risk_level)}
      rationale: #{inspect(event.review.rationale)}
    """)

    send(parent, {:audit, {:guardian_started, event.target_item_id}})
  end

  defp print_event(%Events.GuardianApprovalReviewCompleted{} = event, parent) do
    IO.puts("""

    [guardian.review.completed]
      target_item_id: #{event.target_item_id}
      status: #{inspect(event.review.status)}
      risk_level: #{inspect(event.review.risk_level)}
      rationale: #{inspect(event.review.rationale)}
    """)

    send(parent, {:audit, {:guardian_completed, event.review.status}})
  end

  defp print_event(%Events.ServerRequestResolved{} = event, parent) do
    IO.puts("""

    [server_request.resolved]
      thread_id: #{event.thread_id}
      request_id: #{inspect(event.request_id)}
    """)

    send(parent, {:audit, {:resolved_request, event.request_id}})
  end

  defp print_event(%Events.TurnCompleted{status: status}, _parent) do
    IO.puts("\n[turn.completed] status=#{inspect(status)}")
  end

  defp print_event(_other, _parent), do: :ok

  defp new_audit_state do
    %{
      command_proposed?: false,
      file_proposed?: false,
      approval_request_methods: MapSet.new(),
      approval_response_methods: MapSet.new(),
      permissions_grants: [],
      guardian_started_items: [],
      guardian_completed_statuses: [],
      resolved_request_ids: [],
      command_completed_statuses: [],
      file_completed_statuses: []
    }
  end

  defp drain_audit_messages(state) do
    receive do
      {:audit, :command_proposed} ->
        drain_audit_messages(%{state | command_proposed?: true})

      {:audit, :file_proposed} ->
        drain_audit_messages(%{state | file_proposed?: true})

      {:audit, {:request_received, method}} ->
        methods = MapSet.put(state.approval_request_methods, method)
        drain_audit_messages(%{state | approval_request_methods: methods})

      {:audit, {:response_sent, method}} ->
        methods = MapSet.put(state.approval_response_methods, method)
        drain_audit_messages(%{state | approval_response_methods: methods})

      {:audit, {:permissions_granted, response}} ->
        drain_audit_messages(%{state | permissions_grants: [response | state.permissions_grants]})

      {:audit, {:guardian_started, item_id}} ->
        drain_audit_messages(%{
          state
          | guardian_started_items: [item_id | state.guardian_started_items]
        })

      {:audit, {:guardian_completed, status}} ->
        drain_audit_messages(%{
          state
          | guardian_completed_statuses: [status | state.guardian_completed_statuses]
        })

      {:audit, {:resolved_request, request_id}} ->
        drain_audit_messages(%{
          state
          | resolved_request_ids: [request_id | state.resolved_request_ids]
        })

      {:audit, {:command_completed, status}} ->
        drain_audit_messages(%{
          state
          | command_completed_statuses: [status | state.command_completed_statuses]
        })

      {:audit, {:file_completed, status}} ->
        drain_audit_messages(%{
          state
          | file_completed_statuses: [status | state.file_completed_statuses]
        })
    after
      250 ->
        state
    end
  end

  defp print_audit_summary(audit) do
    IO.puts("\nAudit summary:")
    IO.puts("  command/file item proposed? #{audit.command_proposed? or audit.file_proposed?}")
    IO.puts("  commandExecution proposed? #{audit.command_proposed?}")
    IO.puts("  fileChange proposed? #{audit.file_proposed?}")

    IO.puts(
      "  approval request methods: #{inspect(MapSet.to_list(audit.approval_request_methods))}"
    )

    IO.puts(
      "  approval response methods: #{inspect(MapSet.to_list(audit.approval_response_methods))}"
    )

    IO.puts("  permissions grants sent: #{inspect(Enum.reverse(audit.permissions_grants))}")

    IO.puts(
      "  guardian review started items: #{inspect(Enum.reverse(audit.guardian_started_items))}"
    )

    IO.puts(
      "  guardian review completed statuses: #{inspect(Enum.reverse(audit.guardian_completed_statuses))}"
    )

    IO.puts("  resolved request ids: #{inspect(Enum.reverse(audit.resolved_request_ids))}")

    IO.puts(
      "  commandExecution completed statuses: #{inspect(Enum.reverse(audit.command_completed_statuses))}"
    )

    IO.puts(
      "  fileChange completed statuses: #{inspect(Enum.reverse(audit.file_completed_statuses))}"
    )

    if MapSet.size(audit.approval_request_methods) == 0 do
      IO.puts(
        "  note: no approval requests observed for this prompt/policy combination; check item events above to confirm whether tools were invoked."
      )
    end

    if not MapSet.member?(audit.approval_request_methods, @file_approval_method) do
      IO.puts(
        "  note: no live fileChange approval was observed; the model handled file updates without a separate fileChange approval item in this run."
      )
    end

    if not MapSet.member?(audit.approval_request_methods, @permissions_approval_method) do
      IO.puts(
        "  note: no live permissions approval was observed even after the supplemental turn; see [permissions.fallback] above for the exact structured response payload."
      )
    end
  end

  defp fetch_codex_path! do
    System.get_env("CODEX_PATH") ||
      System.find_executable("codex") ||
      Mix.raise("""
      Unable to locate the `codex` CLI.
      Install the Codex CLI and ensure it is on your PATH or set CODEX_PATH.
      """)
  end

  defp ensure_app_server_supported!(codex_path) do
    {_output, status} = System.cmd(codex_path, ["app-server", "--help"], stderr_to_stdout: true)

    if status != 0 do
      Mix.raise("""
      Your `codex` CLI does not appear to support `codex app-server`.
      Upgrade via `npm install -g @openai/codex` and retry.
      """)
    end
  end
end

CodexExamples.LiveAppServerApprovals.main(System.argv())

Mix.Task.run("app.start")

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias CodexExamples.Support

Support.init!()

alias Codex.AppServer.ApprovalDecision
alias Codex.Auth
alias Codex.Config.LayerStack
alias Codex.Events
alias Codex.Items
alias Codex.Protocol.RequestPermissions
alias Codex.RunResultStreaming

defmodule CodexExamples.LiveAppServerApprovals do
  @moduledoc false

  @command_file_prompt """
  Run `pwd` and `ls -la` in the current working directory, then fetch
  `https://example.com` with a separate shell command before creating `tmp/approval_demo.txt`
  (create `tmp/` first if needed) containing the current directory path. Keep shell commands
  separate so approval events stay easy to read, then report exactly what completed.
  """

  @command_approval_method "item/commandExecution/requestApproval"
  @file_approval_method "item/fileChange/requestApproval"
  @permissions_approval_method "item/permissions/requestApproval"
  @demo_feature_flags ~w(request_permissions_tool exec_permission_approvals guardian_approval)

  def main(argv) do
    case run(argv) do
      :ok ->
        :ok

      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")

      {:error, reason} ->
        Mix.raise("App-server approvals example failed: #{inspect(reason)}")
    end
  end

  defp run(argv) do
    command_file_prompt =
      case argv do
        [] -> @command_file_prompt
        values -> Enum.join(values, " ")
      end

    with :ok <-
           Support.ensure_local_execution_surface(
             "this example provisions host-local approval fixtures and does not support --ssh-host"
           ),
         {:ok, codex_opts} <- Support.codex_options(%{}, missing_cli: :skip),
         :ok <- Support.ensure_app_server_supported(codex_opts),
         {:ok, fixture} <- build_demo_fixture() do
      try do
        permissions_prompt = permissions_prompt(fixture)

        with {:ok, conn, experimental_api?, init_fallback_reason} <-
               connect_for_approvals_demo(codex_opts, fixture) do
          try do
            parent = self()

            {:ok, approval_pid} =
              Task.start_link(fn ->
                :ok = Codex.AppServer.subscribe(conn)
                send(parent, {:approvals_ready, self()})
                approval_loop(conn, parent)
              end)

            :ok = await_approvals_ready!(approval_pid)

            print_demo_intro(
              command_file_prompt,
              permissions_prompt,
              fixture,
              experimental_api?,
              init_fallback_reason
            )

            {thread, audit} =
              if experimental_api? do
                {:ok, granular_thread} =
                  start_demo_thread(
                    codex_opts,
                    conn,
                    fixture,
                    granular_approval_policy(),
                    :guardian_subagent
                  )

                granular_audit =
                  new_audit_state()
                  |> run_demo_turn!(granular_thread, command_file_prompt, parent, "command/file")

                if granular_audit == new_audit_state() do
                  IO.puts("""

                  The connected Codex build did not produce usable live events under the granular
                  approval policy. Retrying the command/file demo with legacy `:untrusted`
                  approvals for backwards compatibility while keeping the isolated feature-enabled
                  permissions turn below.
                  """)

                  {:ok, legacy_thread} =
                    start_demo_thread(codex_opts, conn, fixture, :untrusted, nil)

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
                {:ok, legacy_thread} =
                  start_demo_thread(codex_opts, conn, fixture, :untrusted, nil)

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
                maybe_run_permissions_turn!(audit, thread, parent, permissions_prompt, fixture)
              else
                print_permissions_response_fallback(fixture)
                audit
              end

            print_audit_summary(audit)
            send(approval_pid, :stop)
            :ok
          after
            :ok = Codex.AppServer.disconnect(conn)
          end
        end
      after
        cleanup_fixture(fixture)
      end
    else
      {:skip, _reason} = skip ->
        skip

      {:error, reason} ->
        {:error, reason}
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

  defp start_demo_thread(codex_opts, conn, fixture, approval_policy, approvals_reviewer) do
    %{
      transport: {:app_server, conn},
      working_directory: fixture.workspace_root,
      ask_for_approval: approval_policy,
      sandbox: :workspace_write
    }
    |> maybe_put(:approvals_reviewer, approvals_reviewer)
    |> Support.thread_opts!()
    |> then(&Codex.start_thread(codex_opts, &1))
  end

  defp maybe_run_permissions_turn!(audit, thread, parent, permissions_prompt, fixture) do
    if MapSet.member?(audit.approval_request_methods, @permissions_approval_method) do
      audit
    else
      IO.puts("""

      No live permissions approval was observed in the first turn.
      Running a supplemental turn that explicitly asks for write access outside the isolated
      demo workspace:
        #{fixture.permissions_target}
      """)

      updated_audit = run_demo_turn!(audit, thread, permissions_prompt, parent, "permissions")

      if MapSet.member?(updated_audit.approval_request_methods, @permissions_approval_method) do
        updated_audit
      else
        print_permissions_response_fallback(fixture)
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

  defp connect_for_approvals_demo(codex_opts, fixture) do
    experimental_opts = connect_opts(fixture, experimental_api: true)

    case Codex.AppServer.connect(codex_opts, experimental_opts) do
      {:ok, conn} ->
        {:ok, conn, true, nil}

      {:error, {:init_failed, reason}} ->
        if experimental_api_rejected?(reason) do
          case Codex.AppServer.connect(codex_opts, connect_opts(fixture, [])) do
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

    ApprovalDecision.from_permissions_hook(:allow, requested)
  end

  defp describe_permissions_request(%{} = params) do
    requested =
      params
      |> Map.get("permissions", %{})
      |> RequestPermissions.RequestPermissionProfile.from_map()

    requested
    |> RequestPermissions.RequestPermissionProfile.to_map()
    |> inspect()
  end

  defp print_permissions_response_fallback(fixture) do
    params = %{
      "permissions" => %{
        "network" => %{"enabled" => false},
        "fileSystem" => %{"write" => [fixture.permissions_target]}
      }
    }

    response = build_permissions_response(params)

    IO.puts("""

    [permissions.fallback]
      The connected build/model still did not emit `item/permissions/requestApproval`, even with
      isolated feature flags enabled in a temporary `CODEX_HOME`. This example is printing the
      exact SDK response shape it would send for a structured grant:
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

  defp permissions_prompt(fixture) do
    """
    Before doing anything else, explicitly request additional write permission for
    `#{fixture.permissions_target}` outside the current working directory. After the permission
    decision resolves, do not write the file. Reply with one short sentence describing whether the
    permission request was granted.
    """
  end

  defp print_demo_intro(
         command_file_prompt,
         permissions_prompt,
         fixture,
         experimental_api?,
         init_fallback_reason
       ) do
    IO.puts("""
    Streaming over app-server with manual approvals.
      workspace_root: #{fixture.workspace_root}
      isolated_codex_home: #{fixture.codex_home}
      isolated_feature_flags: #{Enum.join(fixture.feature_flags, ", ")}
      copied_auth_files: #{inspect(fixture.copied_auth_files)}
      command/file prompt: #{command_file_prompt}
      permissions prompt: #{permissions_prompt}

    This run prints:
      - typed commandExecution/fileChange/requestApproval events when the server emits them
      - typed permissions approval events with structured grant responses
      - raw incoming app-server request methods
      - guardian review started/completed notifications when emitted by Codex
      - serverRequest/resolved notifications
      - approval responses sent
      - completion status for command/file items
      - a deterministic permissions-response fallback if the connected build/model still never
        emits item/permissions/requestApproval
      - a reconnect without `initialize.capabilities.experimentalApi` when the connected build
        rejects experimental app-server fields
      - an automatic retry with legacy `:untrusted` approvals if the connected Codex build does
        not produce usable live events under the granular policy

    Stock Codex builds keep `request_permissions_tool`, `exec_permission_approvals`, and
    `guardian_approval` disabled by default. This example enables them only inside the temporary
    `CODEX_HOME` above, so it can exercise the live protocol without mutating your real settings
    or writing inside this repository.
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
  end

  defp build_demo_fixture do
    suffix = System.unique_integer([:positive])
    temp_root = Path.join(System.tmp_dir!(), "codex_approvals_example_#{suffix}")
    workspace_root = Path.join(temp_root, "workspace")
    home_root = Path.join(temp_root, "home")
    codex_home = Path.join(home_root, ".codex")
    permissions_target = Path.join(temp_root, "outside/codex_sdk_permissions_demo.txt")

    with :ok <- File.mkdir_p(workspace_root),
         :ok <- File.mkdir_p(codex_home),
         :ok <-
           File.write(
             Path.join(workspace_root, "README.txt"),
             "Temporary approvals demo workspace\n"
           ),
         {:ok, copied_auth_files} <- copy_auth_fixture_files(codex_home),
         :ok <- write_demo_config(codex_home) do
      {:ok,
       %{
         temp_root: temp_root,
         workspace_root: workspace_root,
         home_root: home_root,
         codex_home: codex_home,
         permissions_target: permissions_target,
         feature_flags: @demo_feature_flags,
         copied_auth_files: copied_auth_files
       }}
    else
      {:error, reason} ->
        cleanup_fixture(%{temp_root: temp_root})
        {:error, {:fixture_setup_failed, reason}}
    end
  end

  defp write_demo_config(codex_home) do
    config_lines =
      current_auth_store_lines() ++
        [
          "[features]",
          "request_permissions_tool = true",
          "exec_permission_approvals = true",
          "guardian_approval = true"
        ]

    File.write(Path.join(codex_home, "config.toml"), Enum.join(config_lines, "\n") <> "\n")
  end

  defp current_auth_store_lines do
    cwd = File.cwd!()

    with {:ok, layers} <- LayerStack.load(Auth.codex_home(), cwd),
         %{} = config <- LayerStack.effective_config(layers),
         mode when is_binary(mode) <-
           Map.get(config, "cli_auth_credentials_store") ||
             Map.get(config, :cli_auth_credentials_store),
         true <- mode in ["auto", "file", "keyring"] do
      ["cli_auth_credentials_store = #{inspect(mode)}", ""]
    else
      _ -> []
    end
  end

  defp copy_auth_fixture_files(codex_home) do
    Auth.auth_paths()
    |> Enum.reduce_while({:ok, []}, fn source, {:ok, copied} ->
      case copy_auth_fixture_file(source, codex_home) do
        :skip -> {:cont, {:ok, copied}}
        {:ok, destination} -> {:cont, {:ok, [destination | copied]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, copied} -> {:ok, Enum.reverse(copied)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp copy_auth_fixture_file(source, _codex_home) when not is_binary(source), do: :skip

  defp copy_auth_fixture_file(source, codex_home) do
    if File.regular?(source) do
      destination = auth_fixture_destination(source, codex_home)

      with :ok <- File.mkdir_p(Path.dirname(destination)),
           :ok <- File.cp(source, destination) do
        {:ok, destination}
      else
        {:error, reason} -> {:error, {:auth_copy_failed, source, reason}}
      end
    else
      :skip
    end
  end

  defp auth_fixture_destination(source, codex_home) do
    case Path.basename(source) do
      "auth.json" -> Path.join(codex_home, "auth.json")
      ".credentials.json" -> Path.join(codex_home, ".credentials.json")
      "credentials.json" -> Path.join(codex_home, ".credentials.json")
      "codex.json" -> Path.join(codex_home, ".credentials.json")
      other -> Path.join(codex_home, other)
    end
  end

  defp connect_opts(fixture, extra_opts) do
    [
      init_timeout_ms: 30_000,
      cwd: fixture.workspace_root,
      process_env: isolated_process_env(fixture)
    ] ++
      extra_opts
  end

  defp isolated_process_env(fixture) do
    %{}
    |> maybe_put("CODEX_HOME", fixture.codex_home)
    |> maybe_put("HOME", System.get_env("HOME") || System.user_home!())
    |> maybe_put("USERPROFILE", System.get_env("USERPROFILE"))
  end

  defp format_permission_profile(nil), do: nil

  defp format_permission_profile(profile) do
    profile
    |> RequestPermissions.RequestPermissionProfile.from_map()
    |> RequestPermissions.RequestPermissionProfile.to_map()
  end

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

  defp print_event(%Events.CommandApprovalRequested{} = event, parent) do
    IO.puts("""

    [approval.request commandExecution]
      item_id: #{event.item_id}
      approval_id: #{inspect(event.approval_id)}
      reason: #{inspect(event.reason)}
      command: #{inspect(event.command)}
      cwd: #{inspect(event.cwd)}
      command_actions: #{inspect(event.command_actions)}
      network_approval_context: #{inspect(event.network_approval_context)}
      additional_permissions: #{inspect(format_permission_profile(event.additional_permissions))}
      available_decisions: #{inspect(event.available_decisions)}
      proposed_execpolicy_amendment: #{inspect(event.proposed_execpolicy_amendment)}
      proposed_network_policy_amendments: #{inspect(event.proposed_network_policy_amendments)}
    """)

    send(parent, {:audit, {:request_received, @command_approval_method}})
  end

  defp print_event(%Events.FileApprovalRequested{} = event, parent) do
    IO.puts("""

    [approval.request fileChange]
      item_id: #{event.item_id}
      reason: #{inspect(event.reason)}
      grant_root: #{inspect(event.grant_root)}
    """)

    send(parent, {:audit, {:request_received, @file_approval_method}})
  end

  defp print_event(%Events.PermissionsApprovalRequested{} = event, parent) do
    IO.puts("""

    [approval.request permissions]
      item_id: #{event.item_id}
      reason: #{inspect(event.reason)}
      permissions: #{inspect(format_permission_profile(event.permissions))}
    """)

    send(parent, {:audit, {:request_received, @permissions_approval_method}})
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
      review_id: #{inspect(event.review_id)}
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
      review_id: #{inspect(event.review_id)}
      target_item_id: #{event.target_item_id}
      decision_source: #{inspect(event.decision_source)}
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

    if not MapSet.member?(audit.approval_request_methods, @command_approval_method) do
      IO.puts(
        "  note: no live commandExecution approval was observed; the connected build/model may have allowed the requested shell commands without a separate command approval request."
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

  defp cleanup_fixture(%{temp_root: temp_root}) when is_binary(temp_root),
    do: File.rm_rf(temp_root)

  defp cleanup_fixture(_fixture), do: :ok
end

CodexExamples.LiveAppServerApprovals.main(System.argv())

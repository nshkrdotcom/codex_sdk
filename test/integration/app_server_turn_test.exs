defmodule Codex.Integration.AppServerTurnTest do
  use ExUnit.Case, async: false

  alias Codex.AppServer.Connection
  alias Codex.Items
  alias Codex.Options
  alias Codex.TestSupport.FixtureScripts
  alias Codex.Thread
  alias Codex.Thread.Options, as: ThreadOptions

  @moduletag :integration

  defmodule ExecpolicyApprovalHook do
    @behaviour Codex.Approvals.Hook

    @impl true
    def review_tool(_event, _context, _opts), do: :allow

    @impl true
    def review_command(_event, _context, _opts) do
      {:allow, execpolicy_amendment: ["npm", "install"]}
    end
  end

  test "runs a turn over app-server stdio using a mock codex executable" do
    script_path = FixtureScripts.mock_app_server(scenario: :basic)

    on_exit(fn ->
      File.rm_rf(script_path)
    end)

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    {:ok, conn} = Connection.start_link(codex_opts, init_timeout_ms: 1_000)
    assert :ok == Connection.await_ready(conn, 1_000)

    on_exit(fn ->
      if Process.alive?(conn) do
        Process.exit(conn, :normal)
      end
    end)

    {:ok, thread_opts} =
      ThreadOptions.new(%{transport: {:app_server, conn}, working_directory: "/tmp"})

    thread = Thread.build(codex_opts, thread_opts)

    assert {:ok, result} = Thread.run_turn(thread, "hello", completion_timeout_ms: 1_000)
    assert result.thread.thread_id == "thr_1"
    assert %Items.AgentMessage{text: "hi"} = result.final_response
  end

  test "auto-responds to command approvals over stdio using approval_hook" do
    expected_decision = %{
      "acceptWithExecpolicyAmendment" => %{"execpolicyAmendment" => ["npm", "install"]}
    }

    script_path =
      FixtureScripts.mock_app_server(
        scenario: :command_approval,
        expected_decision: expected_decision
      )

    on_exit(fn ->
      File.rm_rf(script_path)
    end)

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    {:ok, conn} = Connection.start_link(codex_opts, init_timeout_ms: 1_000)
    assert :ok == Connection.await_ready(conn, 1_000)

    on_exit(fn ->
      if Process.alive?(conn) do
        Process.exit(conn, :normal)
      end
    end)

    {:ok, thread_opts} =
      ThreadOptions.new(%{
        transport: {:app_server, conn},
        working_directory: "/tmp",
        approval_hook: ExecpolicyApprovalHook
      })

    thread = Thread.build(codex_opts, thread_opts)

    assert {:ok, result} = Thread.run_turn(thread, "hello", completion_timeout_ms: 1_000)
    assert result.thread.thread_id == "thr_1"
    assert %Items.AgentMessage{text: "hi"} = result.final_response
  end
end

defmodule Codex.ApprovalsTest do
  use ExUnit.Case, async: true

  alias Codex.Approvals
  alias Codex.Approvals.Hook
  alias Codex.Approvals.StaticPolicy

  defmodule SyncAllowHook do
    @behaviour Hook

    @impl true
    def prepare(_event, context), do: {:ok, context}

    @impl true
    def review_tool(_event, _context, _opts), do: :allow
  end

  defmodule SyncDenyHook do
    @behaviour Hook

    @impl true
    def prepare(_event, context), do: {:ok, context}

    @impl true
    def review_tool(_event, _context, _opts), do: {:deny, "blocked by policy"}
  end

  defmodule AsyncHook do
    @behaviour Hook

    @impl true
    def prepare(_event, context), do: {:ok, context}

    @impl true
    def review_tool(_event, _context, _opts) do
      ref = make_ref()
      {:async, ref, %{submitted_at: System.system_time()}}
    end

    @impl true
    def await(ref, timeout) do
      # Simulate async approval - check mailbox for test messages
      receive do
        {:approve, ^ref} -> {:ok, :allow}
        {:deny, ^ref, reason} -> {:ok, {:deny, reason}}
      after
        timeout -> {:error, :timeout}
      end
    end
  end

  defmodule AsyncTimeoutHook do
    @behaviour Hook

    @impl true
    def prepare(_event, context), do: {:ok, context}

    @impl true
    def review_tool(_event, _context, _opts) do
      {:async, make_ref()}
    end

    @impl true
    def await(_ref, timeout) do
      # Never respond, always timeout
      Process.sleep(timeout + 100)
      {:error, :timeout}
    end
  end

  describe "StaticPolicy" do
    test "allow policy approves tool calls" do
      policy = StaticPolicy.allow()
      assert :allow = StaticPolicy.review_tool(policy, %{tool_name: "demo"}, %{})
    end

    test "deny policy returns tagged error" do
      policy = StaticPolicy.deny(reason: "compliance")

      assert {:deny, "compliance"} =
               StaticPolicy.review_tool(policy, %{tool_name: "demo"}, %{thread_id: "t"})
    end
  end

  describe "review_tool/3 with sync hooks" do
    test "allows when sync hook returns :allow" do
      event = %{tool_name: "test_tool", arguments: %{}, call_id: "call_1"}
      context = %{thread: nil, metadata: %{}}

      assert :allow = Approvals.review_tool(SyncAllowHook, event, context)
    end

    test "denies when sync hook returns {:deny, reason}" do
      event = %{tool_name: "test_tool", arguments: %{}, call_id: "call_1"}
      context = %{thread: nil, metadata: %{}}

      assert {:deny, "blocked by policy"} = Approvals.review_tool(SyncDenyHook, event, context)
    end
  end

  describe "review_tool/3 with async hooks" do
    test "handles async approval that resolves to :allow via spawn" do
      # Define a hook that uses process communication
      defmodule SpawnApprovalHook do
        @behaviour Hook

        @impl true
        def prepare(_event, context), do: {:ok, context}

        @impl true
        def review_tool(_event, _context, _opts) do
          ref = make_ref()
          parent = self()

          # Spawn a process that will approve after a delay
          spawn(fn ->
            Process.sleep(50)
            send(parent, {:approve, ref})
          end)

          {:async, ref}
        end

        @impl true
        def await(ref, timeout) do
          receive do
            {:approve, ^ref} -> {:ok, :allow}
          after
            timeout -> {:error, :timeout}
          end
        end
      end

      event = %{tool_name: "test_tool", arguments: %{}, call_id: "call_1"}
      context = %{thread: nil, metadata: %{}}

      # The hook will spawn, wait, and send approval - dispatcher will await
      assert :allow = Approvals.review_tool(SpawnApprovalHook, event, context, timeout: 1000)
    end

    test "handles async approval with immediate response" do
      # Define a hook that immediately responds
      defmodule QuickAsyncHook do
        @behaviour Hook

        @impl true
        def prepare(_event, context), do: {:ok, context}

        @impl true
        def review_tool(_event, _context, _opts) do
          ref = make_ref()
          # Immediately send approval to self
          send(self(), {:approve, ref})
          {:async, ref, %{quick: true}}
        end

        @impl true
        def await(ref, timeout) do
          receive do
            {:approve, ^ref} -> {:ok, :allow}
          after
            timeout -> {:error, :timeout}
          end
        end
      end

      event = %{tool_name: "test_tool", arguments: %{}, call_id: "call_1"}
      context = %{thread: nil, metadata: %{}}

      # This should auto-await and return :allow
      assert :allow = Approvals.review_tool(QuickAsyncHook, event, context, timeout: 1000)
    end

    test "handles async timeout" do
      event = %{tool_name: "test_tool", arguments: %{}, call_id: "call_1"}
      context = %{thread: nil, metadata: %{}}

      # This should timeout and return denial
      assert {:deny, "approval timeout"} =
               Approvals.review_tool(AsyncTimeoutHook, event, context, timeout: 100)
    end
  end

  describe "telemetry" do
    setup do
      :telemetry.attach_many(
        "test-approval-handler",
        [
          [:codex, :approval, :requested],
          [:codex, :approval, :approved],
          [:codex, :approval, :denied],
          [:codex, :approval, :timeout]
        ],
        fn event_name, measurements, metadata, _config ->
          send(self(), {:telemetry, event_name, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("test-approval-handler")
      end)

      :ok
    end

    test "emits requested and approved events for sync allow" do
      event = %{tool_name: "test_tool", arguments: %{}, call_id: "call_1"}
      context = %{thread: nil, metadata: %{}}

      Approvals.review_tool(SyncAllowHook, event, context)

      assert_receive {:telemetry, [:codex, :approval, :requested], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.tool == "test_tool"
      assert metadata.call_id == "call_1"

      assert_receive {:telemetry, [:codex, :approval, :approved], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.tool == "test_tool"
    end

    test "emits requested and denied events for sync deny" do
      event = %{tool_name: "test_tool", arguments: %{}, call_id: "call_1"}
      context = %{thread: nil, metadata: %{}}

      Approvals.review_tool(SyncDenyHook, event, context)

      assert_receive {:telemetry, [:codex, :approval, :requested], _measurements, _metadata}
      assert_receive {:telemetry, [:codex, :approval, :denied], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.reason == "blocked by policy"
    end

    test "emits timeout event for async timeout" do
      event = %{tool_name: "test_tool", arguments: %{}, call_id: "call_1"}
      context = %{thread: nil, metadata: %{}}

      # This will timeout and emit telemetry
      {:deny, "approval timeout"} =
        Approvals.review_tool(AsyncTimeoutHook, event, context, timeout: 50)

      # Check for telemetry events
      assert_receive {:telemetry, [:codex, :approval, :requested], _measurements, _metadata}
      assert_receive {:telemetry, [:codex, :approval, :timeout], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.tool == "test_tool"
    end
  end

  describe "backwards compatibility" do
    test "supports StaticPolicy allow via dispatcher" do
      event = %{tool_name: "test_tool", arguments: %{}, call_id: "call_1"}
      context = %{thread: nil, metadata: %{}}

      policy = StaticPolicy.allow()
      assert :allow = Approvals.review_tool(policy, event, context)
    end

    test "supports StaticPolicy deny via dispatcher" do
      event = %{tool_name: "test_tool", arguments: %{}, call_id: "call_1"}
      context = %{thread: nil, metadata: %{}}

      policy = StaticPolicy.deny(reason: "test blocked")
      assert {:deny, "test blocked"} = Approvals.review_tool(policy, event, context)
    end

    test "allows when policy is nil" do
      event = %{tool_name: "test_tool", arguments: %{}, call_id: "call_1"}
      context = %{thread: nil, metadata: %{}}

      assert :allow = Approvals.review_tool(nil, event, context)
    end
  end
end

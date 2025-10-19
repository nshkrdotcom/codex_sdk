defmodule Codex.ToolsTest do
  use ExUnit.Case, async: true

  alias Codex.Tools

  setup do
    Tools.reset!()
    Tools.reset_metrics()

    on_exit(fn ->
      Tools.reset!()
      Tools.reset_metrics()
    end)

    :ok
  end

  defmodule SampleTool do
    use Codex.Tool, name: "sample", description: "Sample echo tool"

    @impl true
    def invoke(%{"input" => input}, _context), do: {:ok, %{"echo" => input}}
  end

  test "register stores tool metadata and returns handle" do
    assert {:ok, handle} = Tools.register(SampleTool, name: "sample")

    assert handle.name == "sample"
    assert handle.module == SampleTool

    assert {:ok, info} = Tools.lookup("sample")
    assert info.metadata.description == "Sample echo tool"
  end

  test "invoke dispatches to registered tool module" do
    Tools.register(SampleTool, name: "sample")

    assert {:ok, %{"echo" => "ping"}} =
             Tools.invoke("sample", %{"input" => "ping"}, %{thread_id: "thread_1"})
  end

  test "deregister removes tool" do
    {:ok, handle} = Tools.register(SampleTool, name: "sample")

    assert :ok = Tools.deregister(handle)
    assert {:error, :not_found} = Tools.lookup("sample")
  end

  test "duplicate registration returns error" do
    :ok = Tools.reset!()
    assert {:ok, _} = Tools.register(SampleTool, name: "sample")
    assert {:error, {:already_registered, "sample"}} = Tools.register(SampleTool, name: "sample")
  end

  defmodule ResultTool do
    use Codex.Tool, name: "result_tool", description: "returns configurable responses"

    @impl true
    def invoke(%{"mode" => "ok"}, _ctx), do: {:ok, %{"status" => "ok"}}
    def invoke(%{"mode" => "error"}, _ctx), do: {:error, {:failed, :oops}}
  end

  test "metrics captures success and failure counts" do
    {:ok, _} = Tools.register(ResultTool, name: "result_tool")

    assert {:ok, %{"status" => "ok"}} =
             Tools.invoke("result_tool", %{"mode" => "ok"}, %{thread_id: "t1"})

    assert {:error, {:failed, :oops}} =
             Tools.invoke("result_tool", %{"mode" => "error"}, %{thread_id: "t1"})

    metrics = Tools.metrics()

    assert metrics["result_tool"].success == 1
    assert metrics["result_tool"].failure == 1
    assert metrics["result_tool"].last_error == {:failed, :oops}
    assert metrics["result_tool"].total_latency_ms >= metrics["result_tool"].last_latency_ms
  end

  test "reset_metrics clears accumulated counters" do
    {:ok, _} = Tools.register(ResultTool, name: "result_tool")
    :ok = Tools.reset_metrics()

    assert Tools.metrics() == %{}
  end

  test "telemetry events emitted for tool invocations" do
    {:ok, _} = Tools.register(ResultTool, name: "result_tool")

    handler_id = "tool-metrics-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        [
          [:codex, :tool, :start],
          [:codex, :tool, :success],
          [:codex, :tool, :failure]
        ],
        &__MODULE__.forward_tool_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, _} =
             Tools.invoke("result_tool", %{"mode" => "ok"}, %{thread_id: "t1"})

    assert_receive {:telemetry_event, [:codex, :tool, :start], _m, start_metadata}
    assert start_metadata.tool == "result_tool"
    assert start_metadata.originator == :sdk
    assert_receive {:telemetry_event, [:codex, :tool, :success], measurements, metadata}

    assert is_integer(measurements.duration_ms)
    assert metadata.tool == "result_tool"
    assert metadata.retry? == false
    assert metadata.originator == :sdk

    assert {:error, _} =
             Tools.invoke("result_tool", %{"mode" => "error"}, %{thread_id: "t1"})

    assert_receive {:telemetry_event, [:codex, :tool, :start], _m, retry_metadata}
    assert retry_metadata.originator == :sdk

    assert_receive {:telemetry_event, [:codex, :tool, :failure], failure_measurements,
                    failure_metadata}

    assert is_integer(failure_measurements.duration_ms)
    assert failure_metadata.tool == "result_tool"
    assert failure_metadata.error == {:failed, :oops}
    assert failure_metadata.originator == :sdk
  end

  def forward_tool_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end
end

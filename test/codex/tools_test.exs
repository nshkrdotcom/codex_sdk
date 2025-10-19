defmodule Codex.ToolsTest do
  use ExUnit.Case, async: true

  alias Codex.Tools

  setup do
    Tools.reset!()
    on_exit(fn -> Tools.reset!() end)
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
end

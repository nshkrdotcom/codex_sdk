defmodule Codex.FunctionToolTest do
  use ExUnit.Case, async: true

  alias Codex.Events
  alias Codex.FunctionTool
  alias Codex.Options
  alias Codex.Thread
  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.ToolOutput
  alias Codex.Tools
  alias Codex.Turn.Result, as: TurnResult

  setup do
    Tools.reset!()
    Tools.reset_metrics()

    on_exit(fn ->
      Tools.reset!()
      Tools.reset_metrics()
    end)

    :ok
  end

  defmodule AddTool do
    use FunctionTool,
      name: "add_numbers",
      description: "Adds two numbers together",
      parameters: %{left: :number, right: :number},
      handler: fn %{"left" => left, "right" => right}, _ctx ->
        {:ok, %{"sum" => left + right}}
      end
  end

  test "function_tool builds strict schema and invokes handler" do
    assert {:ok, _} = Tools.register(AddTool)

    assert {:ok, info} = Tools.lookup("add_numbers")

    assert info.metadata.schema == %{
             "type" => "object",
             "properties" => %{
               "left" => %{"type" => "number"},
               "right" => %{"type" => "number"}
             },
             "required" => ["left", "right"],
             "additionalProperties" => false
           }

    assert {:ok, %{"sum" => 5}} =
             Tools.invoke("add_numbers", %{"left" => 2, "right" => 3}, %{thread_id: "t1"})
  end

  defmodule MaybeTool do
    use FunctionTool,
      name: "maybe_tool",
      parameters: %{value: :string},
      enabled?: fn ctx -> Map.get(ctx, :allow?, false) end,
      handler: fn args, _ctx -> {:ok, args} end
  end

  test "enabled? callback can disable tool" do
    assert {:ok, _} = Tools.register(MaybeTool)

    assert {:error, {:tool_disabled, "maybe_tool"}} =
             Tools.invoke("maybe_tool", %{"value" => "no"}, %{})

    assert {:ok, %{"value" => "yes"}} =
             Tools.invoke("maybe_tool", %{"value" => "yes"}, %{allow?: true})
  end

  defmodule FailingTool do
    use FunctionTool,
      name: "failing_tool",
      parameters: %{},
      on_error: fn reason, _ctx -> {:ok, %{"handled" => inspect(reason)}} end,
      handler: fn _args, _ctx -> {:error, :boom} end
  end

  test "on_error handler converts failures into outputs" do
    assert {:ok, _} = Tools.register(FailingTool)

    assert {:ok, %{"handled" => handled}} =
             Tools.invoke("failing_tool", %{}, %{thread_id: "t2"})

    assert handled =~ "boom"
  end

  defmodule StructuredTool do
    use FunctionTool,
      name: "structured_tool",
      parameters: %{},
      handler: fn _args, _ctx ->
        {:ok,
         [
           ToolOutput.text("hello"),
           ToolOutput.image(url: "https://example.com/image.png", detail: "high"),
           ToolOutput.file(data: "abc123", filename: "log.txt")
         ]}
      end
  end

  test "structured tool outputs are normalized for runner" do
    assert {:ok, _} = Tools.register(StructuredTool)

    {:ok, codex_opts} = Options.new(%{api_key: "test"})
    {:ok, thread_opts} = ThreadOptions.new(%{})
    thread = Thread.build(codex_opts, thread_opts)

    event = %Events.ToolCallRequested{
      thread_id: "thread",
      turn_id: "turn",
      call_id: "call-1",
      tool_name: "structured_tool",
      arguments: %{}
    }

    result = %TurnResult{
      thread: thread,
      events: [event],
      final_response: nil,
      usage: %{},
      raw: %{}
    }

    assert {:ok, updated} = Thread.handle_tool_requests(result, 1, %{})

    [%{call_id: "call-1", output: outputs} = payload] = Map.get(updated.raw, :tool_outputs)
    assert payload.tool_name == "structured_tool"

    assert outputs == [
             %{"type" => "input_text", "text" => "hello"},
             %{
               "type" => "input_image",
               "image_url" => %{"url" => "https://example.com/image.png", "detail" => "high"}
             },
             %{
               "type" => "input_file",
               "file_data" => %{"data" => "abc123", "filename" => "log.txt"}
             }
           ]
  end
end

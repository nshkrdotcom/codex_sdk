defmodule Codex.ApprovalsSafetyTest do
  use ExUnit.Case, async: true

  alias Codex.Approvals.StaticPolicy
  alias Codex.Options
  alias Codex.RunResultStreaming
  alias Codex.StreamEvent.{RunItem, ToolApproval}
  alias Codex.Thread
  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.Tools
  alias Codex.Tools.ComputerTool
  alias Codex.TestSupport.FixtureScripts

  defmodule MathTool do
    use Codex.Tool, name: "math_tool", description: "adds numbers"

    @impl true
    def invoke(%{"x" => x, "y" => y}, _ctx), do: {:ok, %{"sum" => x + y}}
  end

  setup do
    Tools.reset!()
    {:ok, _} = Tools.register(MathTool, name: "math_tool")
    :ok
  end

  test "denied tool approval emits ToolApproval event and halts streaming" do
    {script_path, state_file} =
      FixtureScripts.sequential_fixtures(["thread_tool_requires_approval.jsonl"])

    on_exit(fn ->
      File.rm_rf(script_path)
      File.rm_rf(state_file)
    end)

    {:ok, codex_opts} =
      Options.new(%{
        api_key: "test",
        codex_path_override: script_path
      })

    {:ok, thread_opts} = ThreadOptions.new(%{approval_policy: StaticPolicy.deny()})
    thread = Thread.build(codex_opts, thread_opts)

    {:ok, result} = Thread.run_streamed(thread, "needs approval")

    events = result |> RunResultStreaming.events() |> Enum.to_list()

    assert Enum.any?(events, fn
             %ToolApproval{decision: :deny, tool_name: "math_tool"} -> true
             _ -> false
           end)

    raw_events =
      events
      |> Enum.flat_map(fn
        %RunItem{event: event} -> [event]
        _ -> []
      end)

    assert Enum.any?(raw_events, &match?(%Codex.Events.ToolCallRequested{}, &1))
    assert Enum.count(raw_events, &match?(%Codex.Events.TurnStarted{}, &1)) == 1
  end

  test "computer tool safety callback can deny execution" do
    metadata = %{
      safety: fn _args, _ctx, _meta -> {:deny, "unsafe"} end,
      executor: fn _args, _ctx, _meta -> {:ok, :ok} end
    }

    context = %{metadata: metadata}

    assert {:error, {:computer_denied, "unsafe"}} =
             ComputerTool.invoke(%{"action" => "delete"}, context)
  end
end

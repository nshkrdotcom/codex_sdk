#!/usr/bin/env mix run

defmodule Examples.ToolBridging do
  @moduledoc false

  alias Codex.Approvals.StaticPolicy

  def auto_run_example do
    Codex.Tools.reset!()

    defmodule MathTool do
      use Codex.Tool, name: "math_tool", description: "adds two numbers"

      @impl true
      def invoke(%{"x" => x, "y" => y}, _context), do: {:ok, %{"sum" => x + y}}
    end

    {:ok, _handle} = Codex.Tools.register(MathTool)

    {:ok, thread} =
      Codex.start_thread(approval_policy: StaticPolicy.allow())

    {:ok, result} =
      Codex.Thread.run_auto(thread, "Ask the math tool to add 4 and 5", max_attempts: 2)

    IO.inspect(result.raw[:tool_outputs], label: "tool outputs captured by SDK")
    IO.inspect(result.raw[:tool_failures], label: "tool failures captured by SDK")
    IO.inspect(result.thread.pending_tool_outputs, label: "pending outputs after turn")
    IO.inspect(result.thread.pending_tool_failures, label: "pending failures after turn")
  end
end

Examples.ToolBridging.auto_run_example()

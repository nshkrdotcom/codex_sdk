#!/usr/bin/env mix run

defmodule Examples.AgentRunner do
  @moduledoc false

  def run do
    {:ok, thread} = Codex.start_thread()

    {:ok, result} =
      Codex.AgentRunner.run(thread, "Plan a short checklist",
        agent: %{instructions: "Respond with a concise checklist"},
        run_config: %{max_turns: 3}
      )

    IO.inspect(result.final_response, label: "agent runner response")
    IO.inspect(result.attempts, label: "turns executed")
  end
end

Examples.AgentRunner.run()

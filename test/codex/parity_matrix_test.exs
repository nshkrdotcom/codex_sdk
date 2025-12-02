defmodule Codex.ParityMatrixTest do
  use ExUnit.Case, async: true

  alias Codex.TestSupport.ParityMatrix

  @expected_categories [
    :runner_loop,
    :guardrails,
    :function_tools,
    :hosted_tools,
    :mcp,
    :sessions,
    :streaming,
    :tracing_usage,
    :approvals_safety
  ]

  test "parity matrix enumerates coverage across categories" do
    entries = ParityMatrix.entries()

    assert Enum.map(entries, & &1.category) == @expected_categories

    Enum.each(entries, fn %{status: status, fixtures: fixtures, tests: tests} = entry ->
      assert status in [:complete, :partial, :pending]
      assert is_list(fixtures)
      assert is_list(tests)

      Enum.each(fixtures, fn fixture ->
        path = Path.join(["integration", "fixtures", "python", fixture])
        assert File.exists?(path), "missing fixture #{fixture} for #{inspect(entry.category)}"
      end)

      Enum.each(tests, fn mod ->
        assert is_atom(mod), "test module #{inspect(mod)} not an atom"
      end)
    end)
  end
end

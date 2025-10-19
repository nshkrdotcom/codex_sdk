defmodule Codex.Approvals do
  @moduledoc """
  Approval helpers invoked by the auto-run pipeline when actions require consent.
  """

  alias Codex.Approvals.StaticPolicy

  @type decision :: :allow | {:deny, String.t()}

  @doc """
  Reviews a tool invocation given the configured policy.
  """
  @spec review_tool(term(), map(), map()) :: decision()
  def review_tool(nil, _event, _context), do: :allow

  def review_tool(%StaticPolicy{} = policy, event, context) do
    StaticPolicy.review_tool(policy, event, context)
  end

  def review_tool(module, event, context) when is_atom(module) do
    module.review_tool(event, context)
  end
end

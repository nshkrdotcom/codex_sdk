defmodule Codex.GuardrailError do
  @moduledoc """
  Error raised when a guardrail rejects or trips during execution.
  """

  defexception [:stage, :guardrail, :message, :type]

  @type stage :: :input | :output | :tool_input | :tool_output
  @type type :: :tripwire | :reject

  @impl true
  def exception(opts) do
    stage = Keyword.get(opts, :stage)
    guardrail = Keyword.get(opts, :guardrail)
    type = Keyword.get(opts, :type, :tripwire)
    message = Keyword.get(opts, :message, "guardrail #{guardrail} triggered")

    %__MODULE__{
      stage: stage,
      guardrail: guardrail,
      message: message,
      type: type
    }
  end
end

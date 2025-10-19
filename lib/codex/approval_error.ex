defmodule Codex.ApprovalError do
  @moduledoc """
  Error returned when an approval policy denies a tool invocation.
  """

  defexception [:message, :tool, :reason]

  @type t :: %__MODULE__{message: String.t(), tool: String.t(), reason: String.t() | nil}

  @spec new(String.t(), String.t()) :: t()
  def new(tool, reason) do
    %__MODULE__{tool: tool, reason: reason, message: "approval denied for #{tool}: #{reason}"}
  end
end

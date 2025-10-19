defmodule Codex.Error do
  @moduledoc """
  Base error struct for Codex failures.
  """

  defexception [:message, :kind, :details]

  @type t :: %__MODULE__{message: String.t(), kind: atom(), details: map()}

  @spec new(atom(), String.t(), map()) :: t()
  def new(kind, message, details \\ %{}) do
    %__MODULE__{kind: kind, message: message, details: details}
  end
end

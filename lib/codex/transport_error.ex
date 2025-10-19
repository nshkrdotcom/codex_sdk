defmodule Codex.TransportError do
  @moduledoc """
  Raised when the codex executable exits unexpectedly.
  """

  defexception [:message, :exit_status, :stderr]

  @type t :: %__MODULE__{message: String.t(), exit_status: integer(), stderr: String.t() | nil}

  @spec new(integer(), keyword()) :: t()
  def new(status, opts \\ []) do
    stderr = Keyword.get(opts, :stderr)
    message = Keyword.get(opts, :message, "codex executable exited with status #{status}")

    %__MODULE__{exit_status: status, stderr: stderr, message: message}
  end
end

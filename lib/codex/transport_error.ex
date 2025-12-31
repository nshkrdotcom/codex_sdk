defmodule Codex.TransportError do
  @moduledoc """
  Raised when the codex executable exits unexpectedly.

  The `retryable?` field indicates whether the error is transient and the
  operation can be safely retried. This is used by `Codex.Retry` to determine
  whether to attempt automatic retries.
  """

  defexception [:message, :exit_status, :stderr, :retryable?]

  @type t :: %__MODULE__{
          message: String.t(),
          exit_status: integer(),
          stderr: String.t() | nil,
          retryable?: boolean()
        }

  @doc """
  Creates a new `TransportError`.

  ## Options

    * `:stderr` - Standard error output from the process
    * `:message` - Custom error message
    * `:retryable?` - Whether the error is retryable (default: inferred from exit status)
  """
  @spec new(integer(), keyword()) :: t()
  def new(status, opts \\ []) do
    stderr = Keyword.get(opts, :stderr)
    message = Keyword.get(opts, :message, "codex executable exited with status #{status}")
    retryable? = Keyword.get_lazy(opts, :retryable?, fn -> retryable_status?(status) end)

    %__MODULE__{
      exit_status: status,
      stderr: stderr,
      message: message,
      retryable?: retryable?
    }
  end

  @doc """
  Determines if an exit status indicates a retryable error.

  Retryable statuses include:
  - Signal-based exits (128+) for SIGTERM, SIGKILL, SIGPIPE
  - Exit code 75 (EX_TEMPFAIL)
  - Exit code 69 (EX_UNAVAILABLE)
  """
  @spec retryable_status?(integer()) :: boolean()
  def retryable_status?(status) when is_integer(status) do
    cond do
      # Signal-based exits: 128 + signal number
      # SIGTERM (15), SIGKILL (9), SIGPIPE (13) are typically transient
      status == 128 + 15 -> true
      status == 128 + 9 -> true
      status == 128 + 13 -> true
      # EX_TEMPFAIL (75) - temporary failure
      status == 75 -> true
      # EX_UNAVAILABLE (69) - service unavailable
      status == 69 -> true
      true -> false
    end
  end
end

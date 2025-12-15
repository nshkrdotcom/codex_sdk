defmodule Codex.Transport do
  @moduledoc """
  Behaviour for Codex transport implementations.

  Transports handle the communication protocol between the SDK and the Codex runtime.
  """

  @type thread :: Codex.Thread.t()
  @type input :: String.t()
  @type turn_opts :: map() | keyword()
  @type turn_result :: Codex.Turn.Result.t()
  @type event_stream :: Enumerable.t()

  @doc """
  Executes a single turn and returns the accumulated result.
  """
  @callback run_turn(thread(), input(), turn_opts()) :: {:ok, turn_result()} | {:error, term()}

  @doc """
  Executes a turn and returns a stream of events.
  """
  @callback run_turn_streamed(thread(), input(), turn_opts()) ::
              {:ok, event_stream()} | {:error, term()}

  @doc """
  Interrupts a running turn.

  Optional for transports that don't support it.
  """
  @callback interrupt(thread(), turn_id :: String.t()) :: :ok | {:error, term()}

  @optional_callbacks interrupt: 2
end

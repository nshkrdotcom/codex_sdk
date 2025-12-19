defmodule Codex.RunResultStreaming do
  @moduledoc """
  Streaming result wrapper exposing semantic and raw event streams plus
  cancellation controls.
  """

  alias Codex.RunResultStreaming.Control
  alias Codex.StreamEvent.RunItem
  alias Codex.StreamQueue

  @enforce_keys [:queue, :control, :start_fun]
  defstruct queue: nil, control: nil, start_fun: nil

  @type t :: %__MODULE__{
          queue: pid(),
          control: pid(),
          start_fun: (-> any())
        }

  @doc false
  @spec new(pid(), pid(), (-> any())) :: t()
  def new(queue, control, start_fun) do
    %__MODULE__{queue: queue, control: control, start_fun: start_fun}
  end

  @doc """
  Returns a stream of semantic events. Automatically starts the underlying
  streaming process on first invocation.
  """
  @spec events(t()) :: Enumerable.t()
  def events(%__MODULE__{} = result) do
    ensure_started(result)
    StreamQueue.stream(result.queue)
  end

  @doc """
  Returns a stream of the raw Codex events.
  """
  @spec raw_events(t()) :: Enumerable.t()
  def raw_events(%__MODULE__{} = result) do
    events(result)
    |> Stream.filter(&match?(%RunItem{}, &1))
    |> Stream.map(& &1.event)
  end

  @doc """
  Pops the next semantic event from the queue, blocking up to `timeout`.

  Returns `{:error, reason}` if the stream terminates with an error.
  """
  @spec pop(t(), timeout()) :: {:ok, term()} | {:error, term()} | :done
  def pop(%__MODULE__{} = result, timeout \\ 5_000) do
    ensure_started(result)
    StreamQueue.pop(result.queue, timeout)
  end

  @doc """
  Cancels the streaming run.

  Modes:
    * `:immediate` - stop immediately
    * `:after_turn` - finish the current turn then halt
  """
  @spec cancel(t(), :immediate | :after_turn) :: :ok
  def cancel(%__MODULE__{control: control}, mode \\ :immediate) do
    Control.cancel(control, mode)
  end

  @doc """
  Returns the aggregated usage captured so far.
  """
  @spec usage(t()) :: map()
  def usage(%__MODULE__{control: control}) do
    Control.usage(control)
  end

  defp ensure_started(%__MODULE__{control: control, start_fun: fun}) do
    Control.start_if_needed(control, fun)
    :ok
  end
end

defmodule Codex.RunResultStreaming.Control do
  @moduledoc false

  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    initial = %{
      started?: false,
      producer_pid: nil,
      cancel: nil,
      usage: %{}
    }

    Agent.start_link(fn -> initial end, opts)
  end

  @spec start_if_needed(pid(), (-> any())) :: :ok | {:error, term()}
  def start_if_needed(control, starter) when is_pid(control) and is_function(starter, 0) do
    Agent.get_and_update(control, fn %{started?: started?} = state ->
      if started? do
        {:ok, state}
      else
        {:ok, pid} = Task.start_link(starter)
        {:ok, %{state | started?: true, producer_pid: pid}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      _ -> :ok
    end
  end

  @spec cancel(pid(), :immediate | :after_turn) :: :ok
  def cancel(control, mode) when mode in [:immediate, :after_turn] do
    Agent.update(control, &Map.put(&1, :cancel, mode))
  end

  @spec cancel_mode(pid()) :: :immediate | :after_turn | nil
  def cancel_mode(control) do
    Agent.get(control, & &1.cancel)
  end

  @spec put_usage(pid(), map()) :: :ok
  def put_usage(control, usage) when is_map(usage) do
    Agent.update(control, &Map.put(&1, :usage, usage))
  end

  @spec usage(pid()) :: map()
  def usage(control) do
    Agent.get(control, &(Map.get(&1, :usage) || %{}))
  end
end

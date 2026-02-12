defmodule Codex.RunResultStreaming do
  @moduledoc """
  Streaming result wrapper exposing semantic and raw event streams plus
  cancellation controls.
  """

  alias Codex.Config.Defaults
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
  def pop(%__MODULE__{} = result, timeout \\ Defaults.stream_queue_pop_timeout_ms()) do
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

  defp ensure_started(%__MODULE__{control: control, start_fun: fun, queue: queue}) do
    Control.start_if_needed(control, fun, queue)
    :ok
  end
end

defmodule Codex.RunResultStreaming.Control do
  @moduledoc false

  alias Codex.StreamQueue

  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    initial = %{
      started?: false,
      producer_pid: nil,
      queue: nil,
      cancel: nil,
      cancel_handler: nil,
      usage: %{}
    }

    Agent.start_link(fn -> initial end, opts)
  end

  @spec attach_queue(pid(), pid()) :: :ok
  def attach_queue(control, queue) when is_pid(control) and is_pid(queue) do
    Agent.update(control, &Map.put(&1, :queue, queue))
  end

  @spec set_cancel_handler(pid(), (:immediate | :after_turn -> any())) :: :ok
  def set_cancel_handler(control, handler)
      when is_pid(control) and is_function(handler, 1) do
    Agent.update(control, &Map.put(&1, :cancel_handler, handler))
  end

  @spec start_if_needed(pid(), (-> any()), pid()) :: :ok
  def start_if_needed(control, starter, queue)
      when is_pid(control) and is_function(starter, 0) and is_pid(queue) do
    Agent.get_and_update(control, &do_start_if_needed(&1, starter, queue))
    :ok
  end

  defp do_start_if_needed(%{started?: true} = state, _starter, queue) do
    state = maybe_set_queue(state, queue)
    {:ok, state}
  end

  defp do_start_if_needed(%{started?: false, cancel: :immediate} = state, _starter, queue) do
    StreamQueue.close(queue)
    {:ok, %{state | started?: true, queue: queue}}
  end

  defp do_start_if_needed(%{started?: false} = state, starter, queue) do
    wrapped = wrap_starter(starter, queue)
    {:ok, pid} = start_producer(wrapped)
    {:ok, %{state | started?: true, producer_pid: pid, queue: queue}}
  end

  @spec cancel(pid(), :immediate | :after_turn) :: :ok
  def cancel(control, mode) when mode in [:immediate, :after_turn] do
    {queue, producer_pid, cancel_handler} =
      Agent.get_and_update(control, fn state ->
        {{state.queue, state.producer_pid, state.cancel_handler}, Map.put(state, :cancel, mode)}
      end)

    maybe_invoke_cancel_handler(cancel_handler, mode)

    if mode == :immediate do
      if is_pid(queue), do: StreamQueue.close(queue)
      if is_pid(producer_pid), do: Process.exit(producer_pid, :kill)
    end

    :ok
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

  defp maybe_set_queue(%{queue: nil} = state, queue), do: %{state | queue: queue}
  defp maybe_set_queue(state, _queue), do: state

  defp maybe_invoke_cancel_handler(nil, _mode), do: :ok

  defp maybe_invoke_cancel_handler(handler, mode) when is_function(handler, 1) do
    _ = handler.(mode)
    :ok
  rescue
    _ -> :ok
  end

  defp wrap_starter(starter, queue) do
    fn ->
      try do
        starter.()
      rescue
        error ->
          StreamQueue.close(queue, {:error, error})
      catch
        kind, reason ->
          StreamQueue.close(queue, {:error, {kind, reason}})
      after
        StreamQueue.close(queue)
      end
    end
  end

  @spec start_producer((-> any())) :: {:ok, pid()}
  defp start_producer(starter) do
    case Task.Supervisor.start_child(Codex.TaskSupervisor, starter) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, _} -> Task.start(starter)
    end
  catch
    :exit, _ -> Task.start(starter)
  end
end

defmodule Codex.TestSupport.AppServerSubprocess do
  @moduledoc false

  import Kernel, except: [send: 2]

  @behaviour Codex.IO.Transport

  use GenServer

  defstruct [:owner, :subscriber, :send_result, :notify_stop]

  @impl true
  def start(opts), do: GenServer.start(__MODULE__, opts)

  @impl true
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def send(pid, data) when is_pid(pid) do
    GenServer.call(pid, {:send, data})
  end

  @impl true
  def subscribe(pid, subscriber) when is_pid(pid) and is_pid(subscriber) do
    subscribe(pid, subscriber, :legacy)
  end

  @impl true
  def subscribe(pid, subscriber, tag) when is_pid(pid) and is_pid(subscriber) do
    GenServer.call(pid, {:subscribe, subscriber, tag})
  end

  @impl true
  def close(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal)
  catch
    :exit, _ -> :ok
  end

  @impl true
  def force_close(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal)
    :ok
  catch
    :exit, _ -> :ok
  end

  @impl true
  def status(pid) when is_pid(pid) do
    if Process.alive?(pid), do: :connected, else: :disconnected
  end

  @impl true
  def end_input(_pid), do: :ok

  @impl true
  def stderr(_pid), do: ""

  @impl true
  def init(opts) do
    owner = Keyword.fetch!(opts, :owner)
    subscriber = Keyword.fetch!(opts, :subscriber)
    send_result = Keyword.get(opts, :send_result, :ok)
    notify_stop = Keyword.get(opts, :notify_stop, false)

    {subscriber_pid, tag} =
      case subscriber do
        {pid, ref} when is_pid(pid) and is_reference(ref) -> {pid, ref}
        pid when is_pid(pid) -> {pid, :legacy}
      end

    Kernel.send(owner, {:app_server_subprocess_started, subscriber_pid, tag})

    {:ok,
     %__MODULE__{
       owner: owner,
       subscriber: {subscriber_pid, tag},
       send_result: send_result,
       notify_stop: notify_stop
     }}
  end

  @impl true
  def handle_call({:send, data}, _from, state) do
    {subscriber_pid, _tag} = state.subscriber

    Kernel.send(
      state.owner,
      {:app_server_subprocess_send, subscriber_pid, IO.iodata_to_binary(data)}
    )

    {:reply, state.send_result, state}
  end

  def handle_call({:subscribe, pid, tag}, _from, state) do
    {:reply, :ok, %{state | subscriber: {pid, tag}}}
  end

  @impl true
  def terminate(_reason, state) do
    if state.notify_stop do
      {subscriber_pid, _tag} = state.subscriber
      Kernel.send(state.owner, {:app_server_subprocess_stopped, subscriber_pid, self()})
    end

    :ok
  end
end

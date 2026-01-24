defmodule Codex.TestSupport.AppServerSubprocess do
  @moduledoc false

  @behaviour Codex.AppServer.Subprocess

  @impl true
  def start(_command, _run_opts, opts) do
    owner = Keyword.fetch!(opts, :owner)
    os_pid = System.unique_integer([:positive])

    exec_pid =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    send(owner, {:app_server_subprocess_started, self(), os_pid})
    {:ok, exec_pid, os_pid}
  end

  @impl true
  def send(_pid, data, opts) do
    owner = Keyword.fetch!(opts, :owner)
    send(owner, {:app_server_subprocess_send, self(), IO.iodata_to_binary(data)})

    case Keyword.get(opts, :send_result, :ok) do
      :ok -> :ok
      {:error, _} = error -> error
    end
  end

  @impl true
  def stop(pid, opts) do
    if is_pid(pid) and Process.alive?(pid) do
      send(pid, :stop)
    end

    owner = Keyword.get(opts, :owner)

    if owner && Keyword.get(opts, :notify_stop, false) do
      send(owner, {:app_server_subprocess_stopped, self(), pid})
    end

    :ok
  end
end

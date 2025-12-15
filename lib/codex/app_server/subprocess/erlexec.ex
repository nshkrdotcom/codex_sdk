defmodule Codex.AppServer.Subprocess.Erlexec do
  @moduledoc false

  @behaviour Codex.AppServer.Subprocess

  @impl true
  def start(command, run_opts, _opts) do
    :exec.run(command, run_opts)
  end

  @impl true
  def send(pid, data, _opts) do
    :exec.send(pid, IO.iodata_to_binary(data))
  rescue
    _ -> {:error, :send_failed}
  end

  @impl true
  def stop(pid, _opts) do
    if is_pid(pid) and Process.alive?(pid) do
      :exec.stop(pid)
    else
      :ok
    end
  rescue
    _ -> :ok
  end
end

defmodule Codex.Runtime.Erlexec do
  @moduledoc """
  Unified erlexec startup for the SDK-local subprocess families that still own
  raw process lifecycle directly.

  The shared non-PTY command and common session lanes live in
  `cli_subprocess_core`. This helper remains for raw PTY and provider-native
  control surfaces such as `Codex.CLI.Session`, app-server, and MCP stdio.
  """

  @exec_wait_attempts 20
  @exec_wait_delay_ms 50

  @spec ensure_started() :: :ok | {:error, term()}
  def ensure_started do
    with :ok <- ensure_application_started() do
      ensure_exec_worker()
    end
  end

  defp ensure_application_started do
    case Application.ensure_all_started(:erlexec) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, {:erlexec, {:already_started, _}}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_exec_worker do
    case wait_for_exec_worker(@exec_wait_attempts) do
      :ok ->
        :ok

      :error ->
        recover_missing_exec_worker()
    end
  end

  defp recover_missing_exec_worker do
    if exec_app_alive?() do
      {:error, :exec_not_running}
    else
      with :ok <- restart_application(),
           :ok <- wait_for_exec_worker(@exec_wait_attempts) do
        :ok
      else
        :error -> {:error, :exec_not_running}
        {:error, _} = error -> error
      end
    end
  end

  defp wait_for_exec_worker(0) do
    if exec_worker_alive?(), do: :ok, else: :error
  end

  defp wait_for_exec_worker(attempts_remaining) when attempts_remaining > 0 do
    if exec_worker_alive?() do
      :ok
    else
      Process.sleep(@exec_wait_delay_ms)
      wait_for_exec_worker(attempts_remaining - 1)
    end
  end

  defp restart_application do
    case Application.stop(:erlexec) do
      :ok -> ensure_application_started()
      {:error, {:not_started, :erlexec}} -> ensure_application_started()
      {:error, {:not_started, _app}} -> ensure_application_started()
      {:error, reason} -> {:error, reason}
    end
  end

  defp exec_worker_alive? do
    case Process.whereis(:exec) do
      pid when is_pid(pid) -> Process.alive?(pid)
      _ -> false
    end
  end

  defp exec_app_alive? do
    case Process.whereis(:exec_app) do
      pid when is_pid(pid) -> Process.alive?(pid)
      _ -> false
    end
  end
end

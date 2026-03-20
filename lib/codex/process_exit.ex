defmodule Codex.ProcessExit do
  @moduledoc false

  alias CliSubprocessCore.ProcessExit, as: CoreProcessExit

  @spec exit_status(term()) :: {:ok, integer()} | :unknown
  def exit_status(reason)

  def exit_status(:normal), do: {:ok, 0}
  def exit_status(%CoreProcessExit{status: :success}), do: {:ok, 0}

  def exit_status(%CoreProcessExit{status: :exit, code: status}) when is_integer(status),
    do: {:ok, status}

  def exit_status(%CoreProcessExit{status: :signal, signal: signal}) do
    {:ok, 128 + signal_to_int(signal)}
  end

  def exit_status(%CoreProcessExit{reason: reason}), do: exit_status(reason)
  def exit_status({:exit_code, status}) when is_integer(status), do: {:ok, status}

  def exit_status({:exit_status, status}) when is_integer(status) do
    {:ok, normalize_wait_status(status)}
  end

  def exit_status({:signal, signal, _core?}) do
    {:ok, 128 + signal_to_int(signal)}
  end

  def exit_status(status) when is_integer(status) do
    {:ok, normalize_wait_status(status)}
  end

  def exit_status({:shutdown, reason}), do: exit_status(reason)
  def exit_status({:transport, reason}), do: exit_status(reason)
  def exit_status({:send_failed, reason}), do: exit_status(reason)
  def exit_status({:call_exit, reason}), do: exit_status(reason)
  def exit_status({:error, reason}), do: exit_status(reason)
  def exit_status({:exit, reason}), do: exit_status(reason)
  def exit_status({:EXIT, _pid, reason}), do: exit_status(reason)
  def exit_status({reason, {GenServer, :call, _}}), do: exit_status(reason)

  def exit_status({reason, _meta}) do
    if wrapped_exit_reason?(reason) do
      exit_status(reason)
    else
      :unknown
    end
  end

  def exit_status(_reason), do: :unknown

  @spec normalize_reason(term()) :: :normal | {:exit_code, integer()} | term()
  def normalize_reason(reason) do
    case exit_status(reason) do
      {:ok, 0} -> :normal
      {:ok, status} -> {:exit_code, status}
      :unknown -> reason
    end
  end

  @spec normalize_wait_status(integer()) :: integer()
  def normalize_wait_status(raw_status) when is_integer(raw_status) do
    case :exec.status(raw_status) do
      {:status, code} -> code
      {:signal, signal, _core?} -> 128 + signal_to_int(signal)
    end
  rescue
    _ -> raw_status
  end

  defp wrapped_exit_reason?(:normal), do: true
  defp wrapped_exit_reason?(%CoreProcessExit{}), do: true
  defp wrapped_exit_reason?({:exit_code, status}) when is_integer(status), do: true
  defp wrapped_exit_reason?({:exit_status, status}) when is_integer(status), do: true
  defp wrapped_exit_reason?({:signal, _signal, _core?}), do: true
  defp wrapped_exit_reason?(status) when is_integer(status), do: true
  defp wrapped_exit_reason?({:shutdown, reason}), do: wrapped_exit_reason?(reason)
  defp wrapped_exit_reason?({:transport, reason}), do: wrapped_exit_reason?(reason)
  defp wrapped_exit_reason?({:send_failed, reason}), do: wrapped_exit_reason?(reason)
  defp wrapped_exit_reason?({:call_exit, reason}), do: wrapped_exit_reason?(reason)
  defp wrapped_exit_reason?({:error, reason}), do: wrapped_exit_reason?(reason)
  defp wrapped_exit_reason?({:exit, reason}), do: wrapped_exit_reason?(reason)
  defp wrapped_exit_reason?({:EXIT, _pid, reason}), do: wrapped_exit_reason?(reason)
  defp wrapped_exit_reason?({reason, {GenServer, :call, _}}), do: wrapped_exit_reason?(reason)
  defp wrapped_exit_reason?(_reason), do: false

  defp signal_to_int(signal) when is_integer(signal), do: signal

  defp signal_to_int(signal) when is_atom(signal) do
    :exec.signal_to_int(signal)
  rescue
    _ -> 1
  end
end

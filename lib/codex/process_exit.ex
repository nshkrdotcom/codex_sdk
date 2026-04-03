defmodule Codex.ProcessExit do
  @moduledoc false

  alias ExternalRuntimeTransport.ProcessExit, as: CoreProcessExit

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
    case CoreProcessExit.from_reason(raw_status) do
      %CoreProcessExit{status: :success} ->
        0

      %CoreProcessExit{status: :exit, code: code} when is_integer(code) ->
        code

      %CoreProcessExit{status: :signal, signal: signal} ->
        128 + signal_to_int(signal)

      _other ->
        raw_status
    end
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

  defp signal_to_int(signal) when is_atom(signal),
    do: Map.get(signal_numbers(), signal, 1)

  defp signal_numbers do
    %{
      sigabrt: 6,
      sigalrm: 14,
      sigbus: 7,
      sigchld: 17,
      sigcld: 17,
      sigcont: 18,
      sigemt: 7,
      sigfpe: 8,
      sighup: 1,
      sigill: 4,
      siginfo: 29,
      sigint: 2,
      sigio: 29,
      sigiote: 6,
      sigkill: 9,
      siglost: 29,
      sigpipe: 13,
      sigpoll: 29,
      sigprof: 27,
      sigpwr: 30,
      sigquit: 3,
      sigsegv: 11,
      sigstop: 19,
      sigsys: 31,
      sigterm: 15,
      sigtrap: 5,
      sigtstp: 20,
      sigttin: 21,
      sigttou: 22,
      sigurg: 23,
      sigusr1: 10,
      sigusr2: 12,
      sigvtalrm: 26,
      sigwinch: 28,
      sigxcpu: 24,
      sigxfsz: 25
    }
  end
end

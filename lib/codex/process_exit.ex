defmodule Codex.ProcessExit do
  @moduledoc false

  alias CliSubprocessCore.ProcessExit, as: CoreProcessExit

  @spec exit_status(term()) :: {:ok, integer()} | :unknown
  def exit_status(reason)

  def exit_status(:normal), do: {:ok, 0}
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

  def exit_status(reason) do
    if CoreProcessExit.match?(reason) do
      exit_status_from_core(reason)
    else
      exit_status_fallback(reason)
    end
  end

  defp exit_status_from_core(reason) do
    case {CoreProcessExit.status(reason), CoreProcessExit.code(reason),
          CoreProcessExit.signal(reason)} do
      {:success, _code, _signal} -> {:ok, 0}
      {:exit, status, _signal} when is_integer(status) -> {:ok, status}
      {:signal, _code, signal} -> {:ok, 128 + signal_to_int(signal)}
      _other -> exit_status(CoreProcessExit.reason(reason))
    end
  end

  defp exit_status_fallback({:shutdown, reason}), do: exit_status(reason)
  defp exit_status_fallback({:transport, reason}), do: exit_status(reason)
  defp exit_status_fallback({:send_failed, reason}), do: exit_status(reason)
  defp exit_status_fallback({:call_exit, reason}), do: exit_status(reason)
  defp exit_status_fallback({:error, reason}), do: exit_status(reason)
  defp exit_status_fallback({:exit, reason}), do: exit_status(reason)
  defp exit_status_fallback({:EXIT, _pid, reason}), do: exit_status(reason)
  defp exit_status_fallback({reason, {GenServer, :call, _}}), do: exit_status(reason)

  defp exit_status_fallback({reason, _meta}) do
    if wrapped_exit_reason?(reason) do
      exit_status(reason)
    else
      :unknown
    end
  end

  defp exit_status_fallback(_reason), do: :unknown

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
    exit = CoreProcessExit.from_reason(raw_status)

    cond do
      CoreProcessExit.status(exit) == :success ->
        0

      CoreProcessExit.status(exit) == :exit and is_integer(CoreProcessExit.code(exit)) ->
        CoreProcessExit.code(exit)

      CoreProcessExit.status(exit) == :signal ->
        signal = CoreProcessExit.signal(exit)
        128 + signal_to_int(signal)

      true ->
        raw_status
    end
  end

  defp wrapped_exit_reason?(reason) do
    CoreProcessExit.match?(reason) or wrapped_exit_reason_shape?(reason)
  end

  defp wrapped_exit_reason_shape?(:normal), do: true
  defp wrapped_exit_reason_shape?(reason) when is_integer(reason), do: true
  defp wrapped_exit_reason_shape?({:exit_code, status}) when is_integer(status), do: true
  defp wrapped_exit_reason_shape?({:exit_status, status}) when is_integer(status), do: true
  defp wrapped_exit_reason_shape?({:signal, _signal, _core?}), do: true
  defp wrapped_exit_reason_shape?({:shutdown, reason}), do: wrapped_exit_reason?(reason)
  defp wrapped_exit_reason_shape?({:transport, reason}), do: wrapped_exit_reason?(reason)
  defp wrapped_exit_reason_shape?({:send_failed, reason}), do: wrapped_exit_reason?(reason)
  defp wrapped_exit_reason_shape?({:call_exit, reason}), do: wrapped_exit_reason?(reason)
  defp wrapped_exit_reason_shape?({:error, reason}), do: wrapped_exit_reason?(reason)
  defp wrapped_exit_reason_shape?({:exit, reason}), do: wrapped_exit_reason?(reason)
  defp wrapped_exit_reason_shape?({:EXIT, _pid, reason}), do: wrapped_exit_reason?(reason)

  defp wrapped_exit_reason_shape?({reason, {GenServer, :call, _}}),
    do: wrapped_exit_reason?(reason)

  defp wrapped_exit_reason_shape?(_reason), do: false

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

defmodule Codex.IO.Transport.Erlexec do
  @moduledoc "Core-backed subprocess transport implementation."

  alias CliSubprocessCore.Transport.Erlexec, as: CoreErlexec
  alias CliSubprocessCore.Transport.Error, as: CoreError

  @behaviour Codex.IO.Transport

  @event_tag :codex_io_transport

  @impl Codex.IO.Transport
  def start(opts) when is_list(opts) do
    opts
    |> normalize_start_opts()
    |> CoreErlexec.start()
    |> normalize_result()
  end

  @impl Codex.IO.Transport
  def start_link(opts) when is_list(opts) do
    opts
    |> normalize_start_opts()
    |> CoreErlexec.start_link()
    |> normalize_result()
  end

  @impl Codex.IO.Transport
  def send(transport, message) when is_pid(transport) do
    transport
    |> CoreErlexec.send(message)
    |> normalize_result()
  end

  @impl Codex.IO.Transport
  def subscribe(transport, pid) when is_pid(transport) and is_pid(pid) do
    subscribe(transport, pid, :legacy)
  end

  @impl Codex.IO.Transport
  def subscribe(transport, pid, tag)
      when is_pid(transport) and is_pid(pid) and (tag == :legacy or is_reference(tag)) do
    transport
    |> CoreErlexec.subscribe(pid, tag)
    |> normalize_result()
  end

  @impl Codex.IO.Transport
  def close(transport) when is_pid(transport), do: CoreErlexec.close(transport)

  @impl Codex.IO.Transport
  def force_close(transport) when is_pid(transport) do
    case transport |> CoreErlexec.force_close() |> normalize_result() do
      {:error, {:transport, :not_connected}} -> :ok
      other -> other
    end
  end

  @impl Codex.IO.Transport
  def interrupt(transport) when is_pid(transport) do
    case transport |> CoreErlexec.interrupt() |> normalize_result() do
      {:error, {:transport, :not_connected}} -> :ok
      other -> other
    end
  end

  @impl Codex.IO.Transport
  def status(transport) when is_pid(transport), do: CoreErlexec.status(transport)

  @impl Codex.IO.Transport
  def end_input(transport) when is_pid(transport) do
    transport
    |> CoreErlexec.end_input()
    |> normalize_result()
  end

  @impl Codex.IO.Transport
  def stderr(transport) when is_pid(transport), do: CoreErlexec.stderr(transport)

  defp normalize_start_opts(opts) do
    Keyword.put_new(opts, :event_tag, @event_tag)
  end

  defp normalize_result({:error, {:transport, %CoreError{} = error}}) do
    {:error, {:transport, normalize_reason(error)}}
  end

  defp normalize_result(other), do: other

  defp normalize_reason(%CoreError{reason: :not_connected}), do: :not_connected

  defp normalize_reason(%CoreError{reason: {:invalid_options, {:invalid_subscriber, _tag}}}),
    do: :invalid_subscriber

  defp normalize_reason(%CoreError{} = error), do: error
end

defmodule Codex.IO.Transport.Erlexec do
  @moduledoc """
  Codex subprocess transport backed by `cli_subprocess_core`.

  This module preserves the historical `Codex.IO.Transport` event contract for
  Codex-native control protocols such as app-server and MCP stdio while the
  shared subprocess lifecycle remains owned by `cli_subprocess_core`.
  """

  alias CliSubprocessCore.Transport, as: CoreTransport
  alias CliSubprocessCore.Transport.Error, as: CoreError

  @behaviour Codex.IO.Transport

  @event_tag :codex_io_transport

  @impl Codex.IO.Transport
  def start(opts) when is_list(opts) do
    opts
    |> normalize_start_opts()
    |> CoreTransport.start()
    |> normalize_result()
  end

  @impl Codex.IO.Transport
  def start_link(opts) when is_list(opts) do
    opts
    |> normalize_start_opts()
    |> CoreTransport.start_link()
    |> normalize_result()
  end

  @impl Codex.IO.Transport
  def send(transport, message) when is_pid(transport) do
    transport
    |> CoreTransport.send(message)
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
    |> CoreTransport.subscribe(pid, tag)
    |> normalize_result()
  end

  @impl Codex.IO.Transport
  def close(transport) when is_pid(transport), do: CoreTransport.close(transport)

  @impl Codex.IO.Transport
  def force_close(transport) when is_pid(transport) do
    transport
    |> CoreTransport.force_close()
    |> normalize_result()
  end

  @impl Codex.IO.Transport
  def interrupt(transport) when is_pid(transport) do
    transport
    |> CoreTransport.interrupt()
    |> normalize_result()
  end

  @impl Codex.IO.Transport
  def status(transport) when is_pid(transport), do: CoreTransport.status(transport)

  @impl Codex.IO.Transport
  def end_input(transport) when is_pid(transport) do
    transport
    |> CoreTransport.end_input()
    |> normalize_result()
  end

  @impl Codex.IO.Transport
  def stderr(transport) when is_pid(transport), do: CoreTransport.stderr(transport)

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

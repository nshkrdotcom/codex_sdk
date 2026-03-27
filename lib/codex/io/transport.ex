defmodule Codex.IO.Transport do
  @moduledoc """
  Behaviour and public entrypoint for subprocess I/O transport implementations.

  The core-backed implementation preserves the historical event tag but now
  surfaces normalized `%CliSubprocessCore.ProcessExit{}` and
  `%CliSubprocessCore.Transport.Error{}` values for exit and error payloads.

  Event model:

  Legacy dispatch:
  - `{:transport_message, line}`
  - `{:transport_error, reason}`
  - `{:transport_stderr, data}`
  - `{:transport_exit, reason}`

  Tagged dispatch:
  - `{:codex_io_transport, ref, {:message, line}}`
  - `{:codex_io_transport, ref, {:error, reason}}`
  - `{:codex_io_transport, ref, {:stderr, data}}`
  - `{:codex_io_transport, ref, {:exit, reason}}`
  """

  alias CliSubprocessCore.Transport, as: CoreTransport
  alias CliSubprocessCore.Transport.Error, as: CoreError

  @type t :: pid()
  @type opts :: keyword()
  @type subscription_tag :: :legacy | reference()
  @type transport_error :: {:transport, :invalid_subscriber | :not_connected | CoreError.t()}
  @event_tag :codex_io_transport

  @type message ::
          {:transport_message, String.t()}
          | {:transport_error, term()}
          | {:transport_stderr, binary()}
          | {:transport_exit, term()}
          | {:codex_io_transport, reference(), {:message, String.t()}}
          | {:codex_io_transport, reference(), {:error, term()}}
          | {:codex_io_transport, reference(), {:stderr, binary()}}
          | {:codex_io_transport, reference(), {:exit, term()}}

  @callback start(opts()) :: {:ok, t()} | {:error, term()}
  @callback start_link(opts()) :: {:ok, t()} | {:error, term()}
  @callback send(t(), iodata()) :: :ok | {:error, term()}
  @callback subscribe(t(), pid()) :: :ok | {:error, term()}
  @callback subscribe(t(), pid(), subscription_tag()) :: :ok | {:error, term()}
  @callback close(t()) :: :ok
  @callback force_close(t()) :: :ok | {:error, term()}
  @callback interrupt(t()) :: :ok | {:error, term()}
  @callback status(t()) :: :connected | :disconnected | :error
  @callback end_input(t()) :: :ok | {:error, term()}
  @callback stderr(t()) :: binary()

  @spec start(opts()) :: {:ok, t()} | {:error, term()}
  def start(opts) when is_list(opts) do
    opts
    |> normalize_start_opts()
    |> CoreTransport.start()
    |> normalize_result()
  end

  @spec start_link(opts()) :: {:ok, t()} | {:error, term()}
  def start_link(opts) when is_list(opts) do
    opts
    |> normalize_start_opts()
    |> CoreTransport.start_link()
    |> normalize_result()
  end

  @spec send(t(), iodata()) :: :ok | {:error, term()}
  def send(transport, message) when is_pid(transport) do
    transport
    |> CoreTransport.send(message)
    |> normalize_result()
  end

  @spec subscribe(t(), pid()) :: :ok | {:error, transport_error()}
  def subscribe(transport, pid) when is_pid(transport) and is_pid(pid) do
    subscribe(transport, pid, :legacy)
  end

  @spec subscribe(t(), pid(), subscription_tag()) :: :ok | {:error, transport_error()}
  def subscribe(transport, pid, tag)
      when is_pid(transport) and is_pid(pid) and (tag == :legacy or is_reference(tag)) do
    transport
    |> CoreTransport.subscribe(pid, tag)
    |> normalize_result()
  end

  @spec close(t()) :: :ok
  def close(transport) when is_pid(transport), do: CoreTransport.close(transport)

  @spec force_close(t()) :: :ok | {:error, term()}
  def force_close(transport) when is_pid(transport) do
    transport
    |> CoreTransport.force_close()
    |> normalize_result()
  end

  @spec interrupt(t()) :: :ok | {:error, term()}
  def interrupt(transport) when is_pid(transport) do
    transport
    |> CoreTransport.interrupt()
    |> normalize_result()
  end

  @spec status(t()) :: :connected | :disconnected | :error
  def status(transport) when is_pid(transport), do: CoreTransport.status(transport)

  @spec end_input(t()) :: :ok | {:error, term()}
  def end_input(transport) when is_pid(transport) do
    transport
    |> CoreTransport.end_input()
    |> normalize_result()
  end

  @spec stderr(t()) :: binary()
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

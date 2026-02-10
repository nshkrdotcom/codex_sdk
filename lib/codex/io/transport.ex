defmodule Codex.IO.Transport do
  @moduledoc """
  Behaviour for subprocess I/O transport implementations.

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

  @type t :: pid() | GenServer.server()
  @type opts :: keyword()
  @type subscription_tag :: :legacy | reference()

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
  @callback status(t()) :: :connected | :disconnected | :error
  @callback end_input(t()) :: :ok | {:error, term()}
  @callback stderr(t()) :: binary()
end

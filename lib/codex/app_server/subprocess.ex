defmodule Codex.AppServer.Subprocess do
  @moduledoc false

  @type exec_pid :: pid()
  @type os_pid :: term()

  @callback start(command :: [charlist()], run_opts :: keyword(), opts :: keyword()) ::
              {:ok, exec_pid(), os_pid()} | {:error, term()}

  @callback send(exec_pid(), iodata(), opts :: keyword()) :: :ok | {:error, term()}

  @callback stop(exec_pid(), opts :: keyword()) :: :ok
end

defmodule Codex.RuntimeKit do
  @moduledoc false

  alias CliSubprocessCore.Event

  @callback start_session(keyword()) :: {:ok, pid(), term()} | {:error, term()}
  @callback subscribe(pid(), pid(), reference()) :: :ok | {:error, term()}
  @callback send_input(pid(), iodata(), keyword()) :: :ok | {:error, term()}
  @callback end_input(pid()) :: :ok | {:error, term()}
  @callback interrupt(pid()) :: :ok | {:error, term()}
  @callback close(pid()) :: :ok
  @callback info(pid()) :: map()
  @callback project_event(Event.t(), term()) :: {[term()], term()}
  @callback capabilities() :: [atom()]
end

defmodule Codex.OAuth.TokenStore.Memory do
  @moduledoc false

  use Agent

  alias Codex.Auth.Store
  alias Codex.OAuth.TokenStore

  @spec start_link(Store.Record.t(), Codex.OAuth.Context.t(), keyword()) :: Agent.on_start()
  def start_link(%Store.Record{} = record, context, opts \\ []) do
    Agent.start_link(fn ->
      TokenStore.session_from_record(record, context,
        provider: Keyword.get(opts, :provider, :openai_chatgpt),
        flow: Keyword.get(opts, :flow, :unknown),
        storage: :memory,
        persisted?: false
      )
    end)
  end

  @spec fetch(pid()) :: Codex.OAuth.Session.t()
  def fetch(pid) when is_pid(pid), do: Agent.get(pid, & &1)

  @spec put(pid(), Codex.OAuth.Session.t()) :: :ok
  def put(pid, session) when is_pid(pid) do
    Agent.update(pid, fn _ -> session end)
  end
end

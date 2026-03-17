defmodule Codex.OAuth.TokenStore do
  @moduledoc false

  alias Codex.Auth.Store
  alias Codex.OAuth.Session

  @spec session_from_record(Store.Record.t(), Codex.OAuth.Context.t(), keyword()) :: Session.t()
  def session_from_record(%Store.Record{} = auth_record, context, opts \\ []) do
    %Session{
      provider: Keyword.get(opts, :provider, :openai_chatgpt),
      flow: Keyword.get(opts, :flow, :unknown),
      storage: Keyword.get(opts, :storage, :file),
      context: context,
      auth_record: auth_record,
      persisted?: Keyword.get(opts, :persisted?, false),
      token_store: Keyword.get(opts, :token_store)
    }
  end
end

defmodule Codex.OAuth.TokenStore.File do
  @moduledoc false

  alias Codex.Auth.Store
  alias Codex.OAuth.TokenStore

  @spec load(Codex.OAuth.Context.t()) :: {:ok, Codex.OAuth.Session.t() | nil} | {:error, term()}
  def load(context) do
    case Store.load(codex_home: context.codex_home, codex_home_explicit?: true) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, %Store.Record{} = record} ->
        {:ok,
         TokenStore.session_from_record(record, context,
           provider: :openai_chatgpt,
           flow: :stored,
           storage: :file,
           persisted?: true
         )}

      {:error, _} = error ->
        error
    end
  end

  @spec persist(Codex.Auth.Store.Record.t(), Codex.OAuth.Context.t(), keyword()) ::
          {:ok, Codex.OAuth.Session.t()} | {:error, term()}
  def persist(%Store.Record{} = record, context, opts \\ []) do
    with :ok <- Store.write(record, codex_home: context.codex_home) do
      {:ok,
       TokenStore.session_from_record(record, context,
         provider: Keyword.get(opts, :provider, :openai_chatgpt),
         flow: Keyword.get(opts, :flow, :unknown),
         storage: :file,
         persisted?: true
       )}
    end
  end

  @spec delete(Codex.OAuth.Context.t()) :: :ok | {:error, term()}
  def delete(context) do
    Store.delete(codex_home: context.codex_home)
  end
end

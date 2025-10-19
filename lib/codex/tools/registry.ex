defmodule Codex.Tools.Registry do
  @moduledoc false

  alias Codex.Tools.Handle

  @table :codex_tools_registry

  @doc false
  def register(%{name: name, module: module, metadata: metadata}) do
    ensure_table()

    case :ets.lookup(@table, name) do
      [] ->
        true = :ets.insert(@table, {name, module, metadata})
        {:ok, %Handle{name: name, module: module}}

      _ ->
        {:error, {:already_registered, name}}
    end
  end

  @doc false
  def deregister(%Handle{name: name}) do
    ensure_table()
    :ets.delete(@table, name)
    :ok
  end

  @doc false
  def lookup(name) when is_binary(name) do
    ensure_table()

    case :ets.lookup(@table, name) do
      [{^name, module, metadata}] ->
        {:ok, %{name: name, module: module, metadata: metadata}}

      [] ->
        {:error, :not_found}
    end
  end

  @doc false
  def invoke(name, args, context) when is_binary(name) do
    with {:ok, %{module: module, metadata: metadata} = info} <- lookup(name) do
      full_context =
        context
        |> Map.put(:tool, %{name: info.name, metadata: metadata})
        |> Map.put(:metadata, metadata)

      safe_invoke(module, Map.new(args), full_context)
    end
  end

  defp safe_invoke(module, args, context) do
    try do
      module.invoke(args, context)
    rescue
      error -> {:error, {:tool_exception, module, error}}
    catch
      kind, reason -> {:error, {:tool_failure, module, {kind, reason}}}
    end
  end

  @doc false
  def reset! do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _ -> :ets.delete(@table)
    end

    ensure_table()
    :ok
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        :ok
    end
  end
end

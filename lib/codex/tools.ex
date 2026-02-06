defmodule Codex.Tools do
  @moduledoc """
  Public API for registering and invoking Codex tools.
  """

  alias Codex.Tool
  alias Codex.Tools.Registry

  @metrics_table :codex_tool_metrics
  @metrics_heir :codex_tool_metrics_heir

  defmodule Handle do
    @moduledoc """
    Registration handle returned from `Codex.Tools.register/2`.
    """

    @enforce_keys [:name, :module]
    defstruct [:name, :module]

    @type t :: %__MODULE__{
            name: String.t(),
            module: module()
          }
  end

  @type tool_info :: %{
          name: String.t(),
          module: module(),
          metadata: map()
        }

  @doc """
  Registers a tool module with optional overrides.

  Options:
    * `:name` – tool identifier (defaults to metadata `name` or module name)
    * `:description` – human readable description
    * `:schema` – optional structured output schema metadata
  """
  @spec register(module(), keyword()) :: {:ok, Handle.t()} | {:error, term()}
  def register(module, opts \\ []) when is_atom(module) do
    base_metadata = Tool.metadata(module)

    Registry.register(%{
      module: module,
      name: resolve_name(module, opts, base_metadata),
      metadata: resolve_metadata(opts, base_metadata)
    })
  end

  defp resolve_name(module, opts, metadata) do
    case Keyword.get(opts, :name) || metadata[:name] || metadata["name"] do
      nil -> module |> Module.split() |> List.last() |> Macro.underscore()
      name when is_binary(name) -> name
      name -> to_string(name)
    end
  end

  defp resolve_metadata(opts, metadata) do
    metadata
    |> Map.merge(Map.new(opts) |> Map.drop([:name]))
  end

  @doc """
  Deregisters a tool using the handle returned from `register/2`.
  """
  @spec deregister(Handle.t()) :: :ok
  def deregister(%Handle{} = handle), do: Registry.deregister(handle)

  @doc """
  Looks up a registered tool by name.
  """
  @spec lookup(String.t()) :: {:ok, tool_info()} | {:error, :not_found}
  def lookup(name) when is_binary(name), do: Registry.lookup(name)

  @doc """
  Invokes a registered tool, passing argument and contextual data.
  """
  @spec invoke(String.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def invoke(name, args, context) when is_binary(name) do
    Registry.invoke(name, args, context)
  end

  @doc """
  Returns a snapshot of accumulated tool invocation metrics keyed by tool name.
  """
  @spec metrics() :: %{optional(String.t()) => map()}
  def metrics do
    ensure_metrics_table()

    @metrics_table
    |> :ets.tab2list()
    |> Map.new(fn {tool, success, failure, last_latency_ms, total_latency_ms, last_error} ->
      {tool,
       %{
         success: success,
         failure: failure,
         last_latency_ms: last_latency_ms,
         total_latency_ms: total_latency_ms,
         last_error: last_error
       }}
    end)
  end

  @doc """
  Clears all recorded metrics. Primarily used in test setups.
  """
  @spec reset_metrics() :: :ok
  def reset_metrics do
    ensure_metrics_table()

    try do
      :ets.delete_all_objects(@metrics_table)
    rescue
      ArgumentError ->
        # Table may have been removed by another process; recreate it to keep
        # callers resilient in async test runs.
        ensure_metrics_table()
    end

    :ok
  end

  @doc false
  @spec reset!() :: :ok
  def reset! do
    Registry.reset!()
    reset_metrics()
  end

  @doc false
  @spec record_invocation(String.t(), :success | :failure, non_neg_integer(), term()) :: :ok
  def record_invocation(tool, outcome, latency_ms, error \\ nil) when is_binary(tool) do
    with_metrics_table(fn ->
      ensure_metric_entry(tool)

      :ets.update_element(@metrics_table, tool, {4, latency_ms})
      :ets.update_counter(@metrics_table, tool, {5, latency_ms})

      case outcome do
        :success ->
          :ets.update_counter(@metrics_table, tool, {2, 1})
          :ets.update_element(@metrics_table, tool, {6, nil})

        :failure ->
          :ets.update_counter(@metrics_table, tool, {3, 1})
          :ets.update_element(@metrics_table, tool, {6, error})
      end

      :ok
    end)
  end

  defp ensure_metrics_table do
    case :ets.whereis(@metrics_table) do
      :undefined ->
        try do
          :ets.new(@metrics_table, metrics_table_opts())
        rescue
          ArgumentError -> :ok
        end

      _ ->
        :ok
    end
  end

  defp ensure_metric_entry(tool) do
    ensure_metrics_table()

    :ets.insert_new(@metrics_table, {tool, 0, 0, 0, 0, nil})
    :ok
  end

  defp metrics_table_opts do
    heir = ensure_metrics_heir()

    [
      {:heir, heir, :metrics},
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ]
  end

  defp ensure_metrics_heir do
    case Process.whereis(@metrics_heir) do
      nil ->
        pid = spawn(fn -> metrics_heir_loop() end)

        try do
          Process.register(pid, @metrics_heir)
          pid
        rescue
          ArgumentError ->
            Process.exit(pid, :kill)
            ensure_metrics_heir()
        end

      pid ->
        pid
    end
  end

  defp metrics_heir_loop do
    receive do
      {:"ETS-TRANSFER", @metrics_table, _from, _data} ->
        metrics_heir_loop()

      _other ->
        metrics_heir_loop()
    end
  end

  defp with_metrics_table(fun) when is_function(fun, 0) do
    ensure_metrics_table()
    fun.()
  rescue
    ArgumentError ->
      ensure_metrics_table()
      fun.()
  end
end

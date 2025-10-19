defmodule Codex.Tools do
  @moduledoc """
  Public API for registering and invoking Codex tools.
  """

  alias Codex.Tool
  alias Codex.Tools.Registry

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
  @spec deregister(Handle.t()) :: :ok | {:error, term()}
  def deregister(%Handle{} = handle), do: Registry.deregister(handle)

  @doc """
  Looks up a registered tool by name.
  """
  @spec lookup(String.t()) :: {:ok, map()} | {:error, term()}
  def lookup(name) when is_binary(name), do: Registry.lookup(name)

  @doc """
  Invokes a registered tool, passing argument and contextual data.
  """
  @spec invoke(String.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def invoke(name, args, context) when is_binary(name) do
    Registry.invoke(name, args, context)
  end

  @doc false
  @spec reset!() :: :ok
  def reset!, do: Registry.reset!()
end

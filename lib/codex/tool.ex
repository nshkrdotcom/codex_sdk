defmodule Codex.Tool do
  @moduledoc """
  Behaviour and helper macros for Codex tool modules.

  Tools must implement `c:invoke/2`, returning either `{:ok, map()}` or `{:error, term()}`.
  Optional metadata is surfaced via `metadata/0` and merged with registry attributes on
  registration.
  """

  @callback invoke(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback metadata() :: map()

  @optional_callbacks metadata: 0

  @doc """
  Returns metadata for a tool module, normalising to a map.
  """
  @spec metadata(module()) :: map()
  def metadata(module) when is_atom(module) do
    _ = Code.ensure_loaded(module)

    if function_exported?(module, :metadata, 0) do
      module.metadata() |> normalise_metadata()
    else
      %{}
    end
  end

  @doc """
  Normalizes metadata options to a map.
  """
  @spec normalize_metadata(term()) :: map()
  def normalize_metadata(metadata) when is_map(metadata), do: metadata
  def normalize_metadata(metadata) when is_list(metadata), do: Map.new(metadata)
  def normalize_metadata(_other), do: %{}

  @doc false
  defmacro __using__(opts) do
    quote do
      @behaviour Codex.Tool
      @impl true
      def metadata do
        unquote(opts)
        |> Codex.Tool.normalize_metadata()
      end

      defoverridable metadata: 0
    end
  end

  defp normalise_metadata(metadata), do: normalize_metadata(metadata)
end

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
    if function_exported?(module, :metadata, 0) do
      module.metadata() |> normalise_metadata()
    else
      %{}
    end
  end

  defp normalise_metadata(metadata) when is_map(metadata), do: metadata
  defp normalise_metadata(metadata) when is_list(metadata), do: Map.new(metadata)
  defp normalise_metadata(_other), do: %{}

  @doc false
  defmacro __using__(opts) do
    {evaluated_opts, _} = Code.eval_quoted(opts, [], __CALLER__)
    metadata = Macro.escape(normalise_metadata(evaluated_opts), unquote: true)

    quote do
      @behaviour Codex.Tool
      @impl true
      def metadata do
        unquote(metadata)
      end

      defoverridable metadata: 0
    end
  end
end

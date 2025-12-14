defmodule Codex.FunctionTool do
  @moduledoc """
  Convenience macro for defining function-backed tools with JSON schemas.

  Usage:

      defmodule MyTool do
        use Codex.FunctionTool,
          name: "add",
          description: "Adds numbers",
          parameters: %{left: :number, right: :number},
          handler: fn %{"left" => left, "right" => right}, _ctx ->
            {:ok, %{"sum" => left + right}}
          end
      end

  Options:
    * `:name` - tool name (defaults to module name)
    * `:description` - human-friendly description
    * `:parameters` - map of parameter names to type atoms or schema maps
    * `:required` - list of required parameter names (defaults to all)
    * `:schema` - explicit JSON schema (overrides generated schema)
    * `:strict?` - when true sets `"additionalProperties": false` (default)
    * `:handler` - function to invoke (falls back to `handle/2` or `handle/1`)
    * `:enabled?` - predicate to gate invocation (arity 1 or 2)
    * `:on_error` - fallback handler invoked with the error (arity 2 or 3)
  """

  @type opts :: map() | keyword()

  @doc false
  defmacro __using__(opts) do
    {evaluated_opts, _} = Code.eval_quoted(opts, [], __CALLER__)
    normalized_opts = normalize_opts(evaluated_opts)
    _ = build_metadata(normalized_opts)

    quote location: :keep do
      @behaviour Codex.Tool
      @codex_function_tool_opts_ast unquote(Macro.escape(opts, unquote: true))

      @impl true
      def metadata do
        {evaluated_opts, _} = Code.eval_quoted(@codex_function_tool_opts_ast, [], __ENV__)
        opts_map = Codex.FunctionTool.normalize_opts(evaluated_opts)
        Codex.FunctionTool.build_metadata(opts_map)
      end

      @impl true
      def invoke(args, context) do
        {evaluated_opts, _} = Code.eval_quoted(@codex_function_tool_opts_ast, [], __ENV__)
        opts_map = Codex.FunctionTool.normalize_opts(evaluated_opts)

        Codex.FunctionTool.execute(__MODULE__, opts_map, args, context)
      end

      defoverridable metadata: 0
    end
  end

  @doc """
  Executes the configured handler with normalized arguments.
  """
  @spec execute(module(), map(), map() | list() | String.t() | nil, map()) ::
          {:ok, term()} | {:error, term()}
  def execute(module, opts, args, context) do
    handler = resolve_handler(module, opts)
    normalized_args = normalize_args(args)

    case handler do
      nil ->
        {:error, :missing_handler}

      fun when is_function(fun) ->
        apply_handler(fun, normalized_args, context)
    end
  end

  @doc """
  Builds a JSON schema map from a parameter definition.
  """
  @spec build_schema(map(), keyword() | map()) :: map()
  def build_schema(parameters, opts \\ []) do
    properties =
      parameters
      |> Map.new(fn {name, type} -> {to_string(name), parameter_schema(type)} end)

    required =
      opts
      |> get_opt(:required, Map.keys(properties))
      |> Enum.map(&to_string/1)

    schema =
      %{
        "type" => "object",
        "properties" => properties,
        "required" => required
      }
      |> maybe_put("additionalProperties", get_opt(opts, :strict?, true) && false)

    schema
  end

  @doc """
  Constructs metadata map used for tool registration.
  """
  @spec build_metadata(opts()) :: map()
  def build_metadata(opts) do
    opts = normalize_opts(opts)
    schema = Map.get(opts, :schema) || build_schema(Map.get(opts, :parameters, %{}), opts)

    %{}
    |> maybe_put(:name, Map.get(opts, :name))
    |> maybe_put(:description, Map.get(opts, :description))
    |> maybe_put(:schema, schema)
    |> maybe_put(:parameters, Map.get(opts, :parameters, %{}))
    |> maybe_put(:enabled?, Map.get(opts, :enabled?))
    |> maybe_put(:on_error, Map.get(opts, :on_error))
  end

  defp resolve_handler(module, opts) do
    with nil <- Map.get(opts, :handler),
         nil <- exported_handler(module, 2),
         nil <- exported_handler(module, 1) do
      nil
    else
      fun -> fun
    end
  end

  defp exported_handler(module, 2) do
    if function_exported?(module, :handle, 2) do
      fn args, context -> module.handle(args, context) end
    end
  end

  defp exported_handler(module, 1) do
    if function_exported?(module, :handle, 1) do
      fn args, _context -> module.handle(args) end
    end
  end

  defp parameter_schema({:array, inner}),
    do: %{"type" => "array", "items" => parameter_schema(inner)}

  defp parameter_schema(:string), do: %{"type" => "string"}
  defp parameter_schema(:integer), do: %{"type" => "integer"}
  defp parameter_schema(:number), do: %{"type" => "number"}
  defp parameter_schema(:boolean), do: %{"type" => "boolean"}
  defp parameter_schema(:object), do: %{"type" => "object"}
  defp parameter_schema(:map), do: %{"type" => "object"}
  defp parameter_schema(:array), do: %{"type" => "array"}
  defp parameter_schema(:list), do: %{"type" => "array"}

  defp parameter_schema(%{} = schema) do
    schema
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Map.new()
  end

  defp parameter_schema(other), do: %{"type" => to_string(other)}

  defp apply_handler(fun, args, context) when is_function(fun, 2) do
    case fun.(args, context) do
      {:ok, _} = ok -> ok
      {:error, _} = error -> error
      other -> {:error, {:invalid_function_tool_result, other}}
    end
  end

  defp apply_handler(fun, args, _context) when is_function(fun, 1) do
    case fun.(args) do
      {:ok, _} = ok -> ok
      {:error, _} = error -> error
      other -> {:error, {:invalid_function_tool_result, other}}
    end
  end

  defp apply_handler(fun, _args, _context) when is_function(fun, 0) do
    case fun.() do
      {:ok, _} = ok -> ok
      {:error, _} = error -> error
      other -> {:error, {:invalid_function_tool_result, other}}
    end
  end

  defp normalize_args(map) when is_map(map), do: map
  defp normalize_args(list) when is_list(list), do: Map.new(list)

  defp normalize_args(string) when is_binary(string) do
    case Jason.decode(string) do
      {:ok, %{} = decoded} -> decoded
      _ -> %{"input" => string}
    end
  rescue
    _ -> %{"input" => string}
  end

  defp normalize_args(other), do: %{"input" => other}

  @doc false
  def normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  def normalize_opts(%{} = opts), do: opts

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp get_opt(opts, key, default) when is_map(opts), do: Map.get(opts, key, default)
  defp get_opt(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
end

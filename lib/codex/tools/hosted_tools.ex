defmodule Codex.Tools.Hosted do
  @moduledoc false

  def metadata_value(metadata, key, default \\ nil) do
    Map.get(metadata, key) ||
      Map.get(metadata, to_string(key)) ||
      default
  end

  def file_search_value(metadata, key, default \\ nil) do
    case metadata_value(metadata, key) do
      nil -> nested_file_search_value(metadata, key, default)
      value -> value
    end
  end

  defp nested_file_search_value(metadata, key, default) do
    case metadata_value(metadata, :file_search) do
      %{} = file_search ->
        Map.get(file_search, key) ||
          Map.get(file_search, to_string(key)) ||
          default

      _ ->
        default
    end
  end

  def callback(metadata, key) do
    metadata_value(metadata, key)
  end

  def require_callback(metadata, key) do
    case callback(metadata, key) do
      fun when is_function(fun) -> {:ok, fun}
      _ -> {:error, {:missing_callback, key}}
    end
  end

  def safe_call(fun, args, context, metadata)
      when is_function(fun, 3),
      do: fun.(args, context, metadata)

  def safe_call(fun, args, context, _metadata) when is_function(fun, 2), do: fun.(args, context)
  def safe_call(fun, args, _context, _metadata) when is_function(fun, 1), do: fun.(args)
  def safe_call(fun, _args, _context, _metadata) when is_function(fun, 0), do: fun.()
  def safe_call(_fun, _args, _context, _metadata), do: {:error, :invalid_callback}

  def maybe_truncate_output(output, nil), do: output

  def maybe_truncate_output(output, limit) when is_integer(limit) and limit > 0 do
    cond do
      is_binary(output) -> String.slice(output, 0, limit)
      is_map(output) -> truncate_map(output, limit)
      true -> output
    end
  end

  def maybe_truncate_output(output, _limit), do: output

  def check_approval(metadata, args, context) do
    case callback(metadata, :approval) do
      nil ->
        :ok

      fun when is_function(fun) ->
        case safe_call(fun, args, context, metadata) do
          {:deny, reason} -> {:error, {:approval_denied, reason}}
          false -> {:error, {:approval_denied, :denied}}
          :deny -> {:error, {:approval_denied, :denied}}
          _ -> :ok
        end

      _ ->
        :ok
    end
  end

  defp truncate_map(map, limit) do
    map
    |> maybe_truncate_key(:output, limit)
    |> maybe_truncate_key("output", limit)
    |> maybe_truncate_key(:stdout, limit)
    |> maybe_truncate_key("stdout", limit)
  end

  defp maybe_truncate_key(map, key, limit) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) ->
        Map.put(map, key, String.slice(value, 0, limit))

      _ ->
        map
    end
  end
end

defmodule Codex.Tools.ShellTool do
  @moduledoc """
  Hosted shell executor tool with optional approval and output truncation hooks.
  """

  @behaviour Codex.Tool

  alias Codex.Tools.Hosted

  @impl true
  def metadata do
    %{
      name: "shell",
      description: "Execute shell commands",
      schema: %{
        "type" => "object",
        "properties" => %{"command" => %{"type" => "string"}},
        "required" => ["command"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def invoke(args, context) do
    metadata = Map.get(context, :metadata, %{})
    timeout = Hosted.metadata_value(metadata, :timeout_ms)
    max_bytes = Hosted.metadata_value(metadata, :max_output_bytes)
    merged_context = Map.put(context, :timeout_ms, timeout)

    with :ok <- Hosted.check_approval(metadata, args, merged_context),
         {:ok, executor} <- Hosted.require_callback(metadata, :executor) do
      case Hosted.safe_call(executor, args, merged_context, metadata) do
        {:ok, output} -> {:ok, Hosted.maybe_truncate_output(output, max_bytes)}
        {:error, reason} -> {:error, reason}
        other -> {:ok, Hosted.maybe_truncate_output(other, max_bytes)}
      end
    end
  end
end

defmodule Codex.Tools.ApplyPatchTool do
  @moduledoc """
  Hosted apply_patch editor hook.
  """

  @behaviour Codex.Tool

  alias Codex.Tools.Hosted

  @impl true
  def metadata do
    %{
      name: "apply_patch",
      description: "Apply a textual patch",
      schema: %{
        "type" => "object",
        "properties" => %{"patch" => %{"type" => "string"}},
        "required" => ["patch"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def invoke(args, context) do
    metadata = Map.get(context, :metadata, %{})

    with :ok <- Hosted.check_approval(metadata, args, context),
         {:ok, editor} <- Hosted.require_callback(metadata, :editor) do
      case Hosted.safe_call(editor, args, context, metadata) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
        other -> {:ok, other}
      end
    end
  end
end

defmodule Codex.Tools.ComputerTool do
  @moduledoc """
  Hosted computer action tool with safety callback.
  """

  @behaviour Codex.Tool

  alias Codex.Tools.Hosted

  @impl true
  def metadata do
    %{
      name: "computer",
      description: "Perform computer control actions",
      schema: %{
        "type" => "object",
        "properties" => %{"action" => %{"type" => "string"}},
        "required" => ["action"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def invoke(args, context) do
    metadata = Map.get(context, :metadata, %{})
    safety = Hosted.callback(metadata, :safety)

    with :ok <- Hosted.check_approval(metadata, args, context),
         :ok <- run_safety_check(safety, args, context, metadata),
         {:ok, executor} <- Hosted.require_callback(metadata, :executor) do
      case Hosted.safe_call(executor, args, context, metadata) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
        other -> {:ok, other}
      end
    end
  end

  defp run_safety_check(nil, _args, _context, _metadata), do: :ok

  defp run_safety_check(fun, args, context, metadata) when is_function(fun) do
    case Hosted.safe_call(fun, args, context, metadata) do
      {:deny, reason} -> {:error, {:computer_denied, reason}}
      :deny -> {:error, {:computer_denied, :denied}}
      false -> {:error, {:computer_denied, :denied}}
      _ -> :ok
    end
  end

  defp run_safety_check(_other, _args, _context, _metadata), do: :ok
end

defmodule Codex.Tools.FileSearchTool do
  @moduledoc """
  Hosted file search tool.
  """

  @behaviour Codex.Tool

  alias Codex.Tools.Hosted

  @impl true
  def metadata do
    %{
      name: "file_search",
      description: "Search indexed documents",
      schema: %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string"},
          "filters" => %{"type" => "object"}
        },
        "required" => ["query"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def invoke(args, context) do
    metadata = Map.get(context, :metadata, %{})
    file_search = Map.get(context, :file_search)

    vector_store_ids =
      Hosted.file_search_value(
        metadata,
        :vector_store_ids,
        file_search_field(file_search, :vector_store_ids, [])
      )

    filters =
      Hosted.file_search_value(metadata, :filters, file_search_field(file_search, :filters))

    ranking_options =
      Hosted.file_search_value(
        metadata,
        :ranking_options,
        file_search_field(file_search, :ranking_options)
      )

    include_results =
      Hosted.file_search_value(
        metadata,
        :include_search_results,
        file_search_field(file_search, :include_search_results)
      )

    search_args =
      args
      |> Map.put_new("filters", filters)
      |> Map.put_new("vector_store_ids", vector_store_ids)
      |> maybe_put_arg("include_search_results", include_results)
      |> maybe_put_arg("ranking_options", ranking_options)

    enriched_metadata =
      metadata
      |> maybe_put_arg(:filters, filters)
      |> maybe_put_arg(:vector_store_ids, vector_store_ids)
      |> maybe_put_arg(:include_search_results, include_results)
      |> maybe_put_arg(:ranking_options, ranking_options)

    with {:ok, fun} <- Hosted.require_callback(enriched_metadata, :searcher) do
      case Hosted.safe_call(fun, search_args, context, enriched_metadata) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
        other -> {:ok, other}
      end
    end
  end

  defp file_search_field(file_search, key, default \\ nil)
  defp file_search_field(%Codex.FileSearch{} = fs, key, default), do: Map.get(fs, key) || default

  defp file_search_field(%{} = map, key, default),
    do: Map.get(map, key) || Map.get(map, to_string(key)) || default

  defp file_search_field(_other, _key, default), do: default

  defp maybe_put_arg(map, _key, nil), do: map
  defp maybe_put_arg(map, key, value), do: Map.put(map, key, value)
end

defmodule Codex.Tools.WebSearchTool do
  @moduledoc """
  Hosted web search tool.
  """

  @behaviour Codex.Tool

  alias Codex.Tools.Hosted

  @impl true
  def metadata do
    %{
      name: "web_search",
      description: "Search the web",
      schema: %{
        "type" => "object",
        "properties" => %{"query" => %{"type" => "string"}},
        "required" => ["query"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def invoke(args, context) do
    metadata = Map.get(context, :metadata, %{})

    with {:ok, searcher} <- Hosted.require_callback(metadata, :searcher) do
      case Hosted.safe_call(searcher, args, context, metadata) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
        other -> {:ok, other}
      end
    end
  end
end

defmodule Codex.Tools.ImageGenerationTool do
  @moduledoc """
  Hosted image generation tool.
  """

  @behaviour Codex.Tool

  alias Codex.Tools.Hosted

  @impl true
  def metadata do
    %{
      name: "image_generation",
      description: "Generate images from prompts",
      schema: %{
        "type" => "object",
        "properties" => %{
          "prompt" => %{"type" => "string"},
          "size" => %{"type" => "string"},
          "quality" => %{"type" => "string"}
        },
        "required" => ["prompt"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def invoke(args, context) do
    metadata = Map.get(context, :metadata, %{})

    with {:ok, generator} <- Hosted.require_callback(metadata, :generator) do
      case Hosted.safe_call(generator, args, context, metadata) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
        other -> {:ok, other}
      end
    end
  end
end

defmodule Codex.Tools.CodeInterpreterTool do
  @moduledoc """
  Hosted code interpreter tool.
  """

  @behaviour Codex.Tool

  alias Codex.Tools.Hosted

  @impl true
  def metadata do
    %{
      name: "code_interpreter",
      description: "Run code in a sandbox",
      schema: %{
        "type" => "object",
        "properties" => %{"code" => %{"type" => "string"}},
        "required" => ["code"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def invoke(args, context) do
    metadata = Map.get(context, :metadata, %{})

    with {:ok, runner} <- Hosted.require_callback(metadata, :runner) do
      case Hosted.safe_call(runner, args, context, metadata) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
        other -> {:ok, other}
      end
    end
  end
end

defmodule Codex.Tools.HostedMcpTool do
  @moduledoc """
  Hosted MCP tool wrapper that delegates to `Codex.MCP.Client`.
  """

  @behaviour Codex.Tool

  alias Codex.MCP.Client
  alias Codex.Tools.Hosted

  @impl true
  def metadata do
    %{
      name: "hosted_mcp",
      description: "Call a tool exposed by an MCP server"
    }
  end

  @impl true
  def invoke(args, context) do
    metadata = Map.get(context, :metadata, %{})
    tool = resolve_tool(args, metadata)
    client = Hosted.metadata_value(metadata, :client)
    retries = Hosted.metadata_value(metadata, :retries, 0)
    backoff = Hosted.callback(metadata, :backoff)

    call_args =
      Map.get(args, "arguments") ||
        Map.get(args, :arguments) ||
        args

    with true <- not is_nil(tool) or {:error, :missing_tool},
         {:ok, %Client{} = client} <- ensure_client(client),
         :ok <- Hosted.check_approval(metadata, args, context),
         {:ok, result} <-
           Client.call_tool(client, tool, call_args,
             retries: retries,
             backoff: backoff
           ) do
      {:ok, result}
    else
      {:error, _} = error -> error
    end
  end

  defp ensure_client(%Client{} = client), do: {:ok, client}
  defp ensure_client(_), do: {:error, :missing_client}

  defp resolve_tool(args, metadata) do
    Hosted.metadata_value(metadata, :tool) ||
      Hosted.metadata_value(metadata, :tool_name) ||
      Map.get(args, "tool") ||
      Map.get(args, :tool)
  end
end

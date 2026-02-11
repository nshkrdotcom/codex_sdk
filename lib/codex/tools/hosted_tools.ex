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

defmodule Codex.Tools.VectorStoreSearchTool do
  @moduledoc """
  Hosted vector store search tool for searching indexed documents.

  This tool integrates with OpenAI's vector store file search capabilities,
  allowing searches across indexed documents with optional filtering and ranking.

  ## Options

  Options can be passed during registration or via context metadata:

    * `:searcher` - Required callback function to execute the search
    * `:vector_store_ids` - List of vector store IDs to search
    * `:filters` - Search filters to apply
    * `:ranking_options` - Options for result ranking
    * `:include_search_results` - Whether to include full search results

  ## Usage

      searcher = fn args, _ctx, _meta ->
        {:ok, %{results: [%{text: args["query"]}]}}
      end

      {:ok, _} = Codex.Tools.register(VectorStoreSearchTool,
        searcher: searcher,
        vector_store_ids: ["vs_123"]
      )
  """

  @behaviour Codex.Tool

  alias Codex.Tools.Hosted

  @impl true
  def metadata do
    %{
      name: "vector_store_search",
      description: "Search indexed documents in vector stores",
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

defmodule Codex.Tools.ShellCommandTool do
  @moduledoc """
  Hosted tool for executing shell scripts via the user's default shell.
  """

  @behaviour Codex.Tool

  alias Codex.Config.Defaults
  alias Codex.Tools.Hosted
  alias Codex.Tools.ShellTool

  @default_timeout_ms Defaults.shell_timeout_ms()
  @default_max_output_bytes Defaults.shell_max_output_bytes()

  @impl true
  def metadata do
    %{
      name: "shell_command",
      description: "Execute shell scripts",
      schema: %{
        "type" => "object",
        "properties" => %{
          "command" => %{
            "type" => "string",
            "description" => "The shell script to execute in the user's default shell"
          },
          "workdir" => %{
            "type" => "string",
            "description" => "The working directory to execute the command in"
          },
          "login" => %{
            "type" => "boolean",
            "description" =>
              "Whether to run the shell with login shell semantics. Defaults to true."
          },
          "timeout_ms" => %{
            "type" => "integer",
            "description" => "The timeout for the command in milliseconds"
          },
          "sandbox_permissions" => %{
            "type" => "string",
            "description" =>
              "Sandbox permissions for the command. Set to \"require_escalated\" to request running without sandbox restrictions; defaults to \"use_default\"."
          },
          "justification" => %{
            "type" => "string",
            "description" =>
              "Only set if sandbox_permissions is \"require_escalated\". 1-sentence explanation of why we want to run this command."
          }
        },
        "required" => ["command"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def invoke(args, context) do
    metadata = Map.get(context, :metadata, %{})
    command = Map.get(args, "command") || Map.get(args, :command)

    cwd = resolve_cwd(args, context, metadata)
    timeout_ms = resolve_timeout(args, context, metadata)
    login = resolve_login(args, metadata)
    max_bytes = Hosted.metadata_value(metadata, :max_output_bytes, @default_max_output_bytes)

    merged_context =
      context
      |> Map.put(:timeout_ms, timeout_ms)
      |> Map.put(:cwd, cwd)
      |> Map.put(:command, command)
      |> Map.put(:login, login)

    with {:ok, normalized} <- normalize_command(command),
         :ok <- check_approval(normalized, metadata, merged_context) do
      execute_command(
        normalized,
        login,
        cwd,
        timeout_ms,
        max_bytes,
        args,
        merged_context,
        metadata
      )
    end
  end

  defp resolve_cwd(args, context, metadata) do
    Map.get(args, "workdir") ||
      Map.get(args, "cwd") ||
      Map.get(context, :cwd) ||
      Hosted.metadata_value(metadata, :cwd)
  end

  defp resolve_timeout(args, context, metadata) do
    Map.get(args, "timeout_ms") ||
      Map.get(args, "timeout") ||
      Map.get(context, :timeout_ms) ||
      Hosted.metadata_value(metadata, :timeout_ms, @default_timeout_ms)
  end

  defp resolve_login(args, metadata) do
    login =
      cond do
        Map.has_key?(args, "login") -> Map.get(args, "login")
        Map.has_key?(args, :login) -> Map.get(args, :login)
        true -> Hosted.metadata_value(metadata, :login)
      end

    case login do
      false -> false
      _ -> true
    end
  end

  defp normalize_command(command) when is_binary(command) and command != "" do
    {:ok, command}
  end

  defp normalize_command(command) when is_list(command) do
    normalized =
      command
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    if normalized == "" do
      {:error, {:invalid_argument, :command}}
    else
      {:ok, normalized}
    end
  end

  defp normalize_command(_), do: {:error, {:invalid_argument, :command}}

  defp check_approval(command, metadata, context) do
    case Hosted.callback(metadata, :approval) do
      nil ->
        :ok

      fun when is_function(fun, 2) ->
        handle_approval_result(fun.(command, context))

      fun when is_function(fun, 3) ->
        handle_approval_result(fun.(command, context, metadata))

      module when is_atom(module) ->
        if function_exported?(module, :review_tool, 2) do
          handle_approval_result(module.review_tool(command, context))
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp handle_approval_result(:ok), do: :ok
  defp handle_approval_result(:allow), do: :ok
  defp handle_approval_result({:allow, _opts}), do: :ok
  defp handle_approval_result({:deny, reason}), do: {:error, {:approval_denied, reason}}
  defp handle_approval_result(:deny), do: {:error, {:approval_denied, :denied}}
  defp handle_approval_result(false), do: {:error, {:approval_denied, :denied}}
  defp handle_approval_result(_), do: :ok

  defp execute_command(command, login, cwd, timeout_ms, max_bytes, args, context, metadata) do
    case Hosted.callback(metadata, :executor) do
      nil ->
        case default_executor(command, login, cwd, timeout_ms) do
          {:ok, output, exit_code} ->
            {:ok, format_result(output, exit_code, max_bytes)}

          {:error, :timeout} ->
            {:error, :timeout}

          {:error, reason} ->
            {:error, reason}
        end

      fun when is_function(fun) ->
        result = Hosted.safe_call(fun, args, context, metadata)
        handle_executor_result(result, max_bytes)
    end
  end

  defp default_executor(command, login, cwd, timeout_ms) do
    exec_command = build_shell_command(command, login)
    ShellTool.default_executor(exec_command, cwd, timeout_ms)
  end

  defp build_shell_command(command, login) do
    shell = resolve_shell()
    flags = if login, do: ["-lc"], else: ["-c"]
    [shell | flags] ++ [command]
  end

  defp resolve_shell do
    shell_env = System.get_env("SHELL")

    if is_binary(shell_env) and shell_env != "" and File.exists?(shell_env) do
      shell_env
    else
      System.find_executable("bash") ||
        System.find_executable("sh") ||
        "sh"
    end
  end

  defp handle_executor_result({:ok, output}, max_bytes) when is_binary(output) do
    {:ok, format_result(output, 0, max_bytes)}
  end

  defp handle_executor_result(
         {:ok, %{"output" => output, "exit_code" => code} = result},
         max_bytes
       ) do
    {:ok,
     format_result(output, code, max_bytes)
     |> Map.merge(Map.drop(result, ["output", "exit_code", "success"]))}
  end

  defp handle_executor_result({:ok, %{output: output, exit_code: code} = result}, max_bytes) do
    {:ok,
     format_result(output, code, max_bytes)
     |> Map.merge(Map.drop(result, [:output, :exit_code, :success]))}
  end

  defp handle_executor_result({:ok, output}, max_bytes) when is_map(output) do
    {:ok, Hosted.maybe_truncate_output(output, max_bytes)}
  end

  defp handle_executor_result({:error, reason}, _max_bytes), do: {:error, reason}

  defp handle_executor_result(output, max_bytes) when is_binary(output) do
    {:ok, format_result(output, 0, max_bytes)}
  end

  defp handle_executor_result(output, max_bytes) when is_map(output) do
    {:ok, Hosted.maybe_truncate_output(output, max_bytes)}
  end

  defp handle_executor_result(other, _max_bytes), do: {:ok, other}

  defp format_result(output, exit_code, max_bytes) do
    truncated = maybe_truncate(output, max_bytes)

    %{
      "output" => truncated,
      "exit_code" => exit_code,
      "success" => exit_code == 0
    }
  end

  defp maybe_truncate(output, nil), do: output
  defp maybe_truncate(output, max_bytes) when byte_size(output) <= max_bytes, do: output

  defp maybe_truncate(output, max_bytes) do
    String.slice(output, 0, max_bytes) <> "\n... (truncated)"
  end
end

defmodule Codex.Tools.WriteStdinTool do
  @moduledoc """
  Hosted tool for writing to an existing exec session.
  """

  @behaviour Codex.Tool

  alias Codex.AppServer
  alias Codex.Thread
  alias Codex.Tools.Hosted

  @impl true
  def metadata do
    %{
      name: "write_stdin",
      description: "Writes characters to an existing unified exec session and returns output",
      enabled?: &enabled?/2,
      schema: %{
        "type" => "object",
        "properties" => %{
          "session_id" => %{
            "type" => "integer",
            "description" => "Identifier of the running unified exec session."
          },
          "chars" => %{
            "type" => "string",
            "description" => "Bytes to write to stdin (may be empty to poll)."
          },
          "yield_time_ms" => %{
            "type" => "integer",
            "description" => "How long to wait (in milliseconds) for output before yielding."
          },
          "max_output_tokens" => %{
            "type" => "integer",
            "description" =>
              "Maximum number of tokens to return. Excess output will be truncated."
          }
        },
        "required" => ["session_id"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def invoke(args, context) do
    metadata = Map.get(context, :metadata, %{})

    with {:ok, session_id} <- fetch_session_id(args),
         {:ok, conn} <- resolve_connection(context) do
      payload = build_payload(args, session_id)
      execute_write(payload, args, context, metadata, conn)
    end
  end

  defp build_payload(args, session_id) do
    %{
      session_id: session_id,
      chars: Map.get(args, "chars") || Map.get(args, :chars) || "",
      yield_time_ms: fetch_payload_arg(args, "yield_time_ms", "yieldTimeMs", :yield_time_ms),
      max_output_tokens:
        fetch_payload_arg(args, "max_output_tokens", "maxOutputTokens", :max_output_tokens)
    }
  end

  defp fetch_payload_arg(args, string_key, camel_key, atom_key) do
    Map.get(args, string_key) || Map.get(args, camel_key) || Map.get(args, atom_key)
  end

  defp execute_write(payload, args, context, metadata, conn) do
    case Hosted.callback(metadata, :executor) do
      nil ->
        AppServer.command_write_stdin(
          conn,
          payload.session_id,
          payload.chars,
          command_write_opts(context, payload)
        )

      fun when is_function(fun) ->
        fun
        |> Hosted.safe_call(args, context, metadata)
        |> normalize_executor_result()
    end
  end

  defp normalize_executor_result({:ok, result}), do: {:ok, result}
  defp normalize_executor_result({:error, reason}), do: {:error, reason}
  defp normalize_executor_result(other), do: {:ok, other}

  defp enabled?(context, _metadata) do
    case Map.get(context, :thread) do
      %Thread{transport: {:app_server, conn}} when is_pid(conn) -> true
      _ -> false
    end
  end

  defp fetch_session_id(args) do
    value =
      Map.get(args, "session_id") ||
        Map.get(args, "sessionId") ||
        Map.get(args, :session_id) ||
        Map.get(args, :sessionId) ||
        Map.get(args, "process_id") ||
        Map.get(args, "processId")

    case value do
      nil -> {:error, {:missing_argument, :session_id}}
      "" -> {:error, {:invalid_argument, :session_id}}
      other -> {:ok, to_string(other)}
    end
  end

  defp resolve_connection(%{thread: %Thread{transport: {:app_server, conn}}} = _context)
       when is_pid(conn) do
    {:ok, conn}
  end

  defp resolve_connection(_context), do: {:error, :unsupported_transport}

  defp command_write_opts(context, payload) do
    event = Map.get(context, :event)

    []
    |> maybe_put(:thread_id, event && event.thread_id)
    |> maybe_put(:turn_id, event && event.turn_id)
    |> maybe_put(:yield_time_ms, payload.yield_time_ms)
    |> maybe_put(:max_output_tokens, payload.max_output_tokens)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end

defmodule Codex.Tools.ViewImageTool do
  @moduledoc """
  Hosted tool for attaching local images to the conversation.
  """

  @behaviour Codex.Tool

  alias Codex.Thread
  alias Codex.ToolOutput

  @image_mime_types %{
    "png" => "image/png",
    "jpg" => "image/jpeg",
    "jpeg" => "image/jpeg",
    "gif" => "image/gif",
    "webp" => "image/webp",
    "bmp" => "image/bmp",
    "tif" => "image/tiff",
    "tiff" => "image/tiff",
    "ico" => "image/x-icon"
  }

  @impl true
  def metadata do
    %{
      name: "view_image",
      description:
        "Attach a local image (by filesystem path) to the conversation context for this turn.",
      enabled?: &enabled?/2,
      schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{
            "type" => "string",
            "description" => "Local filesystem path to an image file"
          }
        },
        "required" => ["path"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def invoke(args, context) do
    path = Map.get(args, "path") || Map.get(args, :path)

    with {:ok, raw_path} <- require_path(path),
         {:ok, abs_path} <- resolve_path(raw_path, context),
         :ok <- ensure_file(abs_path),
         {:ok, data_url} <- build_data_url(abs_path) do
      {:ok, [ToolOutput.text("attached local image path"), ToolOutput.image(url: data_url)]}
    end
  end

  defp enabled?(context, _metadata) do
    case Map.get(context, :thread) do
      %Thread{thread_opts: %{view_image_tool_enabled: true}} ->
        true

      %Thread{thread_opts: %{view_image_tool_enabled: false}} ->
        false

      %Thread{thread_opts: opts} ->
        feature_enabled_from_config(opts)

      nil ->
        true

      _ ->
        false
    end
  end

  defp feature_enabled_from_config(%{config: %{"features" => %{"view_image_tool" => value}}})
       when is_boolean(value),
       do: value

  defp feature_enabled_from_config(_opts), do: false

  defp require_path(path) when is_binary(path) and path != "", do: {:ok, path}
  defp require_path(_), do: {:error, {:invalid_argument, :path}}

  defp resolve_path(path, context) do
    thread = Map.get(context, :thread)

    cwd =
      Map.get(context, :cwd) ||
        (thread &&
           thread.thread_opts &&
           thread.thread_opts.working_directory) ||
        File.cwd!()

    expanded =
      case Path.type(path) do
        :absolute -> Path.expand(path)
        _ -> Path.expand(path, cwd)
      end

    {:ok, expanded}
  end

  defp ensure_file(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular}} -> :ok
      {:ok, _} -> {:error, {:invalid_image_path, :not_a_file}}
      {:error, reason} -> {:error, {:invalid_image_path, reason}}
    end
  end

  defp build_data_url(path) do
    ext =
      path
      |> Path.extname()
      |> String.trim_leading(".")
      |> String.downcase()

    case Map.fetch(@image_mime_types, ext) do
      {:ok, mime} ->
        with {:ok, contents} <- File.read(path) do
          encoded = Base.encode64(contents)
          {:ok, "data:" <> mime <> ";base64," <> encoded}
        end

      :error ->
        {:error, {:unsupported_image_type, ext}}
    end
  end
end

# WebSearchTool is now defined in lib/codex/tools/web_search_tool.ex
# with support for Tavily, Serper, and mock providers

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

defmodule Codex.Items do
  @moduledoc """
  Typed representations of thread items emitted by the Codex runtime.

  This module provides helpers to convert JSON-style maps (with string keys)
  into structs and back, keeping status fields normalised as atoms.
  """

  alias __MODULE__.{
    AgentMessage,
    CommandExecution,
    Error,
    FileChange,
    ImageView,
    McpToolCall,
    Reasoning,
    ReviewMode,
    TodoList,
    UserMessage,
    WebSearch
  }

  @type t ::
          AgentMessage.t()
          | Reasoning.t()
          | CommandExecution.t()
          | FileChange.t()
          | UserMessage.t()
          | ImageView.t()
          | ReviewMode.t()
          | McpToolCall.t()
          | WebSearch.t()
          | TodoList.t()
          | Error.t()

  defmodule AgentMessage do
    @moduledoc """
    Assistant-authored message item emitted by the Codex runtime, with optional parsed
    payloads for structured output experiments.
    """

    @enforce_keys [:text]
    defstruct id: nil, type: :agent_message, text: nil, parsed: nil

    @type t :: %__MODULE__{
            id: String.t() | nil,
            type: :agent_message,
            text: String.t(),
            parsed: map() | list() | nil
          }
  end

  defmodule Reasoning do
    @moduledoc """
    Intermediate reasoning trace shared as part of tool or agent transparency.
    """

    @enforce_keys [:text]
    defstruct id: nil, type: :reasoning, text: nil

    @type t :: %__MODULE__{
            id: String.t() | nil,
            type: :reasoning,
            text: String.t()
          }
  end

  defmodule CommandExecution do
    @moduledoc """
    Captures an execution request made by the agent, including aggregated output and
    status metadata.
    """

    @enforce_keys [:command]
    defstruct id: nil,
              type: :command_execution,
              command: nil,
              cwd: nil,
              process_id: nil,
              command_actions: [],
              aggregated_output: "",
              exit_code: nil,
              status: :in_progress,
              duration_ms: nil

    @type status :: :in_progress | :completed | :failed | :declined

    @type t :: %__MODULE__{
            id: String.t() | nil,
            type: :command_execution,
            command: String.t(),
            cwd: String.t() | nil,
            process_id: String.t() | nil,
            command_actions: [map()],
            aggregated_output: String.t(),
            exit_code: integer() | nil,
            status: status(),
            duration_ms: integer() | nil
          }
  end

  defmodule FileChange do
    @moduledoc """
    Represents a file diff emitted by the agent, including per-path change metadata and
    completion status.
    """

    @enforce_keys [:changes, :status]
    defstruct id: nil,
              type: :file_change,
              changes: [],
              status: :completed

    @type change_kind :: :add | :delete | :update
    @type change :: %{
            required(:path) => String.t(),
            required(:kind) => change_kind(),
            optional(:diff) => String.t(),
            optional(:move_path) => String.t() | nil
          }

    @type status :: :in_progress | :completed | :failed | :declined

    @type t :: %__MODULE__{
            id: String.t() | nil,
            type: :file_change,
            changes: [change()],
            status: status()
          }
  end

  defmodule McpToolCall do
    @moduledoc """
    Metadata describing a tool invocation routed through an MCP server.
    """

    @enforce_keys [:server, :tool]
    defstruct id: nil,
              type: :mcp_tool_call,
              server: nil,
              tool: nil,
              arguments: nil,
              result: nil,
              error: nil,
              status: :in_progress,
              duration_ms: nil

    @type status :: :in_progress | :completed | :failed

    @type t :: %__MODULE__{
            id: String.t() | nil,
            type: :mcp_tool_call,
            server: String.t(),
            tool: String.t(),
            arguments: map() | list() | nil,
            result: map() | nil,
            error: map() | nil,
            status: status(),
            duration_ms: integer() | nil
          }
  end

  defmodule UserMessage do
    @moduledoc """
    User-authored message item carrying a list of input blocks.
    """

    @enforce_keys [:content]
    defstruct id: nil, type: :user_message, content: []

    @type t :: %__MODULE__{
            id: String.t() | nil,
            type: :user_message,
            content: [map()]
          }
  end

  defmodule ImageView do
    @moduledoc """
    An image view event emitted by the app-server when it renders a local image.
    """

    @enforce_keys [:path]
    defstruct id: nil, type: :image_view, path: nil

    @type t :: %__MODULE__{
            id: String.t() | nil,
            type: :image_view,
            path: String.t()
          }
  end

  defmodule ReviewMode do
    @moduledoc """
    Indicates that review mode has been entered or exited.
    """

    @enforce_keys [:review]
    defstruct id: nil, type: :review_mode, entered: true, review: ""

    @type t :: %__MODULE__{
            id: String.t() | nil,
            type: :review_mode,
            entered: boolean(),
            review: String.t()
          }
  end

  defmodule WebSearch do
    @moduledoc """
    Records a web search request issued by the agent, preserving the original query.
    """

    @enforce_keys [:query]
    defstruct id: nil, type: :web_search, query: nil

    @type t :: %__MODULE__{
            id: String.t() | nil,
            type: :web_search,
            query: String.t()
          }
  end

  defmodule TodoList do
    @moduledoc """
    Structured checklist shared by the agent to track outstanding follow-up items.
    """

    @enforce_keys [:items]
    defstruct id: nil, type: :todo_list, items: []

    @type todo_item :: %{text: String.t(), completed: boolean()}

    @type t :: %__MODULE__{
            id: String.t() | nil,
            type: :todo_list,
            items: [todo_item()]
          }
  end

  defmodule Error do
    @moduledoc """
    Normalised error record describing failures surfaced during a turn.
    """

    @enforce_keys [:message]
    defstruct id: nil, type: :error, message: nil

    @type t :: %__MODULE__{
            id: String.t() | nil,
            type: :error,
            message: String.t()
          }
  end

  @command_status_map %{
    "in_progress" => :in_progress,
    "completed" => :completed,
    "failed" => :failed,
    "declined" => :declined
  }

  @file_change_status_map %{
    "in_progress" => :in_progress,
    "completed" => :completed,
    "failed" => :failed,
    "declined" => :declined
  }

  @file_change_kind_map %{
    "add" => :add,
    "delete" => :delete,
    "update" => :update
  }

  @mcp_status_map %{
    "in_progress" => :in_progress,
    "completed" => :completed,
    "failed" => :failed
  }

  @doc """
  Parses a JSON-decoded map into a typed thread item struct.
  """
  @spec parse!(map()) :: t()
  def parse!(%{"type" => "agent_message"} = map), do: parse_agent_message(map)
  def parse!(%{"type" => "reasoning"} = map), do: parse_reasoning(map)
  def parse!(%{"type" => "command_execution"} = map), do: parse_command_execution(map)
  def parse!(%{"type" => "file_change"} = map), do: parse_file_change(map)
  def parse!(%{"type" => "user_message"} = map), do: parse_user_message(map)
  def parse!(%{"type" => "image_view"} = map), do: parse_image_view(map)
  def parse!(%{"type" => "review_mode"} = map), do: parse_review_mode(map)
  def parse!(%{"type" => "mcp_tool_call"} = map), do: parse_mcp_tool_call(map)
  def parse!(%{"type" => "web_search"} = map), do: parse_web_search(map)
  def parse!(%{"type" => "todo_list"} = map), do: parse_todo_list(map)
  def parse!(%{"type" => "error"} = map), do: parse_error(map)
  def parse!(%{type: type} = map), do: parse!(Map.put(map, "type", type))

  def parse!(%{"type" => other}) do
    raise ArgumentError, "unsupported thread item type #{inspect(other)}"
  end

  def parse!(value) do
    raise ArgumentError, "expected thread item map, got: #{inspect(value)}"
  end

  @doc """
  Converts a typed item struct back into its JSON-serialisable map representation.
  """
  @spec to_map(t()) :: map()
  def to_map(%AgentMessage{} = item) do
    base_item_map(item, "agent_message")
    |> maybe_put("text", item.text)
  end

  def to_map(%Reasoning{} = item) do
    base_item_map(item, "reasoning")
    |> maybe_put("text", item.text)
  end

  def to_map(%CommandExecution{} = item) do
    base_item_map(item, "command_execution")
    |> maybe_put("command", item.command)
    |> maybe_put("cwd", item.cwd)
    |> maybe_put("process_id", item.process_id)
    |> maybe_put("command_actions", item.command_actions)
    |> maybe_put("aggregated_output", item.aggregated_output)
    |> maybe_put("exit_code", item.exit_code)
    |> maybe_put("status", status_to_string(item.status, @command_status_map))
    |> maybe_put("duration_ms", item.duration_ms)
  end

  def to_map(%FileChange{} = item) do
    base_item_map(item, "file_change")
    |> maybe_put("status", status_to_string(item.status, @file_change_status_map))
    |> maybe_put(
      "changes",
      Enum.map(item.changes, fn %{path: path, kind: kind} = change ->
        %{
          "path" => path,
          "kind" => kind_to_string(kind, @file_change_kind_map)
        }
        |> maybe_put("diff", Map.get(change, :diff))
        |> maybe_put("move_path", Map.get(change, :move_path))
      end)
    )
  end

  def to_map(%UserMessage{} = item) do
    base_item_map(item, "user_message")
    |> maybe_put("content", item.content)
  end

  def to_map(%ImageView{} = item) do
    base_item_map(item, "image_view")
    |> maybe_put("path", item.path)
  end

  def to_map(%ReviewMode{} = item) do
    base_item_map(item, "review_mode")
    |> maybe_put("entered", item.entered)
    |> maybe_put("review", item.review)
  end

  def to_map(%McpToolCall{} = item) do
    base_item_map(item, "mcp_tool_call")
    |> maybe_put("server", item.server)
    |> maybe_put("tool", item.tool)
    |> maybe_put("arguments", item.arguments)
    |> maybe_put("result", item.result)
    |> maybe_put("error", item.error)
    |> maybe_put("status", status_to_string(item.status, @mcp_status_map))
    |> maybe_put("duration_ms", item.duration_ms)
  end

  def to_map(%WebSearch{} = item) do
    base_item_map(item, "web_search")
    |> maybe_put("query", item.query)
  end

  def to_map(%TodoList{} = item) do
    base_item_map(item, "todo_list")
    |> maybe_put(
      "items",
      Enum.map(item.items, fn %{text: text, completed: completed} ->
        %{"text" => text, "completed" => completed}
      end)
    )
  end

  def to_map(%Error{} = item) do
    base_item_map(item, "error")
    |> maybe_put("message", item.message)
  end

  defp parse_agent_message(map) do
    %AgentMessage{
      id: get(map, :id),
      text: get(map, :text) || "",
      parsed: get(map, :parsed)
    }
  end

  defp parse_reasoning(map) do
    %Reasoning{
      id: get(map, :id),
      text: get(map, :text) || ""
    }
  end

  defp parse_command_execution(map) do
    %CommandExecution{
      id: get(map, :id),
      command: get(map, :command) || "",
      cwd: get(map, :cwd),
      process_id: get(map, :process_id),
      command_actions: get(map, :command_actions) || [],
      aggregated_output: get(map, :aggregated_output) || "",
      exit_code: get(map, :exit_code),
      status: parse_status(get(map, :status), @command_status_map, :in_progress),
      duration_ms: get(map, :duration_ms)
    }
  end

  defp parse_file_change(map) do
    %FileChange{
      id: get(map, :id),
      status: parse_status(get(map, :status), @file_change_status_map, :completed),
      changes:
        map
        |> get(:changes, [])
        |> Enum.map(fn change ->
          %{
            path: get(change, :path) || "",
            kind: parse_kind(get(change, :kind), @file_change_kind_map),
            diff: get(change, :diff),
            move_path: get(change, :move_path)
          }
        end)
    }
  end

  defp parse_user_message(map) do
    %UserMessage{
      id: get(map, :id),
      content: get(map, :content) || []
    }
  end

  defp parse_image_view(map) do
    %ImageView{
      id: get(map, :id),
      path: get(map, :path) || ""
    }
  end

  defp parse_review_mode(map) do
    %ReviewMode{
      id: get(map, :id),
      entered: !!get(map, :entered),
      review: get(map, :review) || ""
    }
  end

  defp parse_mcp_tool_call(map) do
    %McpToolCall{
      id: get(map, :id),
      server: get(map, :server) || "",
      tool: get(map, :tool) || "",
      arguments: get(map, :arguments),
      result: get(map, :result),
      error: get(map, :error),
      status: parse_status(get(map, :status), @mcp_status_map, :in_progress),
      duration_ms: get(map, :duration_ms)
    }
  end

  defp parse_web_search(map) do
    %WebSearch{
      id: get(map, :id),
      query: get(map, :query) || ""
    }
  end

  defp parse_todo_list(map) do
    %TodoList{
      id: get(map, :id),
      items:
        map
        |> get(:items, [])
        |> Enum.map(fn item ->
          %{
            text: get(item, :text) || "",
            completed: !!get(item, :completed)
          }
        end)
    }
  end

  defp parse_error(map) do
    %Error{
      id: get(map, :id),
      message: get(map, :message) || ""
    }
  end

  defp base_item_map(item, type) do
    %{"type" => type}
    |> maybe_put("id", item.id)
  end

  defp parse_status(nil, _mapping, default), do: default

  defp parse_status(value, mapping, default) when is_atom(value) do
    value
    |> Atom.to_string()
    |> parse_status(mapping, default)
  end

  defp parse_status(value, mapping, default) when is_binary(value) do
    Map.get(mapping, value, default)
  end

  defp parse_status(value, _mapping, default) do
    value
    |> to_string()
    |> parse_status(%{}, default)
  end

  defp parse_kind(nil, mapping), do: mapping["update"]

  defp parse_kind(kind, mapping) when is_atom(kind) do
    parse_kind(Atom.to_string(kind), mapping)
  end

  defp parse_kind(kind, mapping) when is_binary(kind) do
    Map.get(mapping, kind, :update)
  end

  defp status_to_string(nil, _mapping), do: nil

  defp status_to_string(atom, _mapping) when is_atom(atom), do: Atom.to_string(atom)

  defp status_to_string(value, _mapping) when is_binary(value), do: value

  defp kind_to_string(nil, _mapping), do: "update"
  defp kind_to_string(atom, _mapping) when is_atom(atom), do: Atom.to_string(atom)
  defp kind_to_string(value, _mapping) when is_binary(value), do: value

  defp get(map, key), do: get(map, key, nil)

  defp get(map, key, default) when is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> get(map, Atom.to_string(key), default)
    end
  end

  defp get(map, key, default) when is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> fetch_atom_key(map, key, default)
    end
  end

  defp fetch_atom_key(map, key, default) do
    key
    |> String.to_existing_atom()
    |> then(&Map.get(map, &1, default))
  rescue
    ArgumentError -> default
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

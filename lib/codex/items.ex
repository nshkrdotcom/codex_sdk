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
    McpToolCall,
    Reasoning,
    TodoList,
    WebSearch
  }

  @type t ::
          AgentMessage.t()
          | Reasoning.t()
          | CommandExecution.t()
          | FileChange.t()
          | McpToolCall.t()
          | WebSearch.t()
          | TodoList.t()
          | Error.t()

  defmodule AgentMessage do
    @moduledoc false

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
    @moduledoc false

    @enforce_keys [:text]
    defstruct id: nil, type: :reasoning, text: nil

    @type t :: %__MODULE__{
            id: String.t() | nil,
            type: :reasoning,
            text: String.t()
          }
  end

  defmodule CommandExecution do
    @moduledoc false

    @enforce_keys [:command]
    defstruct id: nil,
              type: :command_execution,
              command: nil,
              aggregated_output: "",
              exit_code: nil,
              status: :in_progress

    @type status :: :in_progress | :completed | :failed

    @type t :: %__MODULE__{
            id: String.t() | nil,
            type: :command_execution,
            command: String.t(),
            aggregated_output: String.t(),
            exit_code: integer() | nil,
            status: status()
          }
  end

  defmodule FileChange do
    @moduledoc false

    @enforce_keys [:changes, :status]
    defstruct id: nil,
              type: :file_change,
              changes: [],
              status: :completed

    @type change_kind :: :add | :delete | :update
    @type change :: %{path: String.t(), kind: change_kind()}

    @type status :: :completed | :failed

    @type t :: %__MODULE__{
            id: String.t() | nil,
            type: :file_change,
            changes: [change()],
            status: status()
          }
  end

  defmodule McpToolCall do
    @moduledoc false

    @enforce_keys [:server, :tool]
    defstruct id: nil,
              type: :mcp_tool_call,
              server: nil,
              tool: nil,
              status: :in_progress

    @type status :: :in_progress | :completed | :failed

    @type t :: %__MODULE__{
            id: String.t() | nil,
            type: :mcp_tool_call,
            server: String.t(),
            tool: String.t(),
            status: status()
          }
  end

  defmodule WebSearch do
    @moduledoc false

    @enforce_keys [:query]
    defstruct id: nil, type: :web_search, query: nil

    @type t :: %__MODULE__{
            id: String.t() | nil,
            type: :web_search,
            query: String.t()
          }
  end

  defmodule TodoList do
    @moduledoc false

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
    @moduledoc false

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
    "failed" => :failed
  }

  @file_change_status_map %{
    "completed" => :completed,
    "failed" => :failed
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
    |> maybe_put("aggregated_output", item.aggregated_output)
    |> maybe_put("exit_code", item.exit_code)
    |> maybe_put("status", status_to_string(item.status, @command_status_map))
  end

  def to_map(%FileChange{} = item) do
    base_item_map(item, "file_change")
    |> maybe_put("status", status_to_string(item.status, @file_change_status_map))
    |> maybe_put(
      "changes",
      Enum.map(item.changes, fn %{path: path, kind: kind} ->
        %{
          "path" => path,
          "kind" => kind_to_string(kind, @file_change_kind_map)
        }
      end)
    )
  end

  def to_map(%McpToolCall{} = item) do
    base_item_map(item, "mcp_tool_call")
    |> maybe_put("server", item.server)
    |> maybe_put("tool", item.tool)
    |> maybe_put("status", status_to_string(item.status, @mcp_status_map))
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
      aggregated_output: get(map, :aggregated_output) || "",
      exit_code: get(map, :exit_code),
      status: parse_status(get(map, :status), @command_status_map, :in_progress)
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
            kind: parse_kind(get(change, :kind), @file_change_kind_map)
          }
        end)
    }
  end

  defp parse_mcp_tool_call(map) do
    %McpToolCall{
      id: get(map, :id),
      server: get(map, :server) || "",
      tool: get(map, :tool) || "",
      status: parse_status(get(map, :status), @mcp_status_map, :in_progress)
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
    Map.get(map, key) || Map.get(map, Atom.to_string(key)) || default
  end

  defp get(map, key, default) when is_binary(key) do
    Map.get(map, key) || fetch_atom_key(map, key) || default
  end

  defp get(map, key, default) do
    Map.get(map, key, default)
  end

  defp fetch_atom_key(map, key) do
    key
    |> String.to_existing_atom()
    |> then(&Map.get(map, &1))
  rescue
    ArgumentError -> nil
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

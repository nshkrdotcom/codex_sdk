defmodule Codex.Handoff do
  @moduledoc """
  Represents a handoff from one agent to another, wrapping the downstream agent as a tool with
  optional input filtering and history nesting controls.
  """

  alias Codex.Agent

  defmodule InputData do
    @moduledoc """
    Carries conversation history and run context into handoff input filters.
    """

    @enforce_keys [:input_history, :pre_handoff_items, :new_items]
    defstruct input_history: nil,
              pre_handoff_items: [],
              new_items: [],
              run_context: nil

    @type t :: %__MODULE__{
            input_history: term(),
            pre_handoff_items: list(),
            new_items: list(),
            run_context: term()
          }
  end

  @enforce_keys [:tool_name, :tool_description, :agent_name, :on_invoke_handoff]
  defstruct tool_name: nil,
            tool_description: nil,
            agent_name: nil,
            agent: nil,
            on_invoke_handoff: nil,
            input_schema: %{},
            input_filter: nil,
            nest_handoff_history: nil,
            strict_json_schema: true,
            is_enabled: true

  @type is_enabled :: boolean() | (map(), Agent.t() -> boolean() | term())

  @type t :: %__MODULE__{
          tool_name: String.t(),
          tool_description: String.t(),
          agent_name: String.t(),
          agent: Agent.t() | nil,
          on_invoke_handoff: (map(), term() -> Agent.t()),
          input_schema: map(),
          input_filter: (InputData.t() -> InputData.t()) | nil,
          nest_handoff_history: boolean() | nil,
          strict_json_schema: boolean(),
          is_enabled: is_enabled()
        }

  @doc """
  Wraps an agent as a handoff with optional overrides.

  Options:
    * `:tool_name` - override the default tool name
    * `:tool_description` - override the default tool description
    * `:input_filter` - function invoked to filter history passed to the downstream agent
    * `:nest_handoff_history` - override history nesting behaviour
    * `:input_schema` - optional JSON schema map describing expected input
    * `:strict_json_schema` - whether the schema should be treated as strict (default: true)
    * `:is_enabled` - boolean or function to dynamically enable the handoff
  """
  @spec wrap(Agent.t(), keyword()) :: t()
  def wrap(%Agent{} = agent, opts \\ []) do
    tool_name = Keyword.get(opts, :tool_name, default_tool_name(agent))
    tool_description = Keyword.get(opts, :tool_description, default_tool_description(agent))
    on_invoke = Keyword.get(opts, :on_invoke, fn _ctx, _input -> agent end)
    input_schema = Keyword.get(opts, :input_schema, %{})

    %__MODULE__{
      tool_name: to_string(tool_name),
      tool_description: to_string(tool_description),
      agent_name: agent.name || "",
      agent: agent,
      on_invoke_handoff: on_invoke,
      input_schema: input_schema || %{},
      input_filter: Keyword.get(opts, :input_filter),
      nest_handoff_history: Keyword.get(opts, :nest_handoff_history),
      strict_json_schema: Keyword.get(opts, :strict_json_schema, true),
      is_enabled: Keyword.get(opts, :is_enabled, true)
    }
  end

  @doc """
  Default tool name derived from the downstream agent name.
  """
  @spec default_tool_name(Agent.t()) :: String.t()
  def default_tool_name(%Agent{name: name}) do
    safe =
      name
      |> to_string()
      |> String.trim()
      |> String.replace(~r/\s+/, "_")
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> String.downcase()

    "transfer_to_#{safe}"
  end

  @doc """
  Default tool description referencing the downstream agent.
  """
  @spec default_tool_description(Agent.t()) :: String.t()
  def default_tool_description(%Agent{name: name, handoff_description: desc}) do
    trimmed =
      case desc do
        nil -> ""
        value -> String.trim(to_string(value))
      end

    base = "Handoff to the #{name} agent to handle the request."

    if trimmed == "" do
      base
    else
      "#{base} #{trimmed}"
    end
  end

  @doc """
  Evaluates whether a handoff is enabled for the given context/agent.
  """
  @spec enabled?(t(), map(), Agent.t()) :: boolean()
  def enabled?(%__MODULE__{is_enabled: flag}, _context, %Agent{} = _agent) when is_boolean(flag),
    do: flag

  def enabled?(%__MODULE__{is_enabled: fun}, context, %Agent{} = agent)
      when is_function(fun, 2) do
    fun.(context, agent) |> truthy?()
  end

  def enabled?(%__MODULE__{is_enabled: fun}, context, %Agent{} = _agent)
      when is_function(fun, 1) do
    fun.(context) |> truthy?()
  end

  def enabled?(_handoff, _context, _agent), do: true

  defp truthy?(value) when value in [true, "true", "TRUE", "True"], do: true
  defp truthy?(_), do: false
end

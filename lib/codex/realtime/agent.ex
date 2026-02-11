defmodule Codex.Realtime.Agent do
  @moduledoc """
  A realtime agent optimized for voice interactions.

  Realtime agents are specialized agents meant to be used within a `Codex.Realtime.Session`
  to build voice agents. Due to the nature of this agent, some configuration options differ
  from regular `Codex.Agent` instances:

  - `model` choice is constrained to realtime-capable models
  - Output types and structured outputs are not supported
  - Voice can be configured at the agent level

  ## Features

  - Voice-to-voice communication
  - Tool execution during conversations
  - Handoffs to other agents
  - Dynamic instructions (string or function)
  - Output guardrails

  ## Examples

      # Simple agent
      agent = %Codex.Realtime.Agent{
        name: "Assistant",
        instructions: "You are a helpful voice assistant."
      }

      # Agent with dynamic instructions
      agent = %Codex.Realtime.Agent{
        name: "Greeter",
        instructions: fn ctx -> "Welcome \#{ctx.user_name}!" end
      }

      # Agent with handoffs
      support_agent = %Codex.Realtime.Agent{name: "Support"}
      main_agent = %Codex.Realtime.Agent{
        name: "Main",
        handoffs: [support_agent]
      }
  """

  alias Codex.Handoff

  @type instruction_fn ::
          (map() -> String.t())
          | (map(), t() -> String.t())

  @default_model "gpt-4o-realtime-preview"

  defstruct name: "Agent",
            handoff_description: nil,
            handoffs: [],
            model: @default_model,
            instructions: "You are a helpful assistant.",
            tools: [],
            output_guardrails: [],
            hooks: nil

  @type t :: %__MODULE__{
          name: String.t(),
          handoff_description: String.t() | nil,
          handoffs: [t() | Handoff.t()],
          model: String.t(),
          instructions: String.t() | instruction_fn() | nil,
          tools: [module()],
          output_guardrails: [term()],
          hooks: term()
        }

  @doc """
  Returns the default realtime model name.
  """
  @spec default_model() :: String.t()
  def default_model, do: @default_model

  @doc """
  Create a new realtime agent from keyword options.

  ## Examples

      agent = Codex.Realtime.Agent.new(
        name: "VoiceBot",
        instructions: "Be helpful and concise."
      )
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @doc """
  Create a copy of the agent with the given fields changed.

  ## Examples

      new_agent = Codex.Realtime.Agent.clone(agent, name: "NewName")
  """
  @spec clone(t(), keyword()) :: t()
  def clone(%__MODULE__{} = agent, changes) do
    struct(agent, changes)
  end

  @doc """
  Resolve instructions, calling function if needed.

  Supports both arity-1 functions (receiving context) and arity-2 functions
  (receiving context and agent).

  ## Examples

      # String instructions
      agent = %Agent{instructions: "Be helpful"}
      Agent.resolve_instructions(agent, %{}) #=> "Be helpful"

      # Function instructions (arity 1)
      agent = %Agent{instructions: fn ctx -> "Hello \#{ctx.user}" end}
      Agent.resolve_instructions(agent, %{user: "Alice"}) #=> "Hello Alice"

      # Function instructions (arity 2)
      agent = %Agent{
        name: "Bot",
        instructions: fn ctx, agent -> "Hello \#{ctx.user}, I'm \#{agent.name}" end
      }
      Agent.resolve_instructions(agent, %{user: "Bob"}) #=> "Hello Bob, I'm Bot"
  """
  @spec resolve_instructions(t(), map()) :: String.t() | nil
  def resolve_instructions(%__MODULE__{instructions: instructions}, _context)
      when is_binary(instructions) do
    instructions
  end

  def resolve_instructions(%__MODULE__{instructions: nil}, _context) do
    nil
  end

  def resolve_instructions(%__MODULE__{instructions: fun} = agent, context)
      when is_function(fun, 2) do
    fun.(context, agent)
  end

  def resolve_instructions(%__MODULE__{instructions: fun}, context)
      when is_function(fun, 1) do
    fun.(context)
  end

  @doc """
  Get all tools including handoff tools.

  Returns the agent's tools combined with auto-generated handoff tools
  for each configured handoff.

  ## Examples

      support = %Agent{name: "Support"}
      agent = %Agent{tools: [MyTool], handoffs: [support]}
      Agent.get_tools(agent)
      #=> [MyTool, %Handoff{tool_name: "transfer_to_support", ...}]
  """
  @spec get_tools(t()) :: [module() | Handoff.t()]
  def get_tools(%__MODULE__{tools: tools, handoffs: handoffs}) do
    handoff_tools = Enum.map(handoffs, &create_handoff_tool/1)
    tools ++ handoff_tools
  end

  @doc """
  Find handoff target by tool name.

  Given a tool name like "transfer_to_support", finds the corresponding
  agent or handoff target in the handoffs list.

  ## Examples

      support = %Agent{name: "Support"}
      agent = %Agent{handoffs: [support]}
      {:ok, target} = Agent.find_handoff_target(agent, "transfer_to_support")
      target.name #=> "Support"
  """
  @spec find_handoff_target(t(), String.t()) ::
          {:ok, t() | Codex.Agent.t()} | {:error, :not_found}
  def find_handoff_target(%__MODULE__{handoffs: handoffs}, tool_name) do
    # Tool names follow the pattern "transfer_to_<agent_name>"
    case extract_agent_name(tool_name) do
      nil ->
        {:error, :not_found}

      target_name ->
        case find_matching_handoff(handoffs, target_name) do
          nil -> {:error, :not_found}
          handoff -> {:ok, normalize_target(handoff)}
        end
    end
  end

  # Private Functions

  defp create_handoff_tool(%__MODULE__{} = agent) do
    %Handoff{
      tool_name: default_tool_name(agent.name),
      tool_description: default_tool_description(agent.name, agent.handoff_description),
      agent_name: agent.name,
      agent: nil,
      on_invoke_handoff: fn _ctx, _input -> agent end,
      input_schema: %{},
      input_filter: nil,
      nest_handoff_history: nil,
      strict_json_schema: true,
      is_enabled: true
    }
  end

  defp create_handoff_tool(%Handoff{} = handoff) do
    handoff
  end

  defp default_tool_name(name) do
    safe_name =
      name
      |> to_string()
      |> String.trim()
      |> String.replace(~r/\s+/, "_")
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> String.downcase()

    "transfer_to_#{safe_name}"
  end

  defp default_tool_description(name, nil) do
    "Handoff to the #{name} agent to handle the request."
  end

  defp default_tool_description(name, description) do
    trimmed = String.trim(to_string(description))

    if trimmed == "" do
      default_tool_description(name, nil)
    else
      "Handoff to the #{name} agent to handle the request. #{trimmed}"
    end
  end

  defp extract_agent_name("transfer_to_" <> rest), do: rest
  defp extract_agent_name(_), do: nil

  defp find_matching_handoff(handoffs, target_name) do
    Enum.find(handoffs, fn handoff ->
      handoff_tool_name = get_handoff_tool_name(handoff)
      # Compare the suffix part after "transfer_to_"
      String.ends_with?(handoff_tool_name, target_name)
    end)
  end

  defp get_handoff_tool_name(%__MODULE__{name: name}) do
    default_tool_name(name)
  end

  defp get_handoff_tool_name(%Handoff{tool_name: tool_name}) do
    tool_name
  end

  defp normalize_target(%__MODULE__{} = agent), do: agent
  defp normalize_target(%Handoff{agent: agent}) when not is_nil(agent), do: agent

  defp normalize_target(%Handoff{on_invoke_handoff: invoke_fn}) do
    # For handoffs without a direct agent reference, invoke the function
    # with empty context to get the target
    invoke_fn.(%{}, nil)
  end
end

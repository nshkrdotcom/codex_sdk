defmodule Codex.Voice.AgentWorkflow do
  @moduledoc """
  A workflow that wraps a Codex.Agent for voice interactions.

  This allows using standard agents with the voice pipeline.

  ## Example

      agent = %Codex.Agent{
        name: "Assistant",
        instructions: "Be helpful and concise."
      }

      workflow = AgentWorkflow.new(agent)
      pipeline = Pipeline.new(workflow: workflow)
  """

  @behaviour Codex.Voice.Workflow

  alias Codex.Agent
  alias Codex.Items

  defstruct [:agent, :context, :history]

  @type t :: %__MODULE__{
          agent: Agent.t(),
          context: map(),
          history: list()
        }

  @doc "Create a new agent workflow."
  @spec new(Agent.t(), keyword()) :: t()
  def new(agent, opts \\ []) do
    %__MODULE__{
      agent: agent,
      context: Keyword.get(opts, :context, %{}),
      history: []
    }
  end

  @impl Codex.Voice.Workflow
  def run(%__MODULE__{} = workflow, transcription) do
    # Note: history tracking would be used for multi-turn context in future enhancements
    _history = workflow.history ++ [%{role: "user", content: transcription}]

    # Create a thread and run the agent
    with {:ok, thread} <- Codex.start_thread(),
         {:ok, result} <- Codex.Thread.run(thread, transcription, %{agent: workflow.agent}) do
      # Extract the response text
      case result.final_response do
        %Items.AgentMessage{text: text} when is_binary(text) and text != "" ->
          [text]

        _ ->
          []
      end
    else
      {:error, _reason} ->
        ["I'm sorry, I encountered an error processing your request."]
    end
  end

  @impl Codex.Voice.Workflow
  def on_start(%__MODULE__{agent: agent}) do
    # Generate a greeting based on agent instructions
    greeting =
      case agent.instructions do
        instructions when is_binary(instructions) ->
          if String.contains?(instructions, "greeting") do
            "Hello! How can I assist you today?"
          else
            []
          end

        _ ->
          []
      end

    List.wrap(greeting)
  end
end

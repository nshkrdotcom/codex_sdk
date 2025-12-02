defmodule Codex.Agent do
  @moduledoc """
  Defines a reusable agent with instructions, tools, and hooks.
  """

  @enforce_keys []
  defstruct name: nil,
            instructions: nil,
            prompt: nil,
            handoff_description: nil,
            handoffs: [],
            tools: [],
            tool_use_behavior: :run_llm_again,
            reset_tool_choice: true,
            input_guardrails: [],
            output_guardrails: [],
            tool_input_guardrails: [],
            tool_output_guardrails: [],
            hooks: nil,
            model: nil,
            model_settings: nil

  @type t :: %__MODULE__{
          name: String.t() | nil,
          instructions: String.t() | nil,
          prompt: map() | String.t() | nil,
          handoffs: list(),
          tools: list(),
          handoff_description: String.t() | nil,
          tool_use_behavior:
            :run_llm_again
            | :stop_on_first_tool
            | %{optional(:stop_at_tool_names) => [String.t()]}
            | function()
            | nil,
          reset_tool_choice: boolean(),
          input_guardrails: list(),
          output_guardrails: list(),
          tool_input_guardrails: list(),
          tool_output_guardrails: list(),
          hooks: term(),
          model: String.t() | nil,
          model_settings: map() | struct() | nil
        }

  @doc """
  Builds a validated `%Codex.Agent{}` struct.
  """
  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = agent), do: {:ok, agent}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    name = Map.get(attrs, :name, Map.get(attrs, "name"))
    instructions = Map.get(attrs, :instructions, Map.get(attrs, "instructions"))
    prompt = Map.get(attrs, :prompt, Map.get(attrs, "prompt"))

    handoff_description =
      Map.get(attrs, :handoff_description, Map.get(attrs, "handoff_description"))

    handoffs = Map.get(attrs, :handoffs, Map.get(attrs, "handoffs", []))
    tools = Map.get(attrs, :tools, Map.get(attrs, "tools", []))

    tool_use_behavior =
      Map.get(attrs, :tool_use_behavior, Map.get(attrs, "tool_use_behavior", :run_llm_again))

    reset_tool_choice =
      Map.get(attrs, :reset_tool_choice, Map.get(attrs, "reset_tool_choice", true))

    input_guardrails = Map.get(attrs, :input_guardrails, Map.get(attrs, "input_guardrails", []))

    output_guardrails =
      Map.get(attrs, :output_guardrails, Map.get(attrs, "output_guardrails", []))

    tool_input_guardrails =
      Map.get(attrs, :tool_input_guardrails, Map.get(attrs, "tool_input_guardrails", []))

    tool_output_guardrails =
      Map.get(attrs, :tool_output_guardrails, Map.get(attrs, "tool_output_guardrails", []))

    hooks = Map.get(attrs, :hooks, Map.get(attrs, "hooks"))
    model = Map.get(attrs, :model, Map.get(attrs, "model"))
    model_settings = Map.get(attrs, :model_settings, Map.get(attrs, "model_settings"))

    with :ok <- validate_optional_string(name, :name),
         :ok <- validate_optional_string(instructions, :instructions),
         :ok <- validate_prompt(prompt),
         :ok <- validate_optional_string(handoff_description, :handoff_description),
         {:ok, handoffs} <- ensure_list(handoffs, :handoffs),
         {:ok, tools} <- ensure_list(tools, :tools),
         {:ok, tool_use_behavior} <- validate_tool_use_behavior(tool_use_behavior),
         :ok <- validate_boolean(reset_tool_choice, :reset_tool_choice),
         {:ok, input_guardrails} <- ensure_list(input_guardrails, :input_guardrails),
         {:ok, output_guardrails} <- ensure_list(output_guardrails, :output_guardrails),
         {:ok, tool_input_guardrails} <-
           ensure_list(tool_input_guardrails, :tool_input_guardrails),
         {:ok, tool_output_guardrails} <-
           ensure_list(tool_output_guardrails, :tool_output_guardrails),
         :ok <- validate_optional_string(model, :model) do
      {:ok,
       %__MODULE__{
         name: name,
         instructions: instructions,
         prompt: prompt,
         handoff_description: handoff_description,
         handoffs: handoffs,
         tools: tools,
         tool_use_behavior: tool_use_behavior,
         reset_tool_choice: reset_tool_choice,
         input_guardrails: input_guardrails,
         output_guardrails: output_guardrails,
         tool_input_guardrails: tool_input_guardrails,
         tool_output_guardrails: tool_output_guardrails,
         hooks: hooks,
         model: model,
         model_settings: model_settings
       }}
    else
      {:error, _} = error -> error
    end
  end

  defp validate_optional_string(nil, _field), do: :ok
  defp validate_optional_string(value, _field) when is_binary(value), do: :ok
  defp validate_optional_string(value, field), do: {:error, {:"invalid_#{field}", value}}

  defp validate_tool_use_behavior(:auto), do: {:ok, :run_llm_again}
  defp validate_tool_use_behavior("auto"), do: {:ok, :run_llm_again}
  defp validate_tool_use_behavior(:run_llm_again), do: {:ok, :run_llm_again}
  defp validate_tool_use_behavior("run_llm_again"), do: {:ok, :run_llm_again}
  defp validate_tool_use_behavior(:stop_on_first_tool), do: {:ok, :stop_on_first_tool}
  defp validate_tool_use_behavior("stop_on_first_tool"), do: {:ok, :stop_on_first_tool}

  defp validate_tool_use_behavior(%{} = value) do
    names = Map.get(value, :stop_at_tool_names) || Map.get(value, "stop_at_tool_names")

    cond do
      is_list(names) -> {:ok, %{stop_at_tool_names: names}}
      is_nil(names) -> {:error, {:invalid_tool_use_behavior, value}}
      true -> {:error, {:invalid_tool_use_behavior, value}}
    end
  end

  defp validate_tool_use_behavior(fun) when is_function(fun), do: {:ok, fun}
  defp validate_tool_use_behavior(nil), do: {:ok, :run_llm_again}
  defp validate_tool_use_behavior(value), do: {:error, {:invalid_tool_use_behavior, value}}

  defp validate_prompt(nil), do: :ok
  defp validate_prompt(value) when is_map(value), do: :ok
  defp validate_prompt(value) when is_binary(value), do: :ok
  defp validate_prompt(value), do: {:error, {:invalid_prompt, value}}

  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:"invalid_#{field}", value}}

  defp ensure_list(value, _field) when is_list(value), do: {:ok, value}
  defp ensure_list(nil, _field), do: {:ok, []}
  defp ensure_list(value, field), do: {:error, {:"invalid_#{field}", value}}
end

defmodule Codex.RunConfig do
  @moduledoc """
  Per-run configuration applied to agent execution.
  """

  @default_max_turns 10

  @enforce_keys []
  defstruct model: nil,
            model_settings: nil,
            max_turns: @default_max_turns,
            nest_handoff_history: true,
            call_model_input_filter: nil,
            input_guardrails: [],
            output_guardrails: [],
            hooks: nil

  @type t :: %__MODULE__{
          model: String.t() | nil,
          model_settings: map() | struct() | nil,
          max_turns: pos_integer(),
          nest_handoff_history: boolean(),
          call_model_input_filter: function() | nil,
          input_guardrails: list(),
          output_guardrails: list(),
          hooks: term()
        }

  @doc """
  Builds a validated `%Codex.RunConfig{}` struct.
  """
  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = config), do: {:ok, config}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    model = Map.get(attrs, :model, Map.get(attrs, "model"))
    model_settings = Map.get(attrs, :model_settings, Map.get(attrs, "model_settings"))
    max_turns = Map.get(attrs, :max_turns, Map.get(attrs, "max_turns", @default_max_turns))

    nest_handoff_history =
      Map.get(attrs, :nest_handoff_history, Map.get(attrs, "nest_handoff_history", true))

    call_model_input_filter =
      Map.get(attrs, :call_model_input_filter, Map.get(attrs, "call_model_input_filter"))

    input_guardrails = Map.get(attrs, :input_guardrails, Map.get(attrs, "input_guardrails", []))

    output_guardrails =
      Map.get(attrs, :output_guardrails, Map.get(attrs, "output_guardrails", []))

    hooks = Map.get(attrs, :hooks, Map.get(attrs, "hooks"))

    with :ok <- validate_optional_string(model, :model),
         :ok <- validate_max_turns(max_turns),
         :ok <- validate_boolean(nest_handoff_history, :nest_handoff_history),
         :ok <- validate_optional_function(call_model_input_filter, :call_model_input_filter),
         {:ok, input_guardrails} <- ensure_list(input_guardrails, :input_guardrails),
         {:ok, output_guardrails} <- ensure_list(output_guardrails, :output_guardrails) do
      {:ok,
       %__MODULE__{
         model: model,
         model_settings: model_settings,
         max_turns: max_turns,
         nest_handoff_history: nest_handoff_history,
         call_model_input_filter: call_model_input_filter,
         input_guardrails: input_guardrails,
         output_guardrails: output_guardrails,
         hooks: hooks
       }}
    else
      {:error, _} = error -> error
    end
  end

  defp validate_optional_string(nil, _field), do: :ok
  defp validate_optional_string(value, _field) when is_binary(value), do: :ok
  defp validate_optional_string(value, field), do: {:error, {:"invalid_#{field}", value}}

  defp validate_max_turns(value) when is_integer(value) and value > 0, do: :ok
  defp validate_max_turns(value), do: {:error, {:invalid_max_turns, value}}

  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:"invalid_#{field}", value}}

  defp validate_optional_function(nil, _field), do: :ok
  defp validate_optional_function(value, _field) when is_function(value, 1), do: :ok
  defp validate_optional_function(value, field), do: {:error, {:"invalid_#{field}", value}}

  defp ensure_list(value, _field) when is_list(value), do: {:ok, value}
  defp ensure_list(nil, _field), do: {:ok, []}
  defp ensure_list(value, field), do: {:error, {:"invalid_#{field}", value}}
end

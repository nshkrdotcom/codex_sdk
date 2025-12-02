defmodule Codex.RunConfig do
  @moduledoc """
  Per-run configuration applied to agent execution.
  """

  alias Codex.ModelSettings
  alias Codex.Session

  @default_max_turns 10

  @enforce_keys []
  defstruct model: nil,
            model_settings: nil,
            max_turns: @default_max_turns,
            nest_handoff_history: true,
            call_model_input_filter: nil,
            session: nil,
            session_input_callback: nil,
            conversation_id: nil,
            previous_response_id: nil,
            input_guardrails: [],
            output_guardrails: [],
            hooks: nil

  @type t :: %__MODULE__{
          model: String.t() | nil,
          model_settings: map() | struct() | nil,
          max_turns: pos_integer(),
          nest_handoff_history: boolean(),
          call_model_input_filter: function() | nil,
          session: term() | nil,
          session_input_callback: function() | nil,
          conversation_id: String.t() | nil,
          previous_response_id: String.t() | nil,
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

    session = Map.get(attrs, :session, Map.get(attrs, "session"))

    session_input_callback =
      Map.get(attrs, :session_input_callback, Map.get(attrs, "session_input_callback"))

    conversation_id = Map.get(attrs, :conversation_id, Map.get(attrs, "conversation_id"))

    previous_response_id =
      Map.get(attrs, :previous_response_id, Map.get(attrs, "previous_response_id"))

    input_guardrails = Map.get(attrs, :input_guardrails, Map.get(attrs, "input_guardrails", []))

    output_guardrails =
      Map.get(attrs, :output_guardrails, Map.get(attrs, "output_guardrails", []))

    hooks = Map.get(attrs, :hooks, Map.get(attrs, "hooks"))

    with :ok <- validate_optional_string(model, :model),
         {:ok, model_settings} <- normalize_model_settings(model_settings),
         :ok <- validate_max_turns(max_turns),
         :ok <- validate_boolean(nest_handoff_history, :nest_handoff_history),
         :ok <- validate_optional_function(call_model_input_filter, :call_model_input_filter),
         :ok <- validate_session(session),
         :ok <- validate_session_callback(session_input_callback),
         :ok <- validate_optional_string(conversation_id, :conversation_id),
         :ok <- validate_optional_string(previous_response_id, :previous_response_id),
         {:ok, input_guardrails} <- ensure_list(input_guardrails, :input_guardrails),
         {:ok, output_guardrails} <- ensure_list(output_guardrails, :output_guardrails) do
      {:ok,
       %__MODULE__{
         model: model,
         model_settings: model_settings,
         max_turns: max_turns,
         nest_handoff_history: nest_handoff_history,
         call_model_input_filter: call_model_input_filter,
         session: session,
         session_input_callback: session_input_callback,
         conversation_id: conversation_id,
         previous_response_id: previous_response_id,
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

  defp normalize_model_settings(nil), do: {:ok, nil}
  defp normalize_model_settings(%ModelSettings{} = settings), do: {:ok, settings}

  defp normalize_model_settings(settings) do
    ModelSettings.new(settings)
  end

  defp validate_session(nil), do: :ok

  defp validate_session(session) do
    if Session.valid?(session), do: :ok, else: {:error, {:invalid_session, session}}
  end

  defp validate_session_callback(nil), do: :ok

  defp validate_session_callback(fun)
       when is_function(fun, 1) or is_function(fun, 2) or is_function(fun, 3),
       do: :ok

  defp validate_session_callback(value),
    do: {:error, {:invalid_session_input_callback, value}}

  defp ensure_list(value, _field) when is_list(value), do: {:ok, value}
  defp ensure_list(nil, _field), do: {:ok, []}
  defp ensure_list(value, field), do: {:error, {:"invalid_#{field}", value}}
end

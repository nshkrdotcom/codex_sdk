defmodule Codex.Turn.Result do
  @moduledoc """
  Result struct returned from turn execution.
  """

  alias Codex.Events
  alias Codex.Items
  alias Codex.Thread

  @enforce_keys [:thread, :events]
  defstruct thread: nil,
            events: [],
            final_response: nil,
            usage: nil,
            raw: %{},
            attempts: 1

  @type t :: %__MODULE__{
          thread: Thread.t(),
          events: [Events.t()],
          final_response: Items.AgentMessage.t() | map() | nil,
          usage: map() | nil,
          raw: map(),
          attempts: non_neg_integer()
        }

  @doc """
  Returns the decoded structured output when available.

  If the turn produced structured output and it was successfully decoded, the
  parsed map (or list) is returned. When the output is present but could not be
  decoded, an error tuple is returned. For natural language responses, `:not_structured`
  is returned.
  """
  @spec json(t()) :: {:ok, term()} | {:error, term()}
  def json(%__MODULE__{final_response: %Items.AgentMessage{} = message, raw: raw}) do
    structured? = Map.get(raw, :structured_output?, false)

    cond do
      not is_nil(message.parsed) ->
        {:ok, message.parsed}

      structured? and is_binary(message.text) ->
        case Jason.decode(message.text) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, reason} -> {:error, {:invalid_json, reason}}
        end

      structured? ->
        {:error, {:invalid_json, :non_binary}}

      true ->
        {:error, :not_structured}
    end
  end

  def json(_), do: {:error, :not_structured}
end

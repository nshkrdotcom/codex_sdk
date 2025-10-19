defmodule Codex.Turn.Result do
  @moduledoc """
  Result struct returned from turn execution.
  """

  alias Codex.Events
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
          final_response: map() | nil,
          usage: map() | nil,
          raw: map(),
          attempts: non_neg_integer()
        }
end

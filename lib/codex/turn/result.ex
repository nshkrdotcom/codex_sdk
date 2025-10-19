defmodule Codex.Turn.Result do
  @moduledoc """
  Result struct returned from turn execution.
  """

  alias Codex.Thread

  @enforce_keys [:thread, :events]
  defstruct thread: nil,
            events: [],
            final_response: nil,
            usage: nil,
            raw: %{}

  @type t :: %__MODULE__{
          thread: Thread.t(),
          events: [map()],
          final_response: map() | nil,
          usage: map() | nil,
          raw: map()
        }
end

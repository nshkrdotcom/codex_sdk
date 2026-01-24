defmodule Codex.Voice.Workflow do
  @moduledoc """
  Behaviour for voice workflows.

  A workflow processes transcribed text and generates text responses
  to be synthesized as speech.

  ## Example

      defmodule MyWorkflow do
        @behaviour Codex.Voice.Workflow

        defstruct [:context]

        @impl true
        def run(%__MODULE__{} = _workflow, transcription) do
          # Return a stream of text responses
          ["I heard you say: \#{transcription}"]
        end

        @impl true
        def on_start(%__MODULE__{}) do
          ["Hello! I'm ready to help."]
        end
      end
  """

  @doc """
  Process a transcription and return text responses.

  The returned value should be an enumerable of strings that will
  be synthesized as speech.
  """
  @callback run(workflow :: struct(), transcription :: String.t()) :: Enumerable.t()

  @doc """
  Called at the start of a multi-turn session.

  Override to provide an initial greeting. Returns an empty list by default.
  """
  @callback on_start(workflow :: struct()) :: Enumerable.t()

  @optional_callbacks [on_start: 1]
end

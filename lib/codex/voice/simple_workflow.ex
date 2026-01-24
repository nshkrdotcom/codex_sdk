defmodule Codex.Voice.SimpleWorkflow do
  @moduledoc """
  A simple workflow that uses a function to process transcriptions.

  ## Example

      workflow = SimpleWorkflow.new(fn text ->
        ["You said: \#{text}"]
      end)

      pipeline = Pipeline.new(workflow: workflow)
  """

  @behaviour Codex.Voice.Workflow

  defstruct [:handler, :greeting]

  @type handler :: (String.t() -> Enumerable.t())

  @type t :: %__MODULE__{
          handler: handler(),
          greeting: String.t() | nil
        }

  @doc "Create a new simple workflow."
  @spec new(handler(), keyword()) :: t()
  def new(handler, opts \\ []) when is_function(handler, 1) do
    %__MODULE__{
      handler: handler,
      greeting: Keyword.get(opts, :greeting)
    }
  end

  @impl Codex.Voice.Workflow
  def run(%__MODULE__{handler: handler}, transcription) do
    handler.(transcription)
  end

  @impl Codex.Voice.Workflow
  def on_start(%__MODULE__{greeting: nil}), do: []
  def on_start(%__MODULE__{greeting: greeting}), do: [greeting]
end

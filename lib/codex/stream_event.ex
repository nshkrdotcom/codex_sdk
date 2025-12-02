defmodule Codex.StreamEvent.RunItem do
  @moduledoc """
  Semantic wrapper for a streamed Codex event.
  """

  @enforce_keys [:event]
  defstruct type: nil, event: nil

  @type t :: %__MODULE__{
          type: atom() | nil,
          event: Codex.Events.t()
        }
end

defmodule Codex.StreamEvent.AgentUpdated do
  @moduledoc """
  Signals that the agent or run configuration was updated for this stream.
  """

  defstruct agent: nil, run_config: nil

  @type t :: %__MODULE__{
          agent: Codex.Agent.t() | nil,
          run_config: Codex.RunConfig.t() | nil
        }
end

defmodule Codex.StreamEvent.RawResponses do
  @moduledoc """
  Batch of raw codex events emitted for a turn.
  """

  @enforce_keys [:events]
  defstruct events: [], usage: nil

  @type t :: %__MODULE__{
          events: [Codex.Events.t()],
          usage: map() | nil
        }
end

defmodule Codex.StreamEvent.GuardrailResult do
  @moduledoc """
  Guardrail evaluation outcome streamed to consumers.
  """

  @enforce_keys [:stage, :guardrail, :result]
  defstruct stage: nil, guardrail: nil, result: nil, message: nil

  @type stage :: :input | :output | :tool_input | :tool_output
  @type result :: :ok | :reject | :tripwire

  @type t :: %__MODULE__{
          stage: stage(),
          guardrail: String.t(),
          result: result(),
          message: String.t() | nil
        }
end

defmodule Codex.StreamEvent.ToolApproval do
  @moduledoc """
  Tool approval outcome emitted during streaming.
  """

  @enforce_keys [:tool_name, :decision]
  defstruct tool_name: nil, call_id: nil, decision: nil, reason: nil

  @type decision :: :allow | :deny | :pending

  @type t :: %__MODULE__{
          tool_name: String.t(),
          call_id: String.t() | nil,
          decision: decision(),
          reason: String.t() | nil
        }
end

defmodule Codex.Realtime.Model do
  @moduledoc """
  Behaviour for realtime model implementations.

  This behaviour defines the interface for connecting to a realtime model
  and sending/receiving events. Implementations can include WebSocket-based
  connections to OpenAI's Realtime API or mock implementations for testing.

  ## Implementing a Model

  To implement a custom realtime model, use this behaviour and implement
  all callbacks:

      defmodule MyCustomModel do
        @behaviour Codex.Realtime.Model

        @impl true
        def connect(config) do
          # Establish connection
          :ok
        end

        @impl true
        def add_listener(listener) do
          # Add event listener
          :ok
        end

        # ... implement other callbacks
      end

  ## Listeners

  Listeners can be either a pid or a function. When an event is received,
  it is forwarded to all registered listeners:

    * If the listener is a pid, the event is sent as `{:model_event, event}`
    * If the listener is a function, it is called with the event
  """

  alias Codex.Realtime.Config.ModelConfig
  alias Codex.Realtime.ModelEvents
  alias Codex.Realtime.ModelInputs

  @type listener :: pid() | (ModelEvents.t() -> :ok)

  @doc """
  Establish a connection to the model.

  Called when the session starts. The config contains API keys, URLs,
  and initial model settings.
  """
  @callback connect(config :: ModelConfig.t()) :: :ok | {:error, term()}

  @doc """
  Add a listener for model events.

  Listeners receive all events from the model connection.
  """
  @callback add_listener(listener()) :: :ok

  @doc """
  Remove a listener for model events.
  """
  @callback remove_listener(listener()) :: :ok

  @doc """
  Send an event to the model.

  Events include user input, audio data, tool outputs, and session updates.
  """
  @callback send_event(event :: ModelInputs.send_event()) :: :ok | {:error, term()}

  @doc """
  Close the model connection.

  Cleans up resources and closes any WebSocket connections.
  """
  @callback close() :: :ok
end

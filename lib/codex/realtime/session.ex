defmodule Codex.Realtime.Session do
  @moduledoc """
  Manages a realtime session with WebSocket connection.

  A `RealtimeSession` is a GenServer that manages the connection to OpenAI's
  Realtime API, handles event dispatch, tool execution, and conversation history.

  ## Usage

      # Define an agent
      agent = %Codex.Realtime.Agent{
        name: "Assistant",
        model: "gpt-4o-realtime-preview",
        instructions: "Be helpful and concise."
      }

      # Start the session
      {:ok, session} = Session.start_link(agent: agent)

      # Subscribe to events
      :ok = Session.subscribe(session, self())

      # Send a message
      :ok = Session.send_message(session, "Hello!")

      # Receive events
      receive do
        {:session_event, %Events.AgentStartEvent{}} ->
          IO.puts("Agent started!")

        {:session_event, %Events.AudioEvent{audio: audio}} ->
          # Handle audio data
      end

      # Close when done
      Session.close(session)

  ## Events

  Subscribers receive events as `{:session_event, event}` messages. See
  `Codex.Realtime.Events` for the full list of event types.

  ## Tool Execution

  When the model calls a tool, the session automatically executes it and
  sends the result back to the model. Tool events are emitted to subscribers.
  """

  use GenServer

  alias Codex.Realtime.Config
  alias Codex.Realtime.Config.ModelConfig
  alias Codex.Realtime.Config.SessionModelSettings
  alias Codex.Realtime.Events
  alias Codex.Realtime.Items
  alias Codex.Realtime.ModelEvents
  alias Codex.Realtime.ModelInputs
  alias Codex.Realtime.OpenAIWebSocket
  alias Codex.Realtime.PlaybackTracker

  require Logger

  defstruct [
    :agent,
    :websocket_pid,
    :websocket_module,
    :config,
    :run_config,
    :context,
    :playback_tracker,
    history: [],
    subscribers: %{},
    pending_tool_calls: %{},
    item_transcripts: %{},
    item_guardrail_run_counts: %{},
    interrupted_response_ids: MapSet.new()
  ]

  @type t :: %__MODULE__{
          agent: term(),
          websocket_pid: pid() | nil,
          websocket_module: module() | nil,
          config: ModelConfig.t(),
          run_config: Config.RunConfig.t(),
          context: map(),
          playback_tracker: PlaybackTracker.t(),
          history: [Items.item()],
          subscribers: %{optional(pid()) => reference()},
          pending_tool_calls: %{optional(pid()) => map()},
          item_transcripts: %{String.t() => String.t()},
          item_guardrail_run_counts: %{String.t() => non_neg_integer()},
          interrupted_response_ids: MapSet.t(String.t())
        }

  # Client API

  @doc """
  Start a realtime session.

  ## Options

    * `:agent` - Required. The realtime agent configuration.
    * `:config` - Optional model configuration (API key, URL, etc.).
    * `:run_config` - Optional runtime configuration.
    * `:context` - Optional context map passed to tools and events.
    * `:websocket_pid` - Optional. For testing with a mock WebSocket.
    * `:websocket_module` - Optional. Override the WebSocket module (default: WebSockex).

  ## Returns

    * `{:ok, pid}` on success
    * `{:error, reason}` on failure
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Subscribe to session events.

  The subscriber process will receive `{:session_event, event}` messages
  for all session events.
  """
  @spec subscribe(GenServer.server(), pid()) :: :ok
  def subscribe(session, subscriber_pid) do
    GenServer.call(session, {:subscribe, subscriber_pid})
  end

  @doc """
  Unsubscribe from session events.
  """
  @spec unsubscribe(GenServer.server(), pid()) :: :ok
  def unsubscribe(session, subscriber_pid) do
    GenServer.call(session, {:unsubscribe, subscriber_pid})
  end

  @doc """
  Send audio data to the model.

  ## Options

    * `:commit` - Whether to commit the audio buffer (default: false)

  ## Examples

      Session.send_audio(session, audio_bytes)
      Session.send_audio(session, audio_bytes, commit: true)
  """
  @spec send_audio(GenServer.server(), binary(), keyword()) :: :ok
  def send_audio(session, audio, opts \\ []) do
    commit = Keyword.get(opts, :commit, false)
    GenServer.call(session, {:send_audio, audio, commit})
  end

  @doc """
  Send a text message to the model.

  Can be a simple string or a structured message map.

  ## Examples

      Session.send_message(session, "Hello!")

      Session.send_message(session, %{
        "type" => "message",
        "role" => "user",
        "content" => [
          %{"type" => "input_text", "text" => "Hello!"},
          %{"type" => "input_image", "image_url" => "data:image/..."}
        ]
      })
  """
  @spec send_message(GenServer.server(), String.t() | map()) :: :ok
  def send_message(session, message) do
    GenServer.call(session, {:send_message, message})
  end

  @doc """
  Interrupt the current response.

  Sends a cancel signal to stop the model from generating more output.
  """
  @spec interrupt(GenServer.server()) :: :ok
  def interrupt(session) do
    GenServer.call(session, :interrupt)
  end

  @doc """
  Send a raw event to the model.

  Use this for advanced scenarios where you need to send custom events.
  """
  @spec send_raw_event(GenServer.server(), map()) :: :ok
  def send_raw_event(session, event) do
    GenServer.call(session, {:send_raw_event, event})
  end

  @doc """
  Update session settings.

  Use this to change model settings mid-session, such as voice or modalities.
  """
  @spec update_session(GenServer.server(), SessionModelSettings.t()) :: :ok
  def update_session(session, settings) do
    GenServer.call(session, {:update_session, settings})
  end

  @doc """
  Get the conversation history.
  """
  @spec history(GenServer.server()) :: [Items.item()]
  def history(session) do
    GenServer.call(session, :history)
  end

  @doc """
  Get the current agent.
  """
  @spec current_agent(GenServer.server()) :: term()
  def current_agent(session) do
    GenServer.call(session, :current_agent)
  end

  @doc """
  Close the session.

  Closes the WebSocket connection and stops the session process.
  """
  @spec close(GenServer.server()) :: :ok
  def close(session) do
    GenServer.stop(session, :normal)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    agent = Keyword.fetch!(opts, :agent)
    config = Keyword.get(opts, :config, %ModelConfig{})
    run_config = Keyword.get(opts, :run_config, %Config.RunConfig{})
    context = Keyword.get(opts, :context, %{})

    # Support for testing with mock WebSocket
    websocket_pid = Keyword.get(opts, :websocket_pid)
    websocket_module = Keyword.get(opts, :websocket_module)

    state = %__MODULE__{
      agent: agent,
      config: config,
      run_config: run_config,
      context: context,
      playback_tracker: PlaybackTracker.new(),
      websocket_pid: websocket_pid,
      websocket_module: websocket_module
    }

    if websocket_pid do
      {:ok, state}
    else
      {:ok, state, {:continue, :connect_websocket}}
    end
  end

  @impl true
  def handle_continue(:connect_websocket, state) do
    case start_websocket(state) do
      {:ok, ws_pid} ->
        {:noreply, %{state | websocket_pid: ws_pid}}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    case Map.fetch(state.subscribers, pid) do
      {:ok, _ref} ->
        {:reply, :ok, state}

      :error ->
        ref = Process.monitor(pid)
        {:reply, :ok, %{state | subscribers: Map.put(state.subscribers, pid, ref)}}
    end
  end

  def handle_call({:unsubscribe, pid}, _from, state) do
    case Map.pop(state.subscribers, pid) do
      {nil, _subscribers} ->
        {:reply, :ok, state}

      {ref, subscribers} ->
        Process.demonitor(ref, [:flush])
        {:reply, :ok, %{state | subscribers: subscribers}}
    end
  end

  def handle_call({:send_audio, audio, commit}, _from, state) do
    send_to_websocket(state, ModelInputs.send_audio(audio, commit))
    {:reply, :ok, state}
  end

  def handle_call({:send_message, message}, _from, state) do
    send_to_websocket(state, ModelInputs.send_user_input(message))
    # Also trigger response
    send_to_websocket(state, ModelInputs.send_raw_message(%{"type" => "response.create"}))
    {:reply, :ok, state}
  end

  def handle_call(:interrupt, _from, state) do
    send_to_websocket(state, ModelInputs.send_interrupt())
    state = %{state | playback_tracker: PlaybackTracker.on_interrupted(state.playback_tracker)}
    {:reply, :ok, state}
  end

  def handle_call({:send_raw_event, event}, _from, state) do
    send_to_websocket(state, ModelInputs.send_raw_message(event))
    {:reply, :ok, state}
  end

  def handle_call({:update_session, settings}, _from, state) do
    send_to_websocket(state, ModelInputs.send_session_update(settings))
    {:reply, :ok, state}
  end

  def handle_call(:history, _from, state) do
    {:reply, state.history, state}
  end

  def handle_call(:current_agent, _from, state) do
    {:reply, state.agent, state}
  end

  @impl true
  def handle_info({:model_event, event}, state) do
    state = handle_model_event(event, state)
    {:noreply, state}
  end

  def handle_info({:websocket_event, json}, state) do
    case ModelEvents.from_json(json) do
      {:ok, event} ->
        state = handle_model_event(event, state)
        {:noreply, state}

      {:error, _} ->
        {:noreply, state}
    end
  end

  def handle_info({:EXIT, pid, reason}, %{websocket_pid: pid} = state) do
    event =
      Events.error(
        %{"type" => "websocket_exit", "reason" => format_reason(reason)},
        state.context
      )

    notify_subscribers(state, event)
    {:noreply, %{state | websocket_pid: nil}}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info({:tool_call_result, pid, output}, state) when is_pid(pid) do
    case Map.pop(state.pending_tool_calls, pid) do
      {nil, _pending} ->
        {:noreply, state}

      {pending_tool_call, pending} ->
        Process.demonitor(pending_tool_call.monitor_ref, [:flush])
        state = %{state | pending_tool_calls: pending}
        state = finish_tool_call(state, pending_tool_call, output)
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case pop_subscriber_by_ref(state.subscribers, pid, ref) do
      {:ok, subscribers} ->
        {:noreply, %{state | subscribers: subscribers}}

      :error ->
        handle_tool_call_down(state, ref, pid, reason)
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    _ = drain_pending_tool_calls(state)

    if state.websocket_pid do
      ws_module = state.websocket_module || WebSockex

      try do
        ws_module.send_frame(state.websocket_pid, :close)
      rescue
        _ -> :ok
      catch
        :exit, _ -> :ok
      end
    end

    :ok
  end

  # Private Functions

  defp start_websocket(state) do
    model_name = get_model_name(state.agent)

    OpenAIWebSocket.start_link(
      session_pid: self(),
      config: state.config,
      model_name: model_name
    )
  end

  defp get_model_name(%{model: model}) when is_binary(model), do: model
  defp get_model_name(_), do: "gpt-4o-realtime-preview"

  defp send_to_websocket(state, input) do
    if state.websocket_pid do
      json = ModelInputs.to_json(input)
      ws_module = state.websocket_module || WebSockex
      do_send_to_websocket(ws_module, state.websocket_pid, json)
    end
  end

  defp do_send_to_websocket(ws_module, pid, msgs) when is_list(msgs) do
    Enum.each(msgs, &do_send_to_websocket(ws_module, pid, &1))
  end

  defp do_send_to_websocket(ws_module, pid, msg) when is_map(msg) do
    ws_module.send_frame(pid, {:text, Jason.encode!(msg)})
  end

  # Event Handlers

  defp handle_model_event(%ModelEvents.ConnectionStatusEvent{status: :connected}, state) do
    # Send initial session configuration
    send_initial_config(state)
    event = Events.agent_start(state.agent, state.context)
    notify_subscribers(state, event)
    state
  end

  defp handle_model_event(%ModelEvents.ItemUpdatedEvent{item: item}, state) do
    # Check if this is a new item or an update
    is_new = not Enum.any?(state.history, &(&1.item_id == item.item_id))

    # Update history
    history = update_history(state.history, item)

    if is_new do
      event = Events.history_added(item, state.context)
      notify_subscribers(state, event)
    else
      event = Events.history_updated(history, state.context)
      notify_subscribers(state, event)
    end

    %{state | history: history}
  end

  defp handle_model_event(%ModelEvents.ItemDeletedEvent{item_id: item_id}, state) do
    history = Enum.reject(state.history, &(&1.item_id == item_id))
    event = Events.history_updated(history, state.context)
    notify_subscribers(state, event)
    %{state | history: history}
  end

  defp handle_model_event(%ModelEvents.AudioEvent{} = audio, state) do
    event = Events.audio(audio, audio.item_id, audio.content_index, state.context)
    notify_subscribers(state, event)
    state
  end

  defp handle_model_event(%ModelEvents.AudioDoneEvent{} = done, state) do
    event = Events.audio_end(done.item_id, done.content_index, state.context)
    notify_subscribers(state, event)
    state
  end

  defp handle_model_event(%ModelEvents.AudioInterruptedEvent{} = interrupted, state) do
    event =
      Events.audio_interrupted(interrupted.item_id, interrupted.content_index, state.context)

    notify_subscribers(state, event)
    %{state | playback_tracker: PlaybackTracker.on_interrupted(state.playback_tracker)}
  end

  defp handle_model_event(%ModelEvents.ToolCallEvent{} = tool_call, state) do
    execute_tool_call(tool_call, state)
  end

  defp handle_model_event(%ModelEvents.TranscriptDeltaEvent{} = delta, state) do
    # Accumulate transcript for guardrail debouncing
    item_id = delta.item_id
    current_transcript = Map.get(state.item_transcripts, item_id, "")
    new_transcript = current_transcript <> delta.delta

    item_transcripts = Map.put(state.item_transcripts, item_id, new_transcript)
    state = %{state | item_transcripts: item_transcripts}

    # Update history with transcript
    content = [Items.assistant_audio(nil, new_transcript)]

    item =
      Items.assistant_message(item_id, content, status: :in_progress)

    history = update_history(state.history, item)
    %{state | history: history}
  end

  defp handle_model_event(%ModelEvents.TurnStartedEvent{}, state) do
    event = Events.agent_start(state.agent, state.context)
    notify_subscribers(state, event)
    state
  end

  defp handle_model_event(%ModelEvents.TurnEndedEvent{}, state) do
    # Clear guardrail state for next turn
    event = Events.agent_end(state.agent, state.context)
    notify_subscribers(state, event)

    %{state | item_transcripts: %{}, item_guardrail_run_counts: %{}}
  end

  defp handle_model_event(%ModelEvents.ErrorEvent{error: error}, state) do
    event = Events.error(error, state.context)
    notify_subscribers(state, event)
    state
  end

  defp handle_model_event(%ModelEvents.InputAudioTranscriptionCompletedEvent{} = tc, state) do
    # Update history with completed transcription
    history = update_history_with_transcription(state.history, tc.item_id, tc.transcript)
    %{state | history: history}
  end

  defp handle_model_event(%ModelEvents.InputAudioTimeoutTriggeredEvent{}, state) do
    event = Events.input_audio_timeout_triggered(state.context)
    notify_subscribers(state, event)
    state
  end

  defp handle_model_event(event, state) do
    # Wrap other events as raw model events
    wrapped = Events.raw_model_event(event, state.context)
    notify_subscribers(state, wrapped)
    state
  end

  defp send_initial_config(state) do
    # Resolve instructions
    instructions = resolve_instructions(state.agent, state.context)

    settings = %SessionModelSettings{
      model_name: get_model_name(state.agent),
      instructions: instructions,
      tools: get_agent_tools(state.agent),
      modalities: [:text, :audio],
      input_audio_format: :pcm16,
      output_audio_format: :pcm16
    }

    # Merge with run_config settings
    settings =
      case state.run_config.model_settings do
        nil -> settings
        override -> Config.merge_settings(settings, override)
      end

    send_to_websocket(state, ModelInputs.send_session_update(settings))
  end

  defp resolve_instructions(%{instructions: instructions}, _context)
       when is_binary(instructions) do
    instructions
  end

  defp resolve_instructions(%{instructions: instructions}, context)
       when is_function(instructions, 1) do
    instructions.(context)
  end

  defp resolve_instructions(_, _), do: ""

  defp get_agent_tools(%{tools: tools}) when is_list(tools), do: tools
  defp get_agent_tools(_), do: []

  defp update_history(history, item) do
    case Enum.find_index(history, &(&1.item_id == item.item_id)) do
      nil -> history ++ [item]
      idx -> List.replace_at(history, idx, item)
    end
  end

  defp update_history_with_transcription(history, item_id, transcript) do
    Enum.map(history, fn item ->
      if item.item_id == item_id do
        update_item_transcript(item, transcript)
      else
        item
      end
    end)
  end

  defp update_item_transcript(%Items.UserMessageItem{content: content} = item, transcript) do
    updated_content =
      Enum.map(content, fn
        %Items.InputAudio{} = audio -> %{audio | transcript: transcript}
        other -> other
      end)

    %{item | content: updated_content}
  end

  defp update_item_transcript(item, _transcript), do: item

  defp execute_tool_call(tool_call, state) do
    tools = get_agent_tools(state.agent)
    tool = find_tool(tools, tool_call.name)

    event = Events.tool_start(state.agent, tool, tool_call.arguments, state.context)
    notify_subscribers(state, event)

    {:ok, pid} =
      start_tool_task(fn ->
        resolve_tool_output(tool, tool_call, state.context)
      end)

    monitor_ref = Process.monitor(pid)

    pending_tool_call = %{
      pid: pid,
      monitor_ref: monitor_ref,
      tool_call: tool_call,
      tool: tool
    }

    %{state | pending_tool_calls: Map.put(state.pending_tool_calls, pid, pending_tool_call)}
  end

  defp resolve_tool_output(nil, tool_call, _context) do
    "Error: Unknown tool #{tool_call.name}"
  end

  defp resolve_tool_output(tool, tool_call, context) do
    execute_tool(tool, tool_call.arguments, context)
  end

  defp finish_tool_call(state, pending_tool_call, output) do
    event =
      Events.tool_end(
        state.agent,
        pending_tool_call.tool,
        pending_tool_call.tool_call.arguments,
        output,
        state.context
      )

    notify_subscribers(state, event)

    send_to_websocket(
      state,
      ModelInputs.send_tool_output(pending_tool_call.tool_call, output, true)
    )

    state
  end

  defp handle_tool_call_down(state, ref, pid, :normal) do
    case Map.pop(state.pending_tool_calls, pid) do
      {nil, _pending} ->
        {:noreply, state}

      {%{monitor_ref: ^ref}, pending} ->
        {:noreply, %{state | pending_tool_calls: pending}}

      {pending_tool_call, pending} ->
        Process.demonitor(pending_tool_call.monitor_ref, [:flush])
        {:noreply, %{state | pending_tool_calls: pending}}
    end
  end

  defp handle_tool_call_down(state, ref, pid, reason) do
    case Map.pop(state.pending_tool_calls, pid) do
      {nil, _pending} ->
        {:noreply, state}

      {%{monitor_ref: ^ref} = pending_tool_call, pending} ->
        state = %{state | pending_tool_calls: pending}
        output = "Error: Tool execution failed - #{format_reason(reason)}"
        state = finish_tool_call(state, pending_tool_call, output)
        {:noreply, state}

      {pending_tool_call, pending} ->
        Process.demonitor(pending_tool_call.monitor_ref, [:flush])
        state = %{state | pending_tool_calls: pending}
        output = "Error: Tool execution failed - #{format_reason(reason)}"
        state = finish_tool_call(state, pending_tool_call, output)
        {:noreply, state}
    end
  end

  defp drain_pending_tool_calls(state) do
    Enum.each(state.pending_tool_calls, fn
      {pid, %{monitor_ref: monitor_ref}} ->
        Process.demonitor(monitor_ref, [:flush])

        if is_pid(pid) and Process.alive?(pid) do
          Process.exit(pid, :shutdown)
        end

      {_pid, _pending_tool_call} ->
        :ok
    end)

    :ok
  end

  @spec start_tool_task((-> any())) :: {:ok, pid()}
  defp start_tool_task(fun) do
    parent = self()

    runner = fn ->
      output = fun.()
      send(parent, {:tool_call_result, self(), output})
    end

    try do
      case Task.Supervisor.start_child(Codex.TaskSupervisor, runner) do
        {:ok, pid} -> {:ok, pid}
        {:error, {:already_started, pid}} -> {:ok, pid}
        {:error, _} -> Task.start_link(runner)
      end
    catch
      :exit, _ -> Task.start_link(runner)
    end
  end

  defp find_tool(tools, name) do
    Enum.find(tools, fn tool ->
      case tool do
        %{name: ^name} -> true
        %{"name" => ^name} -> true
        _ -> false
      end
    end)
  end

  defp execute_tool(tool, arguments_json, context) do
    case Jason.decode(arguments_json) do
      {:ok, args} ->
        try do
          result = invoke_tool(tool, args, context)
          to_string(result)
        rescue
          e ->
            "Error: #{Exception.message(e)}"
        end

      {:error, reason} ->
        "Error: Invalid JSON arguments - #{inspect(reason)}"
    end
  end

  defp invoke_tool(%{on_invoke: fun}, args, context) when is_function(fun, 2) do
    fun.(args, context)
  end

  defp invoke_tool(%{on_invoke: fun}, args, _context) when is_function(fun, 1) do
    fun.(args)
  end

  defp invoke_tool(%{execute: fun}, args, context) when is_function(fun, 2) do
    fun.(args, context)
  end

  defp invoke_tool(%{execute: fun}, args, _context) when is_function(fun, 1) do
    fun.(args)
  end

  defp invoke_tool(%{handler: fun}, args, context) when is_function(fun, 2) do
    fun.(args, context)
  end

  defp invoke_tool(%{handler: fun}, args, _context) when is_function(fun, 1) do
    fun.(args)
  end

  defp invoke_tool(_tool, _args, _context) do
    "Error: Tool has no invokable function"
  end

  defp notify_subscribers(state, event) do
    Enum.each(Map.keys(state.subscribers), fn pid ->
      send(pid, {:session_event, event})
    end)
  end

  defp pop_subscriber_by_ref(subscribers, pid, ref) do
    case Map.get(subscribers, pid) do
      ^ref -> {:ok, Map.delete(subscribers, pid)}
      _ -> :error
    end
  end

  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)
end

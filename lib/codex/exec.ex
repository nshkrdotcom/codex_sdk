defmodule Codex.Exec do
  @moduledoc """
  Process manager wrapping the `codex` binary via the shared CLI subprocess core.

  This module is the implementation behind Codex's historical `:exec`
  compatibility selector. That selector names the default core-backed exec JSONL
  lane; it does not imply direct ownership of the Erlang `:exec` worker.

  Provides blocking and streaming helpers that project core session events into
  typed `%Codex.Events{}` structs.
  """

  require Logger

  alias CliSubprocessCore.Event, as: CoreEvent
  alias CliSubprocessCore.TransportError, as: CoreTransportError
  alias Codex.Config.Defaults
  alias Codex.Exec.CancellationRegistry
  alias Codex.Exec.Options, as: ExecOptions
  alias Codex.Files.Attachment
  alias Codex.Runtime.Exec, as: RuntimeExec
  alias Codex.TransportError

  @type exec_opts :: %{
          optional(:codex_opts) => Codex.Options.t(),
          optional(:thread) => Codex.Thread.t(),
          optional(:turn_opts) => map(),
          optional(:continuation_token) => String.t(),
          optional(:attachments) => [Attachment.t()],
          optional(:output_schema_path) => String.t(),
          optional(:tool_outputs) => [map()],
          optional(:tool_failures) => [map()],
          optional(:env) => map(),
          optional(:clear_env?) => boolean(),
          optional(:cancellation_token) => String.t(),
          optional(:timeout_ms) => pos_integer(),
          optional(:max_stderr_buffer_bytes) => pos_integer()
        }

  @doc """
  Runs codex in blocking mode and accumulates all emitted events.
  """
  @spec run(String.t(), exec_opts()) :: {:ok, map()} | {:error, term()}
  def run(input, opts) when is_binary(input) do
    with {:ok, exec_opts} <- ExecOptions.new(opts),
         {:ok, state} <- start_session(exec_opts, input) do
      collect_events(state)
    end
  end

  @doc """
  Runs `codex exec review` and accumulates all emitted events.
  """
  @spec review(term(), exec_opts()) :: {:ok, map()} | {:error, term()}
  def review(target, opts) do
    with {:ok, exec_opts} <- ExecOptions.new(opts),
         {:ok, command_args} <- review_args(target),
         {:ok, state} <- start_session(exec_opts, nil, command_args) do
      collect_events(state)
    end
  end

  @doc """
  Returns a lazy stream of events. The underlying process starts on first
  enumeration and stops automatically when the stream halts.
  """
  @spec run_stream(String.t(), exec_opts()) :: {:ok, Enumerable.t()} | {:error, term()}
  def run_stream(input, opts) when is_binary(input) do
    with {:ok, exec_opts} <- ExecOptions.new(opts) do
      starter = fn -> start_session(exec_opts, input) end
      {:ok, build_stream(starter)}
    end
  end

  @doc """
  Returns a lazy stream of events for `codex exec review`.
  """
  @spec review_stream(term(), exec_opts()) :: {:ok, Enumerable.t()} | {:error, term()}
  def review_stream(target, opts) do
    with {:ok, exec_opts} <- ExecOptions.new(opts),
         {:ok, command_args} <- review_args(target) do
      starter = fn -> start_session(exec_opts, nil, command_args) end
      {:ok, build_stream(starter)}
    end
  end

  @doc """
  Cancels any in-flight exec sessions associated with the provided cancellation token.
  """
  @spec cancel(String.t()) :: :ok
  def cancel(token) when is_binary(token) and token != "" do
    token
    |> sessions_for_token()
    |> Enum.each(fn session ->
      _ = RuntimeExec.interrupt(session)
      _ = RuntimeExec.close(session)
    end)

    :ok
  end

  def cancel(_token), do: :ok

  defp start_session(%ExecOptions{} = exec_opts, input, command_args \\ nil) do
    session_ref = make_ref()

    with {:ok, session, info} <-
           RuntimeExec.start_session(
             exec_opts: exec_opts,
             input: input,
             command_args: command_args,
             subscriber: {self(), session_ref}
           ) do
      state = %{
        session: session,
        session_ref: session_ref,
        session_monitor_ref: Process.monitor(session),
        exec_opts: exec_opts,
        projection_state: %{exec_opts: exec_opts},
        stderr: "",
        stderr_truncated?: false,
        max_stderr_buffer_bytes: resolve_max_stderr_buffer_bytes(exec_opts),
        timeout_ms: resolve_timeout_ms(exec_opts),
        idle_timeout_ms: resolve_idle_timeout_ms(exec_opts),
        cancellation_token: exec_opts.cancellation_token,
        session_event_tag: Map.get(info, :session_event_tag, RuntimeExec.session_event_tag())
      }

      :ok = maybe_register_cancellation(state.cancellation_token, session)
      {:ok, state}
    end
  end

  defp collect_events(state), do: do_collect(state, [])

  defp do_collect(%{timeout_ms: timeout_ms} = state, events) do
    receive do
      {event_tag, ref, {:event, %CoreEvent{} = event}}
      when event_tag == state.session_event_tag and ref == state.session_ref ->
        state = capture_stderr(state, event)
        log_transport_error(event, :collect)

        case RuntimeExec.session_error(event, state.stderr, state.stderr_truncated?) do
          {:error, %TransportError{} = error} ->
            safe_stop(state)
            {:error, error}

          nil ->
            {projected, projection_state} =
              RuntimeExec.project_event(event, state.projection_state)

            do_collect(%{state | projection_state: projection_state}, events ++ projected)
        end

      {:DOWN, ref, :process, pid, _reason}
      when ref == state.session_monitor_ref and pid == state.session ->
        maybe_unregister_cancellation(state)
        {:ok, %{events: events}}
    after
      timeout_ms ->
        Logger.warning("codex exec timed out after #{timeout_ms}ms without output")
        safe_stop(state)
        {:error, {:codex_timeout, timeout_ms}}
    end
  end

  defp build_stream(starter) when is_function(starter, 0) do
    Stream.resource(
      starter,
      &next_stream_chunk_safe/1,
      &safe_stop/1
    )
  end

  defp next_stream_chunk_safe({:error, reason}) do
    raise TransportError.new(-1,
            message: "failed to start codex exec stream",
            stderr: inspect(reason)
          )
  end

  defp next_stream_chunk_safe({:ok, state}), do: next_stream_chunk(state)
  defp next_stream_chunk_safe(state), do: next_stream_chunk(state)

  defp next_stream_chunk(%{idle_timeout_ms: idle_timeout_ms} = state) do
    timeout = idle_timeout_ms || :infinity

    receive do
      {event_tag, ref, {:event, %CoreEvent{} = event}}
      when event_tag == state.session_event_tag and ref == state.session_ref ->
        state = capture_stderr(state, event)
        log_transport_error(event, :stream)

        case RuntimeExec.session_error(event, state.stderr, state.stderr_truncated?) do
          {:error, %TransportError{} = error} ->
            maybe_unregister_cancellation(state)
            raise error

          nil ->
            {projected, projection_state} =
              RuntimeExec.project_event(event, state.projection_state)

            {projected, %{state | projection_state: projection_state}}
        end

      {:DOWN, ref, :process, pid, _reason}
      when ref == state.session_monitor_ref and pid == state.session ->
        maybe_unregister_cancellation(state)
        {:halt, state}
    after
      timeout ->
        raise handle_stream_idle_timeout(state, idle_timeout_ms)
    end
  end

  defp handle_stream_idle_timeout(state, timeout_ms) do
    Logger.warning("codex exec stream idle timeout after #{timeout_ms}ms without output")
    safe_stop(state)

    TransportError.new(-1,
      message: "codex exec stream idle timeout after #{timeout_ms}ms",
      retryable?: true
    )
  end

  defp capture_stderr(state, event) do
    case RuntimeExec.stderr_chunk(event) do
      data when is_binary(data) ->
        {stderr, truncated?} =
          append_stderr(
            state.stderr,
            data,
            state.max_stderr_buffer_bytes,
            state.stderr_truncated?
          )

        %{state | stderr: stderr, stderr_truncated?: truncated?}

      _other ->
        state
    end
  end

  defp log_transport_error(%CoreEvent{raw: error}, phase) do
    if CoreTransportError.match?(error) do
      Logger.warning(
        "Transport error during #{phase}: #{inspect(CoreTransportError.reason(error))}"
      )
    end
  end

  defp safe_stop({:error, _reason}), do: :ok
  defp safe_stop({:ok, state}), do: safe_stop(state)

  defp safe_stop(%{session: nil} = state) do
    maybe_unregister_cancellation(state)
    :ok
  end

  defp safe_stop(%{session: session, session_ref: session_ref} = state) when is_pid(session) do
    maybe_unregister_cancellation(state)
    _ = RuntimeExec.close(session)
    maybe_await_session_down(state.session_monitor_ref, session)
    flush_session_messages(session_ref, state.session_event_tag)
    :ok
  rescue
    _ -> :ok
  end

  defp resolve_timeout_ms(%ExecOptions{timeout_ms: nil}), do: Defaults.exec_timeout_ms()
  defp resolve_timeout_ms(%ExecOptions{timeout_ms: timeout_ms}), do: timeout_ms

  defp resolve_idle_timeout_ms(%ExecOptions{stream_idle_timeout_ms: nil}), do: nil

  defp resolve_idle_timeout_ms(%ExecOptions{stream_idle_timeout_ms: timeout_ms})
       when is_integer(timeout_ms) and timeout_ms > 0 do
    timeout_ms
  end

  defp resolve_idle_timeout_ms(_), do: nil

  defp resolve_max_stderr_buffer_bytes(%ExecOptions{max_stderr_buffer_bytes: nil}) do
    Defaults.transport_max_stderr_buffer_size()
  end

  defp resolve_max_stderr_buffer_bytes(%ExecOptions{max_stderr_buffer_bytes: max_bytes})
       when is_integer(max_bytes) and max_bytes > 0 do
    max_bytes
  end

  defp resolve_max_stderr_buffer_bytes(_), do: Defaults.transport_max_stderr_buffer_size()

  defp append_stderr(_existing, _data, max_size, _already_truncated?)
       when not is_integer(max_size) or max_size <= 0,
       do: {"", true}

  defp append_stderr(existing, data, max_size, already_truncated?) do
    combined = existing <> data
    combined_size = byte_size(combined)

    if combined_size <= max_size do
      {combined, already_truncated?}
    else
      {:binary.part(combined, combined_size - max_size, max_size), true}
    end
  end

  defp await_session_down_or_demonitor(ref, session)
       when is_reference(ref) and is_pid(session) do
    receive do
      {:DOWN, ^ref, :process, ^session, _reason} ->
        :ok
    after
      Defaults.transport_close_grace_ms() ->
        Process.exit(session, :kill)
        Process.demonitor(ref, [:flush])
        :ok
    end
  end

  defp await_session_down_or_demonitor(_ref, _session), do: :ok

  defp maybe_await_session_down(ref, session)
       when is_reference(ref) and is_pid(session) do
    if Process.alive?(session) do
      await_session_down_or_demonitor(ref, session)
    else
      Process.demonitor(ref, [:flush])
      :ok
    end
  end

  defp maybe_await_session_down(_ref, _session), do: :ok

  defp flush_session_messages(ref, session_event_tag)
       when is_reference(ref) and is_atom(session_event_tag) do
    receive do
      {event_tag, ^ref, {:event, _event}} when event_tag == session_event_tag ->
        flush_session_messages(ref, session_event_tag)
    after
      0 ->
        :ok
    end
  end

  defp flush_session_messages(_ref, _session_event_tag), do: :ok

  defp maybe_register_cancellation(token, session)
       when is_binary(token) and token != "" and is_pid(session) do
    CancellationRegistry.register(token, session)
  end

  defp maybe_register_cancellation(_token, _session), do: :ok

  defp maybe_unregister_cancellation(%{cancellation_token: token, session: session}) do
    maybe_unregister_cancellation(token, session)
  end

  defp maybe_unregister_cancellation(%{cancellation_token: token}) do
    maybe_unregister_cancellation(token, nil)
  end

  defp maybe_unregister_cancellation(_state), do: :ok

  defp maybe_unregister_cancellation(token, session) when is_binary(token) and token != "" do
    CancellationRegistry.unregister(token, session)
  end

  defp maybe_unregister_cancellation(_token, _session), do: :ok

  defp sessions_for_token(token) do
    CancellationRegistry.transports_for_token(token)
  end

  defp review_args(:uncommitted_changes), do: {:ok, ["review", "--uncommitted"]}
  defp review_args({:uncommitted_changes}), do: {:ok, ["review", "--uncommitted"]}

  defp review_args({:base_branch, branch}) when is_binary(branch) and branch != "" do
    {:ok, ["review", "--base", branch]}
  end

  defp review_args({:commit, sha}) when is_binary(sha) and sha != "" do
    {:ok, ["review", "--commit", sha]}
  end

  defp review_args({:commit, sha, title}) when is_binary(sha) and sha != "" do
    args =
      ["review", "--commit", sha]
      |> maybe_append_title(title)

    {:ok, args}
  end

  defp review_args({:custom, instructions}) when is_binary(instructions) do
    instructions = String.trim(instructions)

    if instructions == "" do
      {:error, {:invalid_review_target, instructions}}
    else
      {:ok, ["review", instructions]}
    end
  end

  defp review_args(instructions) when is_binary(instructions) do
    review_args({:custom, instructions})
  end

  defp review_args(other), do: {:error, {:invalid_review_target, other}}

  defp maybe_append_title(args, title) when is_binary(title) and title != "" do
    args ++ ["--title", title]
  end

  defp maybe_append_title(args, _title), do: args
end

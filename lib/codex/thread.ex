defmodule Codex.Thread do
  @moduledoc """
  Represents a Codex conversation thread and exposes turn execution APIs.
  """

  alias Codex.Options
  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.Turn.Result

  @enforce_keys [:codex_opts, :thread_opts]
  defstruct thread_id: nil,
            codex_opts: nil,
            thread_opts: nil,
            metadata: %{},
            labels: %{}

  @type t :: %__MODULE__{
          thread_id: String.t() | nil,
          codex_opts: Options.t(),
          thread_opts: ThreadOptions.t(),
          metadata: map(),
          labels: map()
        }

  @doc false
  @spec build(Options.t(), ThreadOptions.t(), keyword()) :: t()
  def build(%Options{} = opts, %ThreadOptions{} = thread_opts, extra \\ []) do
    struct!(
      __MODULE__,
      Keyword.merge(
        [
          thread_id: nil,
          codex_opts: opts,
          thread_opts: thread_opts,
          metadata: %{},
          labels: %{}
        ],
        extra
      )
    )
  end

  @doc """
  Executes a blocking turn against the codex engine.
  """
  @spec run(t(), String.t(), map() | keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def run(%__MODULE__{} = thread, input, turn_opts \\ %{}) when is_binary(input) do
    with {:ok, exec_opts} <- build_exec_options(thread, turn_opts),
         {:ok, exec_result} <- Codex.Exec.run(input, exec_opts) do
      {:ok, finalize_turn(thread, exec_result)}
    end
  end

  @doc """
  Executes a turn and returns a stream of events for progressive consumption.

  The stream is lazy; events will not be produced until enumerated.
  """
  @spec run_streamed(t(), String.t(), map() | keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def run_streamed(%__MODULE__{} = thread, input, turn_opts \\ %{}) when is_binary(input) do
    with {:ok, exec_opts} <- build_exec_options(thread, turn_opts) do
      {:ok, Codex.Exec.run_stream(input, exec_opts)}
    end
  end

  defp build_exec_options(thread, turn_opts) do
    {:ok,
     Map.merge(
       %{
         codex_opts: thread.codex_opts,
         thread: thread,
         turn_opts: Map.new(turn_opts)
       },
       %{}
     )}
  end

  defp finalize_turn(thread, %{events: events} = exec_result) do
    {updated_thread, final_response, usage} = fold_events(thread, events)

    %Result{
      thread: updated_thread,
      events: events,
      final_response: final_response,
      usage: usage,
      raw: exec_result
    }
  end

  defp fold_events(thread, events) do
    Enum.reduce(events, {thread, nil, nil}, fn event, {acc_thread, response, usage} ->
      case event["type"] do
        "thread.started" ->
          thread_id = event["thread_id"] || acc_thread.thread_id
          metadata = event["metadata"] || %{}
          labels = get_in(metadata, ["labels"]) || acc_thread.labels

          updated =
            acc_thread
            |> Map.put(:thread_id, thread_id)
            |> Map.put(:metadata, metadata)
            |> Map.put(:labels, labels)

          {updated, response, usage}

        "turn.completed" ->
          {acc_thread, event["final_response"] || response, event["usage"] || usage}

        _ ->
          {acc_thread, response, usage}
      end
    end)
  end
end

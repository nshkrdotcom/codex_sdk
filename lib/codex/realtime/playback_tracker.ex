defmodule Codex.Realtime.PlaybackTracker do
  @moduledoc """
  Tracks audio playback progress for handling interruptions.

  When you have custom playback logic or expect audio to be played with delays
  or at different speeds, use this tracker to inform the model about the actual
  playback state. This is important for proper interruption handling.

  ## Usage

      tracker = PlaybackTracker.new()
      |> PlaybackTracker.set_audio_format(:pcm16)
      |> PlaybackTracker.on_play_bytes("item_123", 0, audio_data)

      state = PlaybackTracker.get_state(tracker)
      # %{current_item_id: "item_123", current_item_content_index: 0, elapsed_ms: 500.0}

  ## Why This Matters

  The model generates audio much faster than realtime playback speed. If there's
  an interruption, the model needs to know how much audio has actually been
  played to the user. In low-latency scenarios, assuming immediate playback is
  fine. In scenarios like phone calls or remote interactions, use this tracker
  to provide accurate playback state.
  """

  alias Codex.Realtime.Audio

  defstruct [:format, :current_item, :elapsed_ms]

  @type t :: %__MODULE__{
          format: Audio.format() | nil,
          current_item: {String.t(), non_neg_integer()} | nil,
          elapsed_ms: float() | nil
        }

  @doc """
  Create a new playback tracker.

  ## Examples

      iex> tracker = Codex.Realtime.PlaybackTracker.new()
      iex> tracker.format
      nil
  """
  @spec new() :: %__MODULE__{format: nil, current_item: nil, elapsed_ms: nil}
  def new, do: %__MODULE__{}

  @doc """
  Record audio bytes that have been played.

  This calculates the duration in milliseconds based on the audio format
  and calls `on_play_ms/4`.

  ## Parameters

    * `tracker` - The playback tracker
    * `item_id` - The item ID of the audio being played
    * `content_index` - The index of the audio content in `item.content`
    * `bytes` - The audio bytes that have been fully played

  ## Examples

      tracker = PlaybackTracker.new()
      |> PlaybackTracker.set_audio_format(:pcm16)
      |> PlaybackTracker.on_play_bytes("item_123", 0, audio_data)
  """
  @spec on_play_bytes(t(), String.t(), non_neg_integer(), binary()) :: t()
  def on_play_bytes(%__MODULE__{format: format} = tracker, item_id, content_index, bytes) do
    ms = Audio.calculate_audio_length_ms(format || :pcm16, bytes)
    on_play_ms(tracker, item_id, content_index, ms)
  end

  @doc """
  Record milliseconds of audio that have been played.

  If the item/content changes, the elapsed time is reset. Otherwise,
  the elapsed time is accumulated.

  ## Parameters

    * `tracker` - The playback tracker
    * `item_id` - The item ID of the audio being played
    * `content_index` - The index of the audio content in `item.content`
    * `ms` - The number of milliseconds of audio that have been played

  ## Examples

      tracker = PlaybackTracker.new()
      |> PlaybackTracker.on_play_ms("item_123", 0, 500.0)
      |> PlaybackTracker.on_play_ms("item_123", 0, 250.0)
      # elapsed_ms is now 750.0
  """
  @spec on_play_ms(t(), String.t(), non_neg_integer(), float()) :: t()
  def on_play_ms(%__MODULE__{} = tracker, item_id, content_index, ms) do
    current = {item_id, content_index}

    if tracker.current_item == current do
      %{tracker | elapsed_ms: (tracker.elapsed_ms || 0.0) + ms}
    else
      %{tracker | current_item: current, elapsed_ms: ms}
    end
  end

  @doc """
  Reset the tracker when audio playback has been interrupted.

  This is called by the model when an interruption occurs.

  ## Examples

      tracker = PlaybackTracker.new()
      |> PlaybackTracker.on_play_ms("item_123", 0, 500.0)
      |> PlaybackTracker.on_interrupted()
      # current_item and elapsed_ms are now nil
  """
  @spec on_interrupted(t()) :: t()
  def on_interrupted(%__MODULE__{} = tracker) do
    %{tracker | current_item: nil, elapsed_ms: nil}
  end

  @doc """
  Set the audio format for duration calculations.

  This is called by the model when the audio format is configured.

  ## Examples

      tracker = PlaybackTracker.new()
      |> PlaybackTracker.set_audio_format(:pcm16)
  """
  @spec set_audio_format(t(), Audio.format()) :: t()
  def set_audio_format(%__MODULE__{} = tracker, format) do
    %{tracker | format: format}
  end

  @doc """
  Get the current playback state.

  Returns a map with the current item ID, content index, and elapsed milliseconds.
  If no audio has been played, all values are nil.

  ## Examples

      tracker = PlaybackTracker.new()
      |> PlaybackTracker.on_play_ms("item_123", 0, 500.0)

      PlaybackTracker.get_state(tracker)
      # %{current_item_id: "item_123", current_item_content_index: 0, elapsed_ms: 500.0}
  """
  @spec get_state(t()) :: %{
          current_item_id: String.t() | nil,
          current_item_content_index: non_neg_integer() | nil,
          elapsed_ms: float() | nil
        }
  def get_state(%__MODULE__{current_item: nil}) do
    %{current_item_id: nil, current_item_content_index: nil, elapsed_ms: nil}
  end

  def get_state(%__MODULE__{current_item: {item_id, content_index}, elapsed_ms: ms}) do
    %{current_item_id: item_id, current_item_content_index: content_index, elapsed_ms: ms}
  end
end

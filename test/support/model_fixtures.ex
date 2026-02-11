defmodule Codex.Test.ModelFixtures do
  @moduledoc """
  Canonical model and reasoning-level constants for tests.

  Use these instead of hardcoded model strings so that tests stay in sync
  when default models change upstream.  Tests that intentionally assert
  behaviour for a *specific* model (e.g. coercion rules for mini) may
  still inline the string — these fixtures are for the common case where
  the test just needs *a* valid model.
  """

  alias Codex.Models
  alias Codex.Realtime.Agent, as: RealtimeAgent
  alias Codex.Voice.Models.OpenAISTT
  alias Codex.Voice.Models.OpenAITTS

  @doc "The SDK default model (currently `Codex.Models.default_model/0`)."
  def default_model, do: Models.default_model(:api)

  @doc "A non-default model suitable for testing model-override paths."
  def alt_model, do: "gpt-5.1-codex-mini"

  @doc "The codex-max model."
  def max_model, do: "gpt-5.1-codex-max"

  @doc "The default realtime model."
  def realtime_model, do: RealtimeAgent.default_model()

  @doc "The default STT model."
  def stt_model, do: OpenAISTT.model_name()

  @doc "The default TTS model."
  def tts_model, do: OpenAITTS.model_name()
end

defmodule Codex.Voice.Models.OpenAIProvider do
  @moduledoc """
  OpenAI voice model provider.

  This module implements the `Codex.Voice.Model.ModelProvider` behaviour,
  providing factory methods for creating OpenAI STT and TTS models.

  ## Configuration

  The provider can be configured with:
  - API key (defaults to OPENAI_API_KEY env var)
  - Base URL (defaults to OpenAI's API)
  - Organization and project IDs (optional)

  ## Example

      # Default configuration
      provider = OpenAIProvider.new()
      stt = OpenAIProvider.get_stt_model(provider, nil)
      tts = OpenAIProvider.get_tts_model(provider, nil)

      # Custom API key
      provider = OpenAIProvider.new(api_key: "sk-...")
      stt = OpenAIProvider.get_stt_model(provider, "whisper-1")

  ## Default Models

  - STT: `gpt-4o-transcribe`
  - TTS: `gpt-4o-mini-tts`
  """

  @behaviour Codex.Voice.Model.ModelProvider

  alias Codex.Voice.Models.OpenAISTT
  alias Codex.Voice.Models.OpenAITTS

  defstruct [:api_key, :base_url, :organization, :project]

  @type t :: %__MODULE__{
          api_key: String.t() | nil,
          base_url: String.t() | nil,
          organization: String.t() | nil,
          project: String.t() | nil
        }

  @default_stt_model "gpt-4o-transcribe"
  @default_tts_model "gpt-4o-mini-tts"

  @doc """
  Create a new OpenAI voice model provider.

  ## Options

  - `:api_key` - API key (defaults to OPENAI_API_KEY env var)
  - `:base_url` - Base URL for API requests
  - `:organization` - Organization ID
  - `:project` - Project ID

  ## Examples

      iex> provider = Codex.Voice.Models.OpenAIProvider.new()
      iex> is_struct(provider, Codex.Voice.Models.OpenAIProvider)
      true

      iex> provider = Codex.Voice.Models.OpenAIProvider.new(api_key: "sk-test")
      iex> provider.api_key
      "sk-test"
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      api_key: Keyword.get(opts, :api_key),
      base_url: Keyword.get(opts, :base_url),
      organization: Keyword.get(opts, :organization),
      project: Keyword.get(opts, :project)
    }
  end

  @impl true
  def get_stt_model(model_name) do
    get_stt_model(%__MODULE__{}, model_name)
  end

  @doc """
  Get a speech-to-text model by name.

  If `model_name` is nil, returns the default STT model (`gpt-4o-transcribe`).

  ## Examples

      iex> provider = Codex.Voice.Models.OpenAIProvider.new()
      iex> model = Codex.Voice.Models.OpenAIProvider.get_stt_model(provider, nil)
      iex> model.model
      "gpt-4o-transcribe"

      iex> provider = Codex.Voice.Models.OpenAIProvider.new()
      iex> model = Codex.Voice.Models.OpenAIProvider.get_stt_model(provider, "whisper-1")
      iex> model.model
      "whisper-1"
  """
  @spec get_stt_model(t(), String.t() | nil) :: OpenAISTT.t()
  def get_stt_model(%__MODULE__{} = provider, model_name) do
    opts = build_opts(provider)
    OpenAISTT.new(model_name || @default_stt_model, opts)
  end

  @impl true
  def get_tts_model(model_name) do
    get_tts_model(%__MODULE__{}, model_name)
  end

  @doc """
  Get a text-to-speech model by name.

  If `model_name` is nil, returns the default TTS model (`gpt-4o-mini-tts`).

  ## Examples

      iex> provider = Codex.Voice.Models.OpenAIProvider.new()
      iex> model = Codex.Voice.Models.OpenAIProvider.get_tts_model(provider, nil)
      iex> model.model
      "gpt-4o-mini-tts"

      iex> provider = Codex.Voice.Models.OpenAIProvider.new()
      iex> model = Codex.Voice.Models.OpenAIProvider.get_tts_model(provider, "tts-1")
      iex> model.model
      "tts-1"
  """
  @spec get_tts_model(t(), String.t() | nil) :: OpenAITTS.t()
  def get_tts_model(%__MODULE__{} = provider, model_name) do
    opts = build_opts(provider)
    OpenAITTS.new(model_name || @default_tts_model, opts)
  end

  @spec build_opts(t()) :: keyword()
  defp build_opts(%__MODULE__{} = provider) do
    []
    |> maybe_add_opt(:api_key, provider.api_key)
    |> maybe_add_opt(:base_url, provider.base_url)
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)
end

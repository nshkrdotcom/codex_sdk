defmodule Codex.Realtime.Config do
  @moduledoc """
  Configuration types for realtime sessions.

  This module defines all configuration structures for customizing
  realtime session behavior, including model settings, turn detection,
  transcription, and tracing options.
  """

  # Type Definitions

  @type model_name ::
          :gpt_realtime
          | :gpt_4o_realtime_preview
          | :gpt_4o_mini_realtime_preview
          | String.t()

  @type audio_format :: :pcm16 | :g711_ulaw | :g711_alaw | String.t()
  @type modality :: :text | :audio
  @type eagerness :: :auto | :low | :medium | :high
  @type turn_detection_type :: :semantic_vad | :server_vad

  # Configuration Structs

  defmodule TurnDetectionConfig do
    @moduledoc "Configuration for voice activity detection and turn-taking."

    defstruct [
      :type,
      :create_response,
      :eagerness,
      :interrupt_response,
      :prefix_padding_ms,
      :silence_duration_ms,
      :threshold,
      :idle_timeout_ms
    ]

    @type t :: %__MODULE__{
            type: Codex.Realtime.Config.turn_detection_type() | nil,
            create_response: boolean() | nil,
            eagerness: Codex.Realtime.Config.eagerness() | nil,
            interrupt_response: boolean() | nil,
            prefix_padding_ms: non_neg_integer() | nil,
            silence_duration_ms: non_neg_integer() | nil,
            threshold: float() | nil,
            idle_timeout_ms: non_neg_integer() | nil
          }

    @doc "Convert to JSON-compatible map."
    @spec to_json(t()) :: map()
    def to_json(%__MODULE__{} = config) do
      %{}
      |> maybe_put("type", type_to_string(config.type))
      |> maybe_put("create_response", config.create_response)
      |> maybe_put("eagerness", eagerness_to_string(config.eagerness))
      |> maybe_put("interrupt_response", config.interrupt_response)
      |> maybe_put("prefix_padding_ms", config.prefix_padding_ms)
      |> maybe_put("silence_duration_ms", config.silence_duration_ms)
      |> maybe_put("threshold", config.threshold)
      |> maybe_put("idle_timeout_ms", config.idle_timeout_ms)
    end

    defp type_to_string(nil), do: nil
    defp type_to_string(:semantic_vad), do: "semantic_vad"
    defp type_to_string(:server_vad), do: "server_vad"

    defp eagerness_to_string(nil), do: nil
    defp eagerness_to_string(:auto), do: "auto"
    defp eagerness_to_string(:low), do: "low"
    defp eagerness_to_string(:medium), do: "medium"
    defp eagerness_to_string(:high), do: "high"

    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, key, value), do: Map.put(map, key, value)
  end

  defmodule TranscriptionConfig do
    @moduledoc "Configuration for input audio transcription."

    defstruct [:language, :model, :prompt]

    @type t :: %__MODULE__{
            language: String.t() | nil,
            model: String.t() | nil,
            prompt: String.t() | nil
          }

    @doc "Convert to JSON-compatible map."
    @spec to_json(t()) :: map()
    def to_json(%__MODULE__{} = config) do
      %{}
      |> maybe_put("language", config.language)
      |> maybe_put("model", config.model)
      |> maybe_put("prompt", config.prompt)
    end

    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, key, value), do: Map.put(map, key, value)
  end

  defmodule NoiseReductionConfig do
    @moduledoc "Configuration for input audio noise reduction."

    defstruct [:type]

    @type t :: %__MODULE__{
            type: :near_field | :far_field | nil
          }

    @doc "Convert to JSON-compatible map."
    @spec to_json(t()) :: map()
    def to_json(%__MODULE__{} = config) do
      case config.type do
        nil -> %{}
        :near_field -> %{"type" => "near_field"}
        :far_field -> %{"type" => "far_field"}
      end
    end
  end

  defmodule TracingConfig do
    @moduledoc "Configuration for request tracing."

    defstruct [:workflow_name, :group_id, :metadata]

    @type t :: %__MODULE__{
            workflow_name: String.t() | nil,
            group_id: String.t() | nil,
            metadata: map() | nil
          }
  end

  defmodule GuardrailsSettings do
    @moduledoc "Settings for output guardrails."

    defstruct debounce_text_length: 100

    @type t :: %__MODULE__{
            debounce_text_length: non_neg_integer()
          }
  end

  defmodule SessionModelSettings do
    @moduledoc "Model settings for a realtime session."

    alias Codex.Realtime.Config.NoiseReductionConfig
    alias Codex.Realtime.Config.TracingConfig
    alias Codex.Realtime.Config.TranscriptionConfig
    alias Codex.Realtime.Config.TurnDetectionConfig

    defstruct [
      :model_name,
      :instructions,
      :prompt,
      :modalities,
      :voice,
      :speed,
      :input_audio_format,
      :output_audio_format,
      :input_audio_transcription,
      :input_audio_noise_reduction,
      :turn_detection,
      :tool_choice,
      :tools,
      :handoffs,
      :tracing
    ]

    @type t :: %__MODULE__{
            model_name: Codex.Realtime.Config.model_name() | nil,
            instructions: String.t() | nil,
            prompt: String.t() | term() | nil,
            modalities: [Codex.Realtime.Config.modality()] | nil,
            voice: String.t() | nil,
            speed: float() | nil,
            input_audio_format: Codex.Realtime.Config.audio_format() | nil,
            output_audio_format: Codex.Realtime.Config.audio_format() | nil,
            input_audio_transcription: TranscriptionConfig.t() | nil,
            input_audio_noise_reduction: NoiseReductionConfig.t() | nil,
            turn_detection: TurnDetectionConfig.t() | nil,
            tool_choice: term() | nil,
            tools: [term()] | nil,
            handoffs: [term()] | nil,
            tracing: TracingConfig.t() | nil
          }

    @doc "Convert to JSON-compatible map for OpenAI API."
    @spec to_json(t()) :: map()
    def to_json(%__MODULE__{} = settings) do
      %{}
      |> maybe_put("model", settings.model_name)
      |> maybe_put("instructions", settings.instructions)
      |> maybe_put("modalities", modalities_to_json(settings.modalities))
      |> maybe_put("voice", settings.voice)
      |> maybe_put("speed", settings.speed)
      |> maybe_put("input_audio_format", format_to_string(settings.input_audio_format))
      |> maybe_put("output_audio_format", format_to_string(settings.output_audio_format))
      |> maybe_put_nested(
        "input_audio_transcription",
        settings.input_audio_transcription,
        &TranscriptionConfig.to_json/1
      )
      |> maybe_put_nested(
        "input_audio_noise_reduction",
        settings.input_audio_noise_reduction,
        &NoiseReductionConfig.to_json/1
      )
      |> maybe_put_nested(
        "turn_detection",
        settings.turn_detection,
        &TurnDetectionConfig.to_json/1
      )
      |> maybe_put("tool_choice", tool_choice_to_json(settings.tool_choice))
      |> maybe_put("tools", tools_to_json(settings.tools))
    end

    defp modalities_to_json(nil), do: nil
    defp modalities_to_json(mods), do: Enum.map(mods, &Atom.to_string/1)

    defp format_to_string(nil), do: nil
    defp format_to_string(f) when is_atom(f), do: Atom.to_string(f)
    defp format_to_string(f) when is_binary(f), do: f

    defp tool_choice_to_json(nil), do: nil
    defp tool_choice_to_json(:auto), do: "auto"
    defp tool_choice_to_json(:none), do: "none"
    defp tool_choice_to_json(:required), do: "required"

    defp tool_choice_to_json({:function, name}), do: %{"type" => "function", "name" => name}

    defp tools_to_json(nil), do: nil

    defp tools_to_json(tools) do
      Enum.map(tools, &serialize_tool/1)
    end

    defp serialize_tool(%{__struct__: struct_module} = struct_tool) do
      if function_exported?(struct_module, :to_function_schema, 1) do
        struct_module.to_function_schema(struct_tool)
      else
        struct_tool
      end
    end

    defp serialize_tool(other), do: other

    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, key, value), do: Map.put(map, key, value)

    defp maybe_put_nested(map, _key, nil, _fun), do: map
    defp maybe_put_nested(map, key, value, fun), do: Map.put(map, key, fun.(value))
  end

  defmodule RunConfig do
    @moduledoc "Configuration for running a realtime agent session."

    alias Codex.Realtime.Config.GuardrailsSettings
    alias Codex.Realtime.Config.SessionModelSettings

    defstruct model_settings: nil,
              output_guardrails: nil,
              guardrails_settings: nil,
              tracing_disabled: false,
              async_tool_calls: true

    @type t :: %__MODULE__{
            model_settings: SessionModelSettings.t() | nil,
            output_guardrails: [term()] | nil,
            guardrails_settings: GuardrailsSettings.t() | nil,
            tracing_disabled: boolean(),
            async_tool_calls: boolean()
          }
  end

  defmodule ModelConfig do
    @moduledoc "Options for connecting to a realtime model."

    alias Codex.Auth
    alias Codex.Config.Defaults
    alias Codex.Realtime.Config.SessionModelSettings

    defstruct [
      :api_key,
      :url,
      :headers,
      :initial_model_settings,
      :playback_tracker,
      :call_id
    ]

    @type api_key_fn :: (-> String.t())

    @type t :: %__MODULE__{
            api_key: String.t() | api_key_fn() | nil,
            url: String.t() | nil,
            headers: %{String.t() => String.t()} | nil,
            initial_model_settings: SessionModelSettings.t() | nil,
            playback_tracker: term() | nil,
            call_id: String.t() | nil
          }

    @default_url Defaults.openai_realtime_ws_url()

    @doc "Resolve the API key, calling function if needed."
    @spec resolve_api_key(t()) :: String.t() | nil
    def resolve_api_key(%__MODULE__{api_key: nil}), do: Auth.direct_api_key()
    def resolve_api_key(%__MODULE__{api_key: key}) when is_binary(key), do: key
    def resolve_api_key(%__MODULE__{api_key: fun}) when is_function(fun, 0), do: fun.()

    @doc "Build the WebSocket URL with query parameters."
    @spec build_url(t(), String.t() | nil) :: String.t()
    def build_url(%__MODULE__{} = config, model_name) do
      base_url = config.url || @default_url

      cond do
        config.call_id ->
          "#{base_url}?call_id=#{URI.encode(config.call_id)}"

        model_name ->
          "#{base_url}?model=#{URI.encode(model_name)}"

        true ->
          base_url
      end
    end
  end

  # Helper Functions

  @doc """
  Merge two session model settings, with the override taking precedence.

  Only non-nil values from override are used.
  """
  @spec merge_settings(SessionModelSettings.t(), SessionModelSettings.t()) ::
          SessionModelSettings.t()
  def merge_settings(%SessionModelSettings{} = base, %SessionModelSettings{} = override) do
    base_map = Map.from_struct(base)
    override_map = Map.from_struct(override)

    merged =
      Map.merge(base_map, override_map, fn _key, base_val, override_val ->
        if is_nil(override_val), do: base_val, else: override_val
      end)

    struct!(SessionModelSettings, merged)
  end

  @doc """
  Create default session model settings.
  """
  @spec default_session_settings() :: SessionModelSettings.t()
  def default_session_settings do
    %SessionModelSettings{
      modalities: [:text, :audio],
      input_audio_format: :pcm16,
      output_audio_format: :pcm16,
      turn_detection: %TurnDetectionConfig{
        type: :semantic_vad,
        create_response: true,
        interrupt_response: true
      }
    }
  end
end

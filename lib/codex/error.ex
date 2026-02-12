defmodule Codex.Error do
  @moduledoc """
  Base error struct for Codex failures.

  ## Error Kinds

    * `:rate_limit` - API rate limit exceeded
    * `:sandbox_assessment_failed` - Sandbox assessment failed
    * `:unknown` - Unclassified error

  ## Rate Limit Handling

  Rate limit errors may include a `retry_after_ms` hint extracted from
  the API response. Use `retry_after_ms/1` to access this value.
  """

  defexception [:message, :kind, :details, :retry_after_ms]

  @type kind ::
          :rate_limit
          | :sandbox_assessment_failed
          | :unknown
          # Realtime errors
          | :realtime_connection_failed
          | :realtime_connection_closed
          | :realtime_session_error
          | :realtime_audio_error
          | :realtime_tool_error
          | :realtime_handoff_error
          | :realtime_guardrail_tripped
          # Voice errors
          | :voice_stt_error
          | :voice_stt_connection_error
          | :voice_tts_error
          | :voice_workflow_error
          | :voice_pipeline_error
          | :unsupported_feature

  @type t :: %__MODULE__{
          message: String.t(),
          kind: kind(),
          details: map(),
          retry_after_ms: non_neg_integer() | nil
        }

  @doc """
  Normalizes raw error payloads into `%Codex.Error{}` structs.

  Accepts maps emitted by codex-rs (`turn.failed`), basic strings, or already
  constructed `%Codex.Error{}` structs. Known codes and types are classified
  into stable `:kind` atoms so callers can branch on error domains (e.g.,
  rate limits, sandbox assessment failures).
  """
  @spec normalize(term()) :: t()
  def normalize(%__MODULE__{} = error), do: error

  def normalize(%Codex.TransportError{} = error) do
    details =
      %{
        exit_status: error.exit_status,
        stderr: error.stderr,
        stderr_truncated?: error.stderr_truncated?,
        retryable?: error.retryable?
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    new(:unknown, error.message, details)
  end

  def normalize(%{message: message} = payload) do
    normalize_map(Map.put(payload, "message", message))
  end

  def normalize(%{"message" => _} = payload), do: normalize_map(payload)

  def normalize(%{} = payload), do: normalize_map(payload)

  def normalize({:codex_timeout, timeout_ms}) when is_integer(timeout_ms) do
    new(:unknown, "codex exec timed out after #{timeout_ms}ms", %{timeout_ms: timeout_ms})
  end

  def normalize(message) when is_binary(message) do
    new(:unknown, message, %{})
  end

  def normalize(other), do: new(:unknown, inspect(other), %{})

  @spec new(atom(), String.t(), map()) :: t()
  def new(kind, message, details \\ %{}) do
    %__MODULE__{kind: kind, message: message, details: details, retry_after_ms: nil}
  end

  @doc """
  Creates a rate limit error with optional retry-after hint.

  ## Options

    * `:retry_after_ms` - Suggested delay before retry in milliseconds
    * `:details` - Additional error details map

  ## Examples

      iex> error = Codex.Error.rate_limit("Rate limit exceeded", retry_after_ms: 30_000)
      iex> error.kind
      :rate_limit
      iex> error.retry_after_ms
      30_000
  """
  @spec rate_limit(String.t(), keyword()) :: t()
  def rate_limit(message, opts \\ []) do
    retry_after = Keyword.get(opts, :retry_after_ms)
    details = Keyword.get(opts, :details, %{})

    %__MODULE__{
      kind: :rate_limit,
      message: message,
      details: details,
      retry_after_ms: retry_after
    }
  end

  @doc """
  Checks if error is a rate limit error.

  ## Examples

      iex> error = Codex.Error.rate_limit("Rate limited")
      iex> Codex.Error.rate_limit?(error)
      true
      iex> Codex.Error.rate_limit?(%Codex.Error{kind: :unknown, message: "Other"})
      false
  """
  @spec rate_limit?(t() | term()) :: boolean()
  def rate_limit?(%__MODULE__{kind: :rate_limit}), do: true
  def rate_limit?(_), do: false

  @doc """
  Extracts retry-after hint from error if present.

  Returns the delay in milliseconds, or `nil` if not available.

  ## Examples

      iex> error = Codex.Error.rate_limit("Rate limited", retry_after_ms: 60_000)
      iex> Codex.Error.retry_after_ms(error)
      60_000
      iex> Codex.Error.retry_after_ms(%Codex.Error{kind: :unknown, message: "Other"})
      nil
  """
  @spec retry_after_ms(t()) :: non_neg_integer() | nil
  def retry_after_ms(%__MODULE__{retry_after_ms: ms}) when is_integer(ms) and ms > 0, do: ms
  def retry_after_ms(_), do: nil

  # Realtime error constructors

  @doc """
  Creates a realtime connection failed error.
  """
  @spec realtime_connection_failed(keyword()) :: t()
  def realtime_connection_failed(opts \\ []) do
    message = Keyword.get(opts, :message, "Realtime connection failed")
    details = Keyword.get(opts, :details, %{})
    new(:realtime_connection_failed, message, details)
  end

  @doc """
  Creates a realtime connection closed error.
  """
  @spec realtime_connection_closed(keyword()) :: t()
  def realtime_connection_closed(opts \\ []) do
    message = Keyword.get(opts, :message, "Realtime connection closed")
    details = Keyword.get(opts, :details, %{})
    new(:realtime_connection_closed, message, details)
  end

  @doc """
  Creates a realtime session error.
  """
  @spec realtime_session_error(keyword()) :: t()
  def realtime_session_error(opts \\ []) do
    message = Keyword.get(opts, :message, "Realtime session error")
    details = Keyword.get(opts, :details, %{})
    new(:realtime_session_error, message, details)
  end

  @doc """
  Creates a realtime audio error.
  """
  @spec realtime_audio_error(keyword()) :: t()
  def realtime_audio_error(opts \\ []) do
    message = Keyword.get(opts, :message, "Realtime audio error")
    details = Keyword.get(opts, :details, %{})
    new(:realtime_audio_error, message, details)
  end

  @doc """
  Creates a realtime tool error.
  """
  @spec realtime_tool_error(keyword()) :: t()
  def realtime_tool_error(opts \\ []) do
    message = Keyword.get(opts, :message, "Realtime tool error")
    details = Keyword.get(opts, :details, %{})
    new(:realtime_tool_error, message, details)
  end

  @doc """
  Creates a realtime handoff error.
  """
  @spec realtime_handoff_error(keyword()) :: t()
  def realtime_handoff_error(opts \\ []) do
    message = Keyword.get(opts, :message, "Realtime handoff error")
    details = Keyword.get(opts, :details, %{})
    new(:realtime_handoff_error, message, details)
  end

  @doc """
  Creates a realtime guardrail tripped error.
  """
  @spec realtime_guardrail_tripped(keyword()) :: t()
  def realtime_guardrail_tripped(opts \\ []) do
    message = Keyword.get(opts, :message, "Realtime guardrail tripped")
    details = Keyword.get(opts, :details, %{})
    new(:realtime_guardrail_tripped, message, details)
  end

  # Voice error constructors

  @doc """
  Creates a voice STT (speech-to-text) error.
  """
  @spec voice_stt_error(keyword()) :: t()
  def voice_stt_error(opts \\ []) do
    message = Keyword.get(opts, :message, "Voice STT error")
    details = Keyword.get(opts, :details, %{})
    new(:voice_stt_error, message, details)
  end

  @doc """
  Creates a voice STT connection error.
  """
  @spec voice_stt_connection_error(keyword()) :: t()
  def voice_stt_connection_error(opts \\ []) do
    message = Keyword.get(opts, :message, "Voice STT connection error")
    details = Keyword.get(opts, :details, %{})
    new(:voice_stt_connection_error, message, details)
  end

  @doc """
  Creates a voice TTS (text-to-speech) error.
  """
  @spec voice_tts_error(keyword()) :: t()
  def voice_tts_error(opts \\ []) do
    message = Keyword.get(opts, :message, "Voice TTS error")
    details = Keyword.get(opts, :details, %{})
    new(:voice_tts_error, message, details)
  end

  @doc """
  Creates a voice workflow error.
  """
  @spec voice_workflow_error(keyword()) :: t()
  def voice_workflow_error(opts \\ []) do
    message = Keyword.get(opts, :message, "Voice workflow error")
    details = Keyword.get(opts, :details, %{})
    new(:voice_workflow_error, message, details)
  end

  @doc """
  Creates a voice pipeline error.
  """
  @spec voice_pipeline_error(keyword()) :: t()
  def voice_pipeline_error(opts \\ []) do
    message = Keyword.get(opts, :message, "Voice pipeline error")
    details = Keyword.get(opts, :details, %{})
    new(:voice_pipeline_error, message, details)
  end

  defp normalize_map(payload) do
    message =
      payload
      |> fetch_value(["message", :message])
      |> Kernel.||("turn failed")

    code = fetch_value(payload, ["code", :code])
    type = fetch_value(payload, ["type", :type])
    status = fetch_value(payload, ["status", :status])
    retry_after = fetch_value(payload, ["retry_after", :retry_after])

    additional_details =
      fetch_value(payload, ["additional_details", "additionalDetails", :additional_details])

    codex_error_info =
      fetch_value(payload, ["codex_error_info", "codexErrorInfo", :codex_error_info])

    details = fetch_value(payload, ["details", :details]) || %{}

    kind = classify_kind(code, type, message)

    detail_map =
      %{
        code: code,
        type: type,
        status: status,
        retry_after: retry_after,
        additional_details: additional_details,
        codex_error_info: codex_error_info,
        details: details,
        raw: payload
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    retry_after_ms = parse_retry_after_ms(retry_after, status)

    %__MODULE__{
      kind: kind,
      message: message,
      details: detail_map,
      retry_after_ms: retry_after_ms
    }
  end

  defp parse_retry_after_ms(nil, _status), do: nil

  defp parse_retry_after_ms(retry_after, _status) when is_integer(retry_after) do
    # Assume seconds if < 1000, otherwise milliseconds
    if retry_after < 1000, do: retry_after * 1000, else: retry_after
  end

  defp parse_retry_after_ms(retry_after, _status) when is_binary(retry_after) do
    case Integer.parse(retry_after) do
      {seconds, _} -> seconds * 1000
      :error -> nil
    end
  end

  defp parse_retry_after_ms(_, _), do: nil

  defp fetch_value(map, [key | rest]) do
    case Map.get(map, key) do
      nil -> fetch_value(map, rest)
      value -> value
    end
  end

  defp fetch_value(_map, []), do: nil

  defp classify_kind(code, type, message) do
    cond do
      match_rate_limit?(code, type, message) -> :rate_limit
      match_sandbox_assessment?(code, type, message) -> :sandbox_assessment_failed
      true -> :unknown
    end
  end

  defp match_rate_limit?(code, type, message) do
    code in ["rate_limit", "rate_limit_exceeded", "rate_limit_error"] ||
      type in ["rate_limit", "rate_limit_error", "azure_rate_limit"] ||
      (is_binary(message) and String.match?(message, ~r/rate limit/i))
  end

  defp match_sandbox_assessment?(code, type, message) do
    code in ["sandbox_assessment_failed", "sandbox_assessment"] ||
      type in ["sandbox_assessment_failed", "sandbox_assessment"] ||
      (is_binary(message) and String.match?(message, ~r/sandbox assessment/i))
  end
end

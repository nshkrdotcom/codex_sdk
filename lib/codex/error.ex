defmodule Codex.Error do
  @moduledoc """
  Base error struct for Codex failures.
  """

  defexception [:message, :kind, :details]

  @type t :: %__MODULE__{message: String.t(), kind: atom(), details: map()}

  @doc """
  Normalizes raw error payloads into `%Codex.Error{}` structs.

  Accepts maps emitted by codex-rs (`turn.failed`), basic strings, or already
  constructed `%Codex.Error{}` structs. Known codes and types are classified
  into stable `:kind` atoms so callers can branch on error domains (e.g.,
  rate limits, sandbox assessment failures).
  """
  @spec normalize(term()) :: t()
  def normalize(%__MODULE__{} = error), do: error

  def normalize(%{message: message} = payload) do
    normalize_map(Map.put(payload, "message", message))
  end

  def normalize(%{"message" => _} = payload), do: normalize_map(payload)

  def normalize(%{} = payload), do: normalize_map(payload)

  def normalize(message) when is_binary(message) do
    new(:unknown, message, %{})
  end

  def normalize(other), do: new(:unknown, inspect(other), %{})

  @spec new(atom(), String.t(), map()) :: t()
  def new(kind, message, details \\ %{}) do
    %__MODULE__{kind: kind, message: message, details: details}
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

    new(kind, message, detail_map)
  end

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

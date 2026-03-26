defmodule Codex.ExamplesSupport do
  @moduledoc false

  alias Codex.Items
  alias Codex.Models
  alias Codex.Turn.Result

  @spec ollama_mode?() :: boolean()
  def ollama_mode? do
    System.get_env("CODEX_PROVIDER_BACKEND") == "oss" and
      System.get_env("CODEX_OSS_PROVIDER") == "ollama"
  end

  @spec ollama_model() :: String.t()
  def ollama_model do
    System.get_env("CODEX_MODEL") || "llama3.2"
  end

  @spec example_model(String.t() | nil) :: String.t()
  def example_model(default \\ Models.default_model()) do
    if ollama_mode?(), do: ollama_model(), else: default
  end

  @spec example_reasoning(Models.reasoning_effort() | nil) :: Models.reasoning_effort() | nil
  def example_reasoning(default \\ Models.default_reasoning_effort()) do
    if ollama_mode?(), do: nil, else: default
  end

  @spec decode_json_result(Result.t()) :: {:ok, term()} | {:error, term()}
  def decode_json_result(%Result{} = result) do
    case Result.json(result) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, _reason} ->
        decode_json_message(result.final_response)
    end
  end

  defp decode_json_message(%Items.AgentMessage{text: text}) when is_binary(text) do
    text
    |> json_candidates()
    |> Enum.find_value({:error, :invalid_json}, fn candidate ->
      case Jason.decode(candidate) do
        {:ok, decoded} -> {:ok, decoded}
        {:error, _reason} -> nil
      end
    end)
  end

  defp decode_json_message(_other), do: {:error, :invalid_json}

  defp json_candidates(text) when is_binary(text) do
    trimmed = String.trim(text)

    [
      trimmed,
      fenced_json(trimmed),
      bracket_slice(trimmed, "{", "}"),
      bracket_slice(trimmed, "[", "]")
    ]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp fenced_json(text) when is_binary(text) do
    case Regex.run(~r/```(?:json)?\s*(.*?)\s*```/s, text, capture: :all_but_first) do
      [body] -> String.trim(body)
      _ -> nil
    end
  end

  defp bracket_slice(text, left, right)
       when is_binary(text) and is_binary(left) and is_binary(right) do
    case {:binary.match(text, left), :binary.matches(text, right)} do
      {:nomatch, _} ->
        nil

      {_, []} ->
        nil

      {{start_idx, _left_len}, matches} ->
        {end_idx, _right_len} = List.last(matches)

        if start_idx <= end_idx do
          text
          |> binary_part(start_idx, end_idx - start_idx + byte_size(right))
          |> String.trim()
        else
          nil
        end
    end
  end
end

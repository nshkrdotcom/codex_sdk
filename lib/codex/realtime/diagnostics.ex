defmodule Codex.Realtime.Diagnostics do
  @moduledoc """
  Diagnostics helpers for OpenAI Realtime sessions.

  The direct Realtime API occasionally returns generic `server_error` payloads
  that are hard to distinguish from SDK bugs when all you see is an example
  failure. This module provides:

  - a minimal raw WebSocket text-turn probe that exercises the upstream service
    before higher-level example logic runs
  - error classification helpers for known skip conditions
  - session-id extraction so callers can report concrete upstream evidence
  """

  alias Codex.Realtime.Agent, as: RealtimeAgent
  alias Codex.Realtime.Config.ModelConfig
  alias Codex.Realtime.ModelEvents
  alias Codex.Realtime.OpenAIWebSocket

  @default_probe_prompt "Reply with exactly ok."
  @default_timeout_ms 8_000

  @type probe_result :: %{
          model: String.t(),
          prompt: String.t(),
          session_id: String.t() | nil,
          session_created: map() | nil,
          events: [String.t()],
          error: map() | nil
        }

  @doc """
  Runs a minimal raw-WebSocket text probe against the Realtime API.

  The probe intentionally bypasses `Codex.Realtime.Session` so callers can tell
  whether a failure is in the upstream Realtime service or in higher-level SDK
  logic such as examples, tools, or handoffs.
  """
  @spec probe_text_turn(keyword()) :: {:ok, probe_result()} | {:error, term()}
  def probe_text_turn(opts \\ []) do
    model = Keyword.get(opts, :model, RealtimeAgent.default_model())
    prompt = Keyword.get(opts, :prompt, @default_probe_prompt)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    model_config = Keyword.get(opts, :model_config, %ModelConfig{})
    websocket_module = Keyword.get(opts, :websocket_module, OpenAIWebSocket)
    websocket_opts = Keyword.get(opts, :websocket_opts, [])

    with {:ok, ws} <-
           websocket_module.start_link(
             [session_pid: self(), config: model_config, model_name: model] ++ websocket_opts
           ) do
      try do
        run_probe_turn(ws, websocket_module, model, prompt, timeout_ms)
      after
        websocket_module.close(ws)
      end
    end
  end

  @doc """
  Returns a human-readable summary for a failed probe.
  """
  @spec format_probe_failure(probe_result()) :: String.t()
  def format_probe_failure(%{} = proof) do
    event_chain =
      proof
      |> Map.get(:events, [])
      |> Enum.join(" -> ")

    message =
      case Map.get(proof, :error) do
        %{"message" => value} when is_binary(value) -> value
        value when is_map(value) -> inspect(value, limit: :infinity)
        value -> inspect(value, limit: :infinity)
      end

    "OpenAI Realtime returned upstream server_error during a minimal raw WebSocket probe " <>
      "(model=#{proof.model}, session_id=#{proof.session_id || "unknown"}, events=#{event_chain}, " <>
      "error=#{message})"
  end

  @doc """
  Extracts a Realtime session id (`sess_...`) from a message, map, or inspected term.
  """
  @spec extract_session_id(term()) :: String.t() | nil
  def extract_session_id(error) do
    text = normalized_error_text(error)

    case Regex.run(~r/(sess_[A-Za-z0-9]+)/, text, capture: :all_but_first) do
      [session_id] -> session_id
      _ -> nil
    end
  end

  @doc """
  Maps known direct-API Realtime failures to example skip reasons.
  """
  @spec skip_reason_for_error(term()) :: String.t() | nil
  def skip_reason_for_error(error) do
    normalized = normalized_error_text(error) |> String.downcase()
    error_type = error_type(error)

    cond do
      insufficient_quota_error?(normalized) ->
        "insufficient_quota"

      realtime_model_unavailable_error?(normalized) ->
        "realtime_model_unavailable"

      protocol_incompatibility_error?(error, normalized) ->
        "realtime_protocol_incompatible"

      realtime_server_error?(error_type, normalized) ->
        server_error_skip_reason(error)

      true ->
        nil
    end
  end

  defp insufficient_quota_error?(normalized) do
    String.contains?(normalized, "insufficient_quota")
  end

  defp realtime_model_unavailable_error?(normalized) do
    String.contains?(normalized, "model_not_found") or
      String.contains?(normalized, "do not have access")
  end

  defp realtime_server_error?(error_type, normalized) do
    error_type == "server_error" or String.contains?(normalized, "server_error")
  end

  defp server_error_skip_reason(error) do
    case extract_session_id(error) do
      nil -> "realtime_upstream_server_error"
      session_id -> "realtime_upstream_server_error (session_id=#{session_id})"
    end
  end

  defp send_minimal_text_probe(ws, websocket_module, prompt) do
    websocket_module.send_message(ws, %{
      "type" => "response.create",
      "response" => %{
        "conversation" => "none",
        "input" => [
          %{
            "type" => "message",
            "role" => "user",
            "content" => [%{"type" => "input_text", "text" => prompt}]
          }
        ]
      }
    })
  end

  defp run_probe_turn(ws, websocket_module, model, prompt, timeout_ms) do
    with {:ok, created, events} <- await_session_created(deadline(timeout_ms), []),
         :ok <- send_minimal_text_probe(ws, websocket_module, prompt) do
      await_probe_outcome(deadline(timeout_ms), model, prompt, created, events)
    end
  end

  defp await_session_created(deadline_ms, events) do
    case receive_raw_server_event(deadline_ms) do
      {:ok, %{"type" => "session.created"} = data} ->
        {:ok, data, events ++ ["session.created"]}

      {:ok, %{"type" => "error", "error" => error}} ->
        proof = %{
          model: nil,
          prompt: nil,
          session_id: extract_session_id(error),
          session_created: nil,
          events: events ++ ["error"],
          error: error
        }

        {:error, {:upstream_server_error, proof}}

      {:ok, %{"type" => type}} ->
        await_session_created(deadline_ms, events ++ [type])

      {:error, _} = error ->
        error
    end
  end

  defp await_probe_outcome(deadline_ms, model, prompt, created, events) do
    session_id = get_in(created, ["session", "id"])

    case receive_raw_server_event(deadline_ms) do
      {:ok, %{"type" => "response.done", "response" => %{"status" => "completed"}}} ->
        {:ok,
         %{
           model: model,
           prompt: prompt,
           session_id: session_id,
           session_created: created,
           events: events ++ ["response.done"],
           error: nil
         }}

      {:ok, %{"type" => "response.done", "response" => response}} ->
        error =
          response
          |> Map.get("status_details", %{})
          |> Map.get("error", %{"message" => "response.done failed", "type" => "response_failed"})

        proof = %{
          model: model,
          prompt: prompt,
          session_id: session_id,
          session_created: created,
          events: events ++ ["response.done"],
          error: error
        }

        {:error, {:realtime_probe_failed, proof}}

      {:ok, %{"type" => "error", "error" => error}} ->
        proof = %{
          model: model,
          prompt: prompt,
          session_id: session_id || extract_session_id(error),
          session_created: created,
          events: events ++ ["error"],
          error: error
        }

        if Map.get(error, "type") == "server_error" do
          {:error, {:upstream_server_error, proof}}
        else
          {:error, {:realtime_probe_failed, proof}}
        end

      {:ok, %{"type" => type}} ->
        await_probe_outcome(deadline_ms, model, prompt, created, events ++ [type])

      {:error, :probe_timeout} ->
        {:error,
         {:probe_timeout,
          %{
            model: model,
            prompt: prompt,
            session_id: session_id,
            session_created: created,
            events: events,
            error: nil
          }}}
    end
  end

  defp receive_raw_server_event(deadline_ms) do
    remaining_ms = max(deadline_ms - System.monotonic_time(:millisecond), 0)

    if remaining_ms <= 0 do
      {:error, :probe_timeout}
    else
      receive do
        {:model_event, %ModelEvents.RawServerEvent{data: data}} ->
          {:ok, data}

        {:model_event, _other} ->
          receive_raw_server_event(deadline_ms)
      after
        remaining_ms ->
          {:error, :probe_timeout}
      end
    end
  end

  defp deadline(timeout_ms), do: System.monotonic_time(:millisecond) + timeout_ms

  defp normalized_error_text(error) when is_binary(error), do: error

  defp normalized_error_text(%{"message" => message}) when is_binary(message) do
    message
  end

  defp normalized_error_text(error) do
    inspect(error, limit: :infinity)
  end

  defp error_type(%{"type" => type}) when is_binary(type), do: type
  defp error_type(_), do: nil

  defp protocol_incompatibility_error?(%{} = error, normalized) do
    code = Map.get(error, "code")
    param = Map.get(error, "param")
    type = Map.get(error, "type")

    (code == "unknown_parameter" or
       String.contains?(normalized, "unknown parameter") or
       String.contains?(normalized, "unknown field") or
       String.contains?(normalized, "unexpected field") or
       String.contains?(normalized, "unrecognized field")) and
      (type in [nil, "invalid_request_error"] or is_binary(type)) and
      schema_param?(param, normalized)
  end

  defp protocol_incompatibility_error?(_error, _normalized), do: false

  defp schema_param?(param, _normalized)
       when param in ["response.output_modalities", "response.output_modalities[]"] do
    true
  end

  defp schema_param?(_param, normalized) do
    String.contains?(normalized, "response.output_modalities") or
      String.contains?(normalized, "output_modalities")
  end
end

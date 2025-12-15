defmodule Codex.AppServer.NotificationAdapter do
  @moduledoc false

  alias Codex.AppServer.ItemAdapter
  alias Codex.Events

  @spec to_event(String.t(), map() | nil) :: {:ok, Events.t()}
  def to_event("error", %{} = params) do
    {:ok,
     %Events.Error{
       message: get_in(params, ["error", "message"]) || "",
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: fetch(params, "turnId", "turn_id")
     }}
  end

  def to_event("thread/started", %{} = params) do
    thread = Map.get(params, "thread") || %{}

    {:ok,
     %Events.ThreadStarted{
       thread_id: Map.get(thread, "id") || "",
       metadata: thread
     }}
  end

  def to_event("thread/tokenUsage/updated", %{} = params) do
    token_usage = Map.get(params, "tokenUsage") || %{}

    {:ok,
     %Events.ThreadTokenUsageUpdated{
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: fetch(params, "turnId", "turn_id"),
       usage: token_usage |> Map.get("total") |> normalize_token_usage_breakdown(),
       delta: token_usage |> Map.get("last") |> normalize_token_usage_breakdown()
     }}
  end

  def to_event("thread/compacted", %{} = params) do
    {:ok,
     %Events.TurnCompaction{
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: fetch(params, "turnId", "turn_id"),
       compaction: %{},
       stage: :completed
     }}
  end

  def to_event("turn/started", %{} = params) do
    turn = Map.get(params, "turn") || %{}

    {:ok,
     %Events.TurnStarted{
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: Map.get(turn, "id")
     }}
  end

  def to_event("turn/completed", %{} = params) do
    turn = Map.get(params, "turn") || %{}

    {:ok,
     %Events.TurnCompleted{
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: Map.get(turn, "id"),
       status: normalize_turn_status(Map.get(turn, "status"))
     }}
  end

  def to_event("turn/diff/updated", %{} = params) do
    {:ok,
     %Events.TurnDiffUpdated{
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: fetch(params, "turnId", "turn_id"),
       diff: Map.get(params, "diff") || ""
     }}
  end

  def to_event("turn/plan/updated", %{} = params) do
    {:ok,
     %Events.TurnPlanUpdated{
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: fetch(params, "turnId", "turn_id"),
       explanation: Map.get(params, "explanation"),
       plan: normalize_plan(Map.get(params, "plan") || [])
     }}
  end

  def to_event("item/started", %{} = params), do: handle_item_event(Events.ItemStarted, params)

  def to_event("item/completed", %{} = params),
    do: handle_item_event(Events.ItemCompleted, params)

  def to_event("item/agentMessage/delta", %{} = params) do
    {:ok,
     %Events.ItemAgentMessageDelta{
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: fetch(params, "turnId", "turn_id"),
       item: %{
         "id" => fetch(params, "itemId", "item_id"),
         "type" => "agent_message",
         "text" => Map.get(params, "delta") || ""
       }
     }}
  end

  def to_event("item/reasoning/textDelta", %{} = params) do
    {:ok,
     %Events.ReasoningDelta{
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: fetch(params, "turnId", "turn_id"),
       item_id: fetch(params, "itemId", "item_id") || "",
       delta: Map.get(params, "delta") || "",
       content_index: Map.get(params, "contentIndex")
     }}
  end

  def to_event("item/reasoning/summaryTextDelta", %{} = params) do
    {:ok,
     %Events.ReasoningSummaryDelta{
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: fetch(params, "turnId", "turn_id"),
       item_id: fetch(params, "itemId", "item_id") || "",
       delta: Map.get(params, "delta") || "",
       summary_index: Map.get(params, "summaryIndex")
     }}
  end

  def to_event("item/commandExecution/outputDelta", %{} = params) do
    {:ok,
     %Events.CommandOutputDelta{
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: fetch(params, "turnId", "turn_id"),
       item_id: fetch(params, "itemId", "item_id") || "",
       delta: Map.get(params, "delta") || ""
     }}
  end

  def to_event(method, %{} = params) when is_binary(method) do
    {:ok, %Events.AppServerNotification{method: method, params: params}}
  end

  def to_event(method, params) when is_binary(method) do
    {:ok, %Events.AppServerNotification{method: method, params: Map.new(params || %{})}}
  end

  defp handle_item_event(event_module, params) do
    item = Map.get(params, "item") || %{}

    case ItemAdapter.to_item(item) do
      {:ok, item_struct} ->
        {:ok,
         struct(event_module,
           thread_id: fetch(params, "threadId", "thread_id"),
           turn_id: fetch(params, "turnId", "turn_id"),
           item: item_struct
         )}

      {:raw, raw_item} ->
        {:ok,
         %Events.AppServerNotification{
           method: "item/#{event_suffix(event_module)}",
           params: Map.put(params, "item", raw_item)
         }}
    end
  end

  defp event_suffix(Events.ItemStarted), do: "started"
  defp event_suffix(Events.ItemCompleted), do: "completed"

  defp fetch(map, key1, key2) do
    Map.get(map, key1) || Map.get(map, key2)
  end

  defp normalize_token_usage_breakdown(nil), do: %{}

  defp normalize_token_usage_breakdown(%{} = breakdown) do
    %{}
    |> put_int("total_tokens", Map.get(breakdown, "totalTokens"))
    |> put_int("input_tokens", Map.get(breakdown, "inputTokens"))
    |> put_int("cached_input_tokens", Map.get(breakdown, "cachedInputTokens"))
    |> put_int("output_tokens", Map.get(breakdown, "outputTokens"))
    |> put_int("reasoning_output_tokens", Map.get(breakdown, "reasoningOutputTokens"))
  end

  defp normalize_token_usage_breakdown(_), do: %{}

  defp put_int(map, _key, nil), do: map
  defp put_int(map, key, value) when is_integer(value), do: Map.put(map, key, value)
  defp put_int(map, key, value) when is_number(value), do: Map.put(map, key, trunc(value))
  defp put_int(map, _key, _value), do: map

  defp normalize_plan(plan) when is_list(plan) do
    Enum.map(plan, fn step ->
      %{
        step: Map.get(step, "step") || "",
        status: normalize_plan_status(Map.get(step, "status"))
      }
    end)
  end

  defp normalize_plan(_plan), do: []

  defp normalize_plan_status("pending"), do: :pending
  defp normalize_plan_status("inProgress"), do: :in_progress
  defp normalize_plan_status("completed"), do: :completed
  defp normalize_plan_status(_), do: :pending

  defp normalize_turn_status(nil), do: nil

  defp normalize_turn_status(status) when is_binary(status) do
    case status do
      "inProgress" -> "in_progress"
      other -> other
    end
  end

  defp normalize_turn_status(status), do: status
end

defmodule Codex.AppServer.NotificationAdapter do
  @moduledoc false

  alias Codex.AppServer.ItemAdapter
  alias Codex.Events
  alias Codex.Protocol.RateLimit.Snapshot, as: RateLimitSnapshot

  @spec to_event(String.t(), map() | nil) :: {:ok, Events.t()}
  def to_event("error", %{} = params) do
    error = Map.get(params, "error") || %{}

    {:ok,
     %Events.Error{
       message: Map.get(error, "message") || "",
       additional_details:
         Map.get(error, "additionalDetails") || Map.get(error, "additional_details"),
       codex_error_info: Map.get(error, "codexErrorInfo") || Map.get(error, "codex_error_info"),
       will_retry: Map.get(params, "willRetry") || Map.get(params, "will_retry"),
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

  def to_event("thread/status/changed", %{} = params) do
    {:ok,
     %Events.ThreadStatusChanged{
       thread_id: fetch(params, "threadId", "thread_id") || "",
       status: normalize_thread_status(Map.get(params, "status"))
     }}
  end

  def to_event("thread/archived", %{} = params) do
    {:ok,
     %Events.ThreadArchived{
       thread_id: fetch(params, "threadId", "thread_id") || ""
     }}
  end

  def to_event("thread/unarchived", %{} = params) do
    {:ok,
     %Events.ThreadUnarchived{
       thread_id: fetch(params, "threadId", "thread_id") || ""
     }}
  end

  def to_event("skills/changed", %{} = _params) do
    {:ok, %Events.SkillsChanged{}}
  end

  def to_event("thread/name/updated", %{} = params) do
    {:ok,
     %Events.ThreadNameUpdated{
       thread_id: fetch(params, "threadId", "thread_id") || "",
       thread_name: Map.get(params, "threadName")
     }}
  end

  def to_event("sessionConfigured", %{} = params) do
    initial_messages =
      params
      |> Map.get("initialMessages")
      |> normalize_initial_messages()

    {:ok,
     %Events.SessionConfigured{
       session_id: Map.get(params, "sessionId"),
       forked_from_id: Map.get(params, "forkedFromId") || Map.get(params, "forked_from_id"),
       model: Map.get(params, "model"),
       model_provider_id:
         Map.get(params, "modelProviderId") || Map.get(params, "model_provider_id"),
       approval_policy: Map.get(params, "approvalPolicy") || Map.get(params, "approval_policy"),
       approvals_reviewer:
         params
         |> Map.get("approvalsReviewer", Map.get(params, "approvals_reviewer"))
         |> normalize_approvals_reviewer(),
       sandbox_policy: Map.get(params, "sandboxPolicy") || Map.get(params, "sandbox_policy"),
       cwd: Map.get(params, "cwd"),
       reasoning_effort: Map.get(params, "reasoningEffort"),
       history_log_id: Map.get(params, "historyLogId"),
       history_entry_count: Map.get(params, "historyEntryCount"),
       initial_messages: initial_messages,
       rollout_path: Map.get(params, "rolloutPath")
     }}
  end

  def to_event("thread/tokenUsage/updated", %{} = params) do
    token_usage = Map.get(params, "tokenUsage") || %{}

    {:ok,
     %Events.ThreadTokenUsageUpdated{
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: fetch(params, "turnId", "turn_id"),
       usage: token_usage |> Map.get("total") |> normalize_token_usage_breakdown(),
       delta: token_usage |> Map.get("last") |> normalize_token_usage_breakdown(),
       rate_limits:
         params
         |> Map.get("rateLimits")
         |> case do
           nil -> Map.get(params, "rate_limits")
           value -> value
         end
         |> normalize_rate_limits()
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

  def to_event("hook/started", %{} = params) do
    {:ok,
     %Events.HookStarted{
       thread_id: fetch(params, "threadId", "thread_id") || "",
       turn_id: fetch(params, "turnId", "turn_id"),
       run: Map.get(params, "run") || %{}
     }}
  end

  def to_event("turn/completed", %{} = params) do
    turn = Map.get(params, "turn") || %{}

    {:ok,
     %Events.TurnCompleted{
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: Map.get(turn, "id"),
       status: normalize_turn_status(Map.get(turn, "status")),
       error: Map.get(turn, "error")
     }}
  end

  def to_event("hook/completed", %{} = params) do
    {:ok,
     %Events.HookCompleted{
       thread_id: fetch(params, "threadId", "thread_id") || "",
       turn_id: fetch(params, "turnId", "turn_id"),
       run: Map.get(params, "run") || %{}
     }}
  end

  def to_event("item/autoApprovalReview/started", %{} = params) do
    {:ok,
     %Events.GuardianApprovalReviewStarted{
       thread_id: fetch(params, "threadId", "thread_id") || "",
       turn_id: fetch(params, "turnId", "turn_id") || "",
       review_id: fetch(params, "reviewId", "review_id"),
       target_item_id: fetch(params, "targetItemId", "target_item_id"),
       review: normalize_guardian_review(Map.get(params, "review")),
       action: Map.get(params, "action")
     }}
  end

  def to_event("item/autoApprovalReview/completed", %{} = params) do
    {:ok,
     %Events.GuardianApprovalReviewCompleted{
       thread_id: fetch(params, "threadId", "thread_id") || "",
       turn_id: fetch(params, "turnId", "turn_id") || "",
       review_id: fetch(params, "reviewId", "review_id"),
       target_item_id: fetch(params, "targetItemId", "target_item_id"),
       decision_source:
         params
         |> fetch("decisionSource", "decision_source")
         |> normalize_guardian_decision_source(),
       review: normalize_guardian_review(Map.get(params, "review")),
       action: Map.get(params, "action")
     }}
  end

  def to_event("serverRequest/resolved", %{} = params) do
    {:ok,
     %Events.ServerRequestResolved{
       thread_id: fetch(params, "threadId", "thread_id") || "",
       request_id: fetch(params, "requestId", "request_id")
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

  def to_event("rawResponseItem/completed", %{} = params) do
    item = Map.get(params, "item") || %{}

    parsed_item =
      case ItemAdapter.to_raw_item(item) do
        {:ok, parsed} -> parsed
        {:raw, raw} -> raw
      end

    {:ok,
     %Events.RawResponseItemCompleted{
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: fetch(params, "turnId", "turn_id"),
       item: parsed_item
     }}
  end

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

  def to_event("item/reasoning/summaryPartAdded", %{} = params) do
    {:ok,
     %Events.ReasoningSummaryPartAdded{
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: fetch(params, "turnId", "turn_id"),
       item_id: fetch(params, "itemId", "item_id") || "",
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

  def to_event("item/commandExecution/terminalInteraction", %{} = params) do
    {:ok,
     %Events.TerminalInteraction{
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: fetch(params, "turnId", "turn_id"),
       item_id: fetch(params, "itemId", "item_id") || "",
       process_id: Map.get(params, "processId"),
       stdin: Map.get(params, "stdin") || ""
     }}
  end

  def to_event("item/fileChange/outputDelta", %{} = params) do
    {:ok,
     %Events.FileChangeOutputDelta{
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: fetch(params, "turnId", "turn_id"),
       item_id: fetch(params, "itemId", "item_id") || "",
       delta: Map.get(params, "delta") || ""
     }}
  end

  def to_event("item/mcpToolCall/progress", %{} = params) do
    {:ok,
     %Events.McpToolCallProgress{
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: fetch(params, "turnId", "turn_id"),
       item_id: fetch(params, "itemId", "item_id") || "",
       message: Map.get(params, "message") || ""
     }}
  end

  def to_event("mcpServer/oauthLogin/completed", %{} = params) do
    {:ok,
     %Events.McpServerOauthLoginCompleted{
       name: Map.get(params, "name") || "",
       success: Map.get(params, "success") || false,
       error: Map.get(params, "error")
     }}
  end

  def to_event("account/updated", %{} = params) do
    {:ok,
     %Events.AccountUpdated{
       auth_mode: Map.get(params, "authMode") || Map.get(params, "auth_mode"),
       plan_type: normalize_plan_type(Map.get(params, "planType") || Map.get(params, "plan_type"))
     }}
  end

  def to_event("account/login/completed", %{} = params) do
    {:ok,
     %Events.AccountLoginCompleted{
       login_id: Map.get(params, "loginId") || Map.get(params, "login_id"),
       success: Map.get(params, "success") || false,
       error: Map.get(params, "error")
     }}
  end

  def to_event("account/rateLimits/updated", %{} = params) do
    rate_limits =
      params
      |> Map.get("rateLimits")
      |> case do
        nil -> Map.get(params, "rate_limits")
        value -> value
      end
      |> normalize_rate_limits()

    {:ok,
     %Events.AccountRateLimitsUpdated{
       rate_limits: rate_limits || %{},
       thread_id: fetch(params, "threadId", "thread_id"),
       turn_id: fetch(params, "turnId", "turn_id")
     }}
  end

  def to_event("windows/worldWritableWarning", %{} = params) do
    {:ok,
     %Events.WindowsWorldWritableWarning{
       sample_paths: Map.get(params, "samplePaths") || [],
       extra_count: Map.get(params, "extraCount") || 0,
       failed_scan: Map.get(params, "failedScan") || false
     }}
  end

  def to_event("deprecationNotice", %{} = params) do
    {:ok,
     %Events.DeprecationNotice{
       summary: Map.get(params, "summary") || "",
       details: Map.get(params, "details")
     }}
  end

  def to_event("app/list/updated", %{} = params) do
    {:ok,
     %Events.AppListUpdated{
       data: Map.get(params, "data") || []
     }}
  end

  def to_event("mcpServer/startupStatus/updated", %{} = params) do
    {:ok,
     %Events.McpServerStartupStatusUpdated{
       name: Map.get(params, "name") || "",
       status: normalize_mcp_server_startup_status(Map.get(params, "status")),
       error: Map.get(params, "error")
     }}
  end

  def to_event("model/rerouted", %{} = params) do
    {:ok,
     %Events.ModelRerouted{
       thread_id: fetch(params, "threadId", "thread_id") || "",
       turn_id: fetch(params, "turnId", "turn_id") || "",
       from_model: Map.get(params, "fromModel") || "",
       to_model: Map.get(params, "toModel") || "",
       reason: normalize_model_reroute_reason(Map.get(params, "reason"))
     }}
  end

  def to_event("configWarning", %{} = params) do
    {:ok,
     %Events.ConfigWarning{
       summary: Map.get(params, "summary") || "",
       details: Map.get(params, "details")
     }}
  end

  def to_event("fuzzyFileSearch/sessionUpdated", %{} = params) do
    {:ok,
     %Events.FuzzyFileSearchSessionUpdated{
       session_id: Map.get(params, "sessionId") || "",
       query: Map.get(params, "query") || "",
       files: Map.get(params, "files") || []
     }}
  end

  def to_event("fuzzyFileSearch/sessionCompleted", %{} = params) do
    {:ok,
     %Events.FuzzyFileSearchSessionCompleted{
       session_id: Map.get(params, "sessionId") || ""
     }}
  end

  def to_event("thread/realtime/started", %{} = params) do
    {:ok,
     %Events.ThreadRealtimeStarted{
       thread_id: fetch(params, "threadId", "thread_id") || "",
       session_id: Map.get(params, "sessionId")
     }}
  end

  def to_event("thread/realtime/itemAdded", %{} = params) do
    {:ok,
     %Events.ThreadRealtimeItemAdded{
       thread_id: fetch(params, "threadId", "thread_id") || "",
       item: Map.get(params, "item")
     }}
  end

  def to_event("thread/realtime/outputAudio/delta", %{} = params) do
    {:ok,
     %Events.ThreadRealtimeOutputAudioDelta{
       thread_id: fetch(params, "threadId", "thread_id") || "",
       audio: normalize_audio_chunk(Map.get(params, "audio"))
     }}
  end

  def to_event("thread/realtime/transcript/delta", %{} = params) do
    {:ok,
     %Events.ThreadRealtimeTranscriptDelta{
       thread_id: fetch(params, "threadId", "thread_id") || "",
       role: Map.get(params, "role") || "",
       delta: Map.get(params, "delta") || ""
     }}
  end

  def to_event("thread/realtime/transcript/done", %{} = params) do
    {:ok,
     %Events.ThreadRealtimeTranscriptDone{
       thread_id: fetch(params, "threadId", "thread_id") || "",
       role: Map.get(params, "role") || "",
       text: Map.get(params, "text") || ""
     }}
  end

  def to_event("thread/realtime/error", %{} = params) do
    {:ok,
     %Events.ThreadRealtimeError{
       thread_id: fetch(params, "threadId", "thread_id") || "",
       message: Map.get(params, "message") || ""
     }}
  end

  def to_event("thread/realtime/closed", %{} = params) do
    {:ok,
     %Events.ThreadRealtimeClosed{
       thread_id: fetch(params, "threadId", "thread_id") || "",
       reason: Map.get(params, "reason")
     }}
  end

  def to_event(method, %{} = params) when is_binary(method) do
    {:ok, %Events.AppServerNotification{method: method, params: params}}
  end

  def to_event(method, params) when is_binary(method) do
    {:ok, %Events.AppServerNotification{method: method, params: Map.new(params || %{})}}
  end

  defp normalize_initial_messages(nil), do: nil

  defp normalize_initial_messages(messages) when is_list(messages) do
    Enum.map(messages, fn
      %{} = message ->
        try do
          Events.parse!(message)
        rescue
          _ -> message
        end

      other ->
        other
    end)
  end

  defp normalize_initial_messages(_), do: nil

  defp normalize_rate_limits(nil), do: nil

  defp normalize_rate_limits(%RateLimitSnapshot{} = snapshot), do: snapshot

  defp normalize_rate_limits(%{} = snapshot) do
    RateLimitSnapshot.from_map(snapshot)
  rescue
    _ -> snapshot
  end

  defp normalize_rate_limits(_), do: nil

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

  defp normalize_approvals_reviewer("user"), do: :user
  defp normalize_approvals_reviewer("guardian_subagent"), do: :guardian_subagent
  defp normalize_approvals_reviewer(:user), do: :user
  defp normalize_approvals_reviewer(:guardian_subagent), do: :guardian_subagent
  defp normalize_approvals_reviewer(nil), do: nil
  defp normalize_approvals_reviewer(value), do: value

  defp normalize_guardian_review(%{} = review) do
    %Events.GuardianApprovalReview{
      status: normalize_guardian_review_status(Map.get(review, "status")),
      risk_score: Map.get(review, "riskScore") || Map.get(review, "risk_score"),
      risk_level:
        normalize_guardian_risk_level(
          Map.get(review, "riskLevel") || Map.get(review, "risk_level")
        ),
      rationale: Map.get(review, "rationale")
    }
  end

  defp normalize_guardian_review(_review) do
    %Events.GuardianApprovalReview{status: :in_progress}
  end

  defp normalize_guardian_review_status("inProgress"), do: :in_progress
  defp normalize_guardian_review_status("in_progress"), do: :in_progress
  defp normalize_guardian_review_status("approved"), do: :approved
  defp normalize_guardian_review_status("denied"), do: :denied
  defp normalize_guardian_review_status("timedOut"), do: :timed_out
  defp normalize_guardian_review_status("timed_out"), do: :timed_out
  defp normalize_guardian_review_status("aborted"), do: :aborted
  defp normalize_guardian_review_status(:in_progress), do: :in_progress
  defp normalize_guardian_review_status(:approved), do: :approved
  defp normalize_guardian_review_status(:denied), do: :denied
  defp normalize_guardian_review_status(:timed_out), do: :timed_out
  defp normalize_guardian_review_status(:aborted), do: :aborted
  defp normalize_guardian_review_status(_), do: :in_progress

  defp normalize_guardian_risk_level("low"), do: :low
  defp normalize_guardian_risk_level("medium"), do: :medium
  defp normalize_guardian_risk_level("high"), do: :high
  defp normalize_guardian_risk_level(:low), do: :low
  defp normalize_guardian_risk_level(:medium), do: :medium
  defp normalize_guardian_risk_level(:high), do: :high
  defp normalize_guardian_risk_level(_), do: nil

  defp normalize_guardian_decision_source("agent"), do: :agent
  defp normalize_guardian_decision_source(:agent), do: :agent
  defp normalize_guardian_decision_source(nil), do: nil
  defp normalize_guardian_decision_source(value), do: value

  defp normalize_thread_status(nil), do: nil

  defp normalize_thread_status(%{} = status) do
    case Map.get(status, "type") do
      "active" ->
        %{
          type: :active,
          active_flags:
            status
            |> Map.get("activeFlags", [])
            |> Enum.map(&normalize_thread_active_flag/1)
        }

      "notLoaded" ->
        :not_loaded

      "systemError" ->
        :system_error

      other when is_binary(other) ->
        normalize_thread_status(other)

      _ ->
        status
    end
  end

  defp normalize_thread_status("notLoaded"), do: :not_loaded
  defp normalize_thread_status("idle"), do: :idle
  defp normalize_thread_status("systemError"), do: :system_error
  defp normalize_thread_status(other), do: other

  defp normalize_thread_active_flag("waitingOnApproval"), do: :waiting_on_approval
  defp normalize_thread_active_flag("waitingOnUserInput"), do: :waiting_on_user_input
  defp normalize_thread_active_flag(flag), do: flag

  defp normalize_plan_type(nil), do: nil
  defp normalize_plan_type("plus"), do: :plus
  defp normalize_plan_type("pro"), do: :pro
  defp normalize_plan_type("team"), do: :team
  defp normalize_plan_type("enterprise"), do: :enterprise
  defp normalize_plan_type("api"), do: :api
  defp normalize_plan_type(value), do: value

  defp normalize_model_reroute_reason("highRiskCyberActivity"), do: :high_risk_cyber_activity
  defp normalize_model_reroute_reason(value), do: value

  defp normalize_mcp_server_startup_status("starting"), do: :starting
  defp normalize_mcp_server_startup_status("ready"), do: :ready
  defp normalize_mcp_server_startup_status("failed"), do: :failed
  defp normalize_mcp_server_startup_status("cancelled"), do: :cancelled
  defp normalize_mcp_server_startup_status(value) when is_atom(value), do: value
  defp normalize_mcp_server_startup_status(value) when is_binary(value), do: value
  defp normalize_mcp_server_startup_status(_), do: nil

  defp normalize_audio_chunk(nil), do: %{}

  defp normalize_audio_chunk(%{} = chunk) do
    %{}
    |> put_present("data", Map.get(chunk, "data"))
    |> put_present("sample_rate", Map.get(chunk, "sampleRate"))
    |> put_present("num_channels", Map.get(chunk, "numChannels"))
    |> put_present("samples_per_channel", Map.get(chunk, "samplesPerChannel"))
  end

  defp normalize_audio_chunk(other), do: other

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)
end

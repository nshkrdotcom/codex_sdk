defmodule Codex.Protocol.Ops do
  @moduledoc """
  Encoders for Codex protocol operations submitted to the runtime.
  """

  use TypedStruct

  alias Codex.Models

  alias Codex.Protocol.{
    ByteRange,
    CollaborationMode,
    ConfigTypes,
    Elicitation,
    RequestUserInput,
    TextElement
  }

  @type op_type ::
          :interrupt
          | :user_input
          | :user_turn
          | :override_turn_context
          | :exec_approval
          | :patch_approval
          | :resolve_elicitation
          | :user_input_answer
          | :add_to_history
          | :get_history_entry_request
          | :list_mcp_tools
          | :refresh_mcp_servers
          | :list_custom_prompts
          | :list_skills
          | :compact
          | :undo
          | :thread_rollback
          | :review
          | :shutdown
          | :run_user_shell_command
          | :list_models

  @type review_decision ::
          :approved
          | :approved_for_session
          | :denied
          | :abort
          | {:approved_execpolicy_amendment, term()}

  typedstruct do
    @typedoc "Operation payload wrapper."
    field(:type, op_type(), enforce: true)
    field(:payload, map(), default: %{})
  end

  @doc """
  Builds a protocol operation wrapper.
  """
  @spec new(op_type(), map()) :: t()
  def new(type, payload \\ %{}) when is_atom(type) and is_map(payload) do
    %__MODULE__{type: type, payload: payload}
  end

  @doc """
  Encodes an operation into a protocol map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{type: type, payload: payload}) do
    encode_op(type, payload)
  end

  defp encode_op(:interrupt, _payload) do
    %{"type" => "interrupt"}
  end

  defp encode_op(:user_input, payload) do
    %{"type" => "user_input"}
    |> put_optional("items", encode_user_input_items(fetch_any(payload, [:items, "items"])))
    |> put_optional(
      "final_output_json_schema",
      fetch_any(payload, [
        :final_output_json_schema,
        "final_output_json_schema",
        :output_schema,
        "output_schema"
      ])
    )
  end

  defp encode_op(:user_turn, payload) do
    %{"type" => "user_turn"}
    |> put_optional("items", encode_user_input_items(fetch_any(payload, [:items, "items"])))
    |> put_optional("cwd", fetch_any(payload, [:cwd, "cwd"]))
    |> put_optional(
      "approval_policy",
      payload
      |> fetch_any([:approval_policy, "approval_policy", :ask_for_approval, "ask_for_approval"])
      |> encode_approval_policy()
    )
    |> put_optional(
      "sandbox_policy",
      payload |> fetch_any([:sandbox_policy, "sandbox_policy"]) |> encode_sandbox_policy()
    )
    |> put_optional("model", fetch_any(payload, [:model, "model"]))
    |> put_optional(
      "effort",
      payload
      |> fetch_any([:effort, "effort", :reasoning_effort, "reasoning_effort"])
      |> encode_reasoning_effort()
    )
    |> put_optional("summary", fetch_any(payload, [:summary, "summary"]))
    |> put_optional(
      "final_output_json_schema",
      fetch_any(payload, [
        :final_output_json_schema,
        "final_output_json_schema",
        :output_schema,
        "output_schema"
      ])
    )
    |> put_optional(
      "collaboration_mode",
      payload
      |> fetch_any([:collaboration_mode, "collaboration_mode"])
      |> encode_collaboration_mode()
    )
    |> put_optional(
      "personality",
      payload |> fetch_any([:personality, "personality"]) |> encode_personality()
    )
  end

  defp encode_op(:override_turn_context, payload) do
    effort = encode_override_effort(payload)

    %{"type" => "override_turn_context"}
    |> put_optional("cwd", fetch_any(payload, [:cwd, "cwd"]))
    |> put_optional(
      "approval_policy",
      payload
      |> fetch_any([:approval_policy, "approval_policy", :ask_for_approval, "ask_for_approval"])
      |> encode_approval_policy()
    )
    |> put_optional(
      "sandbox_policy",
      payload |> fetch_any([:sandbox_policy, "sandbox_policy"]) |> encode_sandbox_policy()
    )
    |> put_optional("model", fetch_any(payload, [:model, "model"]))
    |> put_present("effort", effort)
    |> put_optional("summary", fetch_any(payload, [:summary, "summary"]))
    |> put_optional(
      "collaboration_mode",
      payload
      |> fetch_any([:collaboration_mode, "collaboration_mode"])
      |> encode_collaboration_mode()
    )
    |> put_optional(
      "personality",
      payload |> fetch_any([:personality, "personality"]) |> encode_personality()
    )
  end

  defp encode_op(:exec_approval, payload) do
    %{"type" => "exec_approval"}
    |> put_optional("id", fetch_any(payload, [:id, "id"]))
    |> put_optional(
      "decision",
      payload |> fetch_any([:decision, "decision"]) |> encode_review_decision()
    )
  end

  defp encode_op(:patch_approval, payload) do
    %{"type" => "patch_approval"}
    |> put_optional("id", fetch_any(payload, [:id, "id"]))
    |> put_optional(
      "decision",
      payload |> fetch_any([:decision, "decision"]) |> encode_review_decision()
    )
  end

  defp encode_op(:resolve_elicitation, payload) do
    %{"type" => "resolve_elicitation"}
    |> put_optional(
      "server_name",
      fetch_any(payload, [:server_name, "server_name", :serverName, "serverName"])
    )
    |> put_optional("request_id", fetch_any(payload, [:request_id, "request_id", :id, "id"]))
    |> put_optional(
      "decision",
      payload |> fetch_any([:decision, "decision"]) |> encode_elicitation_action()
    )
  end

  defp encode_op(:user_input_answer, payload) do
    %{"type" => "user_input_answer"}
    |> put_optional("id", fetch_any(payload, [:id, "id"]))
    |> put_optional(
      "response",
      payload |> fetch_any([:response, "response"]) |> encode_request_user_input_response()
    )
  end

  defp encode_op(:add_to_history, payload) do
    %{"type" => "add_to_history"}
    |> put_optional("text", fetch_any(payload, [:text, "text"]))
  end

  defp encode_op(:get_history_entry_request, payload) do
    %{"type" => "get_history_entry_request"}
    |> put_optional("offset", fetch_any(payload, [:offset, "offset"]))
    |> put_optional("log_id", fetch_any(payload, [:log_id, "log_id", :logId, "logId"]))
  end

  defp encode_op(:list_mcp_tools, _payload) do
    %{"type" => "list_mcp_tools"}
  end

  defp encode_op(:refresh_mcp_servers, payload) do
    %{"type" => "refresh_mcp_servers"}
    |> put_optional("config", fetch_any(payload, [:config, "config"]))
  end

  defp encode_op(:list_custom_prompts, _payload) do
    %{"type" => "list_custom_prompts"}
  end

  defp encode_op(:list_skills, payload) do
    cwds = payload |> fetch_any([:cwds, "cwds"]) |> List.wrap()

    %{"type" => "list_skills"}
    |> put_optional("cwds", cwds)
    |> put_optional_true("force_reload", fetch_any(payload, [:force_reload, "force_reload"]))
  end

  defp encode_op(:compact, _payload) do
    %{"type" => "compact"}
  end

  defp encode_op(:undo, _payload) do
    %{"type" => "undo"}
  end

  defp encode_op(:thread_rollback, payload) do
    %{"type" => "thread_rollback"}
    |> put_optional(
      "num_turns",
      fetch_any(payload, [:num_turns, "num_turns", :numTurns, "numTurns"])
    )
  end

  defp encode_op(:review, payload) do
    %{"type" => "review"}
    |> put_optional(
      "review_request",
      fetch_any(payload, [:review_request, "review_request", :reviewRequest, "reviewRequest"])
    )
  end

  defp encode_op(:shutdown, _payload) do
    %{"type" => "shutdown"}
  end

  defp encode_op(:run_user_shell_command, payload) do
    %{"type" => "run_user_shell_command"}
    |> put_optional("command", fetch_any(payload, [:command, "command"]))
  end

  defp encode_op(:list_models, _payload) do
    %{"type" => "list_models"}
  end

  defp encode_op(type, _payload) do
    raise ArgumentError, "unsupported op type: #{inspect(type)}"
  end

  defp encode_user_input_items(nil), do: nil

  defp encode_user_input_items(items) when is_binary(items) do
    [encode_user_input_text(items, nil)]
  end

  defp encode_user_input_items(items) when is_list(items) do
    Enum.map(items, &encode_user_input_item/1)
  end

  defp encode_user_input_items(other) do
    [encode_user_input_item(other)]
  end

  defp encode_user_input_item(text) when is_binary(text) do
    encode_user_input_text(text, nil)
  end

  defp encode_user_input_item(%{} = item) do
    item = stringify_keys(item)
    type = normalize_user_input_type(Map.get(item, "type"))

    case type do
      "text" ->
        encode_text_item(item)

      "image" ->
        encode_image_item(item)

      "local_image" ->
        encode_local_image_item(item)

      "skill" ->
        encode_skill_item(item)

      nil ->
        encode_user_input_text(Map.get(item, "text") || "", nil)

      other ->
        Map.put(item, "type", other)
    end
  end

  defp encode_text_item(%{} = item) do
    encode_user_input_text(
      Map.get(item, "text") || "",
      fetch_any(item, ["text_elements", "textElements"])
    )
  end

  defp encode_image_item(%{} = item) do
    %{
      "type" => "image",
      "image_url" => fetch_any(item, ["image_url", "imageUrl", "url"]) || ""
    }
  end

  defp encode_local_image_item(%{} = item) do
    %{
      "type" => "local_image",
      "path" => Map.get(item, "path") || ""
    }
  end

  defp encode_skill_item(%{} = item) do
    %{
      "type" => "skill",
      "name" => Map.get(item, "name") || "",
      "path" => Map.get(item, "path") || ""
    }
  end

  defp encode_user_input_text(text, elements) do
    %{"type" => "text", "text" => text}
    |> put_optional("text_elements", encode_text_elements(elements))
  end

  defp encode_text_elements(nil), do: nil

  defp encode_text_elements(elements) when is_list(elements) do
    elements
    |> Enum.map(&encode_text_element/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      list -> list
    end
  end

  defp encode_text_elements(_), do: nil

  defp encode_text_element(%TextElement{} = element) do
    TextElement.to_map(element)
  end

  defp encode_text_element(%{} = element) do
    element = stringify_keys(element)

    byte_range =
      element
      |> fetch_any(["byte_range", "byteRange"])
      |> encode_byte_range()

    %{}
    |> put_optional("byte_range", byte_range)
    |> put_optional("placeholder", Map.get(element, "placeholder"))
    |> case do
      %{} = map when map_size(map) == 0 -> nil
      %{} = map -> map
    end
  end

  defp encode_text_element(_), do: nil

  defp encode_byte_range(%ByteRange{} = range) do
    ByteRange.to_map(range)
  end

  defp encode_byte_range(%{} = range) do
    range = stringify_keys(range)

    %{}
    |> put_optional("start", fetch_any(range, ["start"]))
    |> put_optional("end", fetch_any(range, ["end"]))
    |> case do
      %{} = map when map_size(map) == 0 -> nil
      %{} = map -> map
    end
  end

  defp encode_byte_range(_), do: nil

  defp normalize_user_input_type(nil), do: nil

  defp normalize_user_input_type(value) when is_atom(value),
    do: normalize_user_input_type(Atom.to_string(value))

  defp normalize_user_input_type(value) when is_binary(value) do
    case value do
      "localImage" -> "local_image"
      "local_image" -> "local_image"
      "local-image" -> "local_image"
      other -> other
    end
  end

  defp normalize_user_input_type(_), do: nil

  defp encode_review_decision(nil), do: nil

  defp encode_review_decision({:approved_execpolicy_amendment, amendment}) do
    %{
      "approved_execpolicy_amendment" => %{
        "proposed_execpolicy_amendment" => encode_execpolicy_amendment(amendment)
      }
    }
  end

  defp encode_review_decision(:approved), do: "approved"
  defp encode_review_decision(:approved_for_session), do: "approved_for_session"
  defp encode_review_decision(:denied), do: "denied"
  defp encode_review_decision(:abort), do: "abort"
  defp encode_review_decision(:allow), do: "approved"
  defp encode_review_decision(:decline), do: "denied"
  defp encode_review_decision(:cancel), do: "abort"
  defp encode_review_decision("approved"), do: "approved"
  defp encode_review_decision("approved_for_session"), do: "approved_for_session"
  defp encode_review_decision("denied"), do: "denied"
  defp encode_review_decision("abort"), do: "abort"

  defp encode_review_decision({:allow, opts}) when is_list(opts) do
    cond do
      amendment = Keyword.get(opts, :execpolicy_amendment) ->
        encode_review_decision({:approved_execpolicy_amendment, amendment})

      Keyword.get(opts, :for_session, false) ->
        "approved_for_session"

      Keyword.get(opts, :grant_root) not in [nil, false] ->
        "approved_for_session"

      true ->
        "approved"
    end
  end

  defp encode_review_decision({:deny, reason}) when reason in [:cancel, "cancel"], do: "abort"
  defp encode_review_decision({:deny, _reason}), do: "denied"

  defp encode_review_decision(%{} = decision), do: decision
  defp encode_review_decision(other), do: other

  defp encode_execpolicy_amendment(nil), do: nil

  defp encode_execpolicy_amendment(%{} = amendment) do
    amendment
    |> fetch_any([:command, "command"])
    |> encode_execpolicy_amendment()
  end

  defp encode_execpolicy_amendment(commands) when is_list(commands), do: commands
  defp encode_execpolicy_amendment(command) when is_binary(command), do: [command]
  defp encode_execpolicy_amendment(_), do: nil

  defp encode_elicitation_action(nil), do: nil

  defp encode_elicitation_action(action) when is_atom(action),
    do: Elicitation.encode_action(action)

  defp encode_elicitation_action(action) when is_binary(action), do: action
  defp encode_elicitation_action(_), do: nil

  defp encode_request_user_input_response(nil), do: nil

  defp encode_request_user_input_response(%RequestUserInput.Response{} = response) do
    RequestUserInput.Response.to_map(response)
  end

  defp encode_request_user_input_response(%{} = response) do
    response = stringify_keys(response)
    answers = Map.get(response, "answers") || %{}

    encoded =
      answers
      |> Enum.map(fn {id, answer} -> {id, encode_request_user_input_answer(answer)} end)
      |> Map.new()

    %{"answers" => encoded}
  end

  defp encode_request_user_input_response(other), do: other

  defp encode_request_user_input_answer(%RequestUserInput.Answer{} = answer) do
    RequestUserInput.Answer.to_map(answer)
  end

  defp encode_request_user_input_answer(%{} = answer) do
    answer = stringify_keys(answer)
    answers = Map.get(answer, "answers") || []
    %{"answers" => List.wrap(answers)}
  end

  defp encode_request_user_input_answer(answers) when is_list(answers) do
    %{"answers" => answers}
  end

  defp encode_request_user_input_answer(answer) when is_binary(answer) do
    %{"answers" => [answer]}
  end

  defp encode_request_user_input_answer(other), do: other

  defp encode_collaboration_mode(nil), do: nil
  defp encode_collaboration_mode(%CollaborationMode{} = mode), do: CollaborationMode.to_map(mode)
  defp encode_collaboration_mode(%{} = mode), do: mode
  defp encode_collaboration_mode(other), do: other

  defp encode_personality(nil), do: nil
  defp encode_personality(value) when is_atom(value), do: ConfigTypes.encode_personality(value)
  defp encode_personality(value) when is_binary(value), do: value
  defp encode_personality(_), do: nil

  defp encode_reasoning_effort(nil), do: nil

  defp encode_reasoning_effort(value) when is_atom(value) do
    Models.reasoning_effort_to_string(value)
  rescue
    _ -> Atom.to_string(value)
  end

  defp encode_reasoning_effort(value) when is_binary(value), do: value
  defp encode_reasoning_effort(_), do: nil

  defp encode_override_effort(payload) do
    keys = [:effort, "effort", :reasoning_effort, "reasoning_effort"]
    {present?, value} = fetch_optional(payload, keys)

    if present? do
      case value do
        :clear -> nil
        "clear" -> nil
        other -> encode_reasoning_effort(other)
      end
    else
      :missing
    end
  end

  defp encode_approval_policy(nil), do: nil
  defp encode_approval_policy(:untrusted), do: "untrusted"
  defp encode_approval_policy(:on_failure), do: "on-failure"
  defp encode_approval_policy(:on_request), do: "on-request"
  defp encode_approval_policy(:never), do: "never"
  defp encode_approval_policy("untrusted"), do: "untrusted"
  defp encode_approval_policy("on-failure"), do: "on-failure"
  defp encode_approval_policy("on-request"), do: "on-request"
  defp encode_approval_policy("never"), do: "never"
  defp encode_approval_policy(value) when is_binary(value), do: value
  defp encode_approval_policy(_), do: nil

  defp encode_sandbox_policy(nil), do: nil
  defp encode_sandbox_policy(%{} = policy), do: normalize_sandbox_policy(policy)

  defp encode_sandbox_policy(policy) when is_atom(policy) or is_binary(policy) do
    %{"type" => normalize_sandbox_type(policy)}
  end

  defp encode_sandbox_policy(_), do: nil

  defp normalize_sandbox_policy(policy) do
    policy = stringify_keys(policy)

    %{}
    |> put_optional("type", normalize_sandbox_type(Map.get(policy, "type")))
    |> put_optional(
      "writable_roots",
      fetch_any(policy, ["writable_roots", "writableRoots"])
    )
    |> put_optional(
      "network_access",
      fetch_any(policy, ["network_access", "networkAccess"])
    )
    |> put_optional(
      "exclude_tmpdir_env_var",
      fetch_any(policy, ["exclude_tmpdir_env_var", "excludeTmpdirEnvVar"])
    )
    |> put_optional(
      "exclude_slash_tmp",
      fetch_any(policy, ["exclude_slash_tmp", "excludeSlashTmp"])
    )
    |> case do
      %{} = map when map_size(map) == 0 -> nil
      %{} = map -> map
    end
  end

  defp normalize_sandbox_type(nil), do: nil
  defp normalize_sandbox_type(:read_only), do: "read-only"
  defp normalize_sandbox_type("read_only"), do: "read-only"
  defp normalize_sandbox_type("read-only"), do: "read-only"
  defp normalize_sandbox_type("readOnly"), do: "read-only"
  defp normalize_sandbox_type(:workspace_write), do: "workspace-write"
  defp normalize_sandbox_type("workspace_write"), do: "workspace-write"
  defp normalize_sandbox_type("workspace-write"), do: "workspace-write"
  defp normalize_sandbox_type("workspaceWrite"), do: "workspace-write"
  defp normalize_sandbox_type(:danger_full_access), do: "danger-full-access"
  defp normalize_sandbox_type("danger_full_access"), do: "danger-full-access"
  defp normalize_sandbox_type("danger-full-access"), do: "danger-full-access"
  defp normalize_sandbox_type("dangerFullAccess"), do: "danger-full-access"
  defp normalize_sandbox_type(:external_sandbox), do: "external-sandbox"
  defp normalize_sandbox_type("external_sandbox"), do: "external-sandbox"
  defp normalize_sandbox_type("external-sandbox"), do: "external-sandbox"
  defp normalize_sandbox_type("externalSandbox"), do: "external-sandbox"
  defp normalize_sandbox_type(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_sandbox_type(value) when is_binary(value), do: value
  defp normalize_sandbox_type(_), do: nil

  defp fetch_any(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end

  defp fetch_any(_map, _keys), do: nil

  defp fetch_optional(map, keys) when is_map(map) and is_list(keys) do
    Enum.reduce_while(keys, {false, nil}, fn key, _acc ->
      if Map.has_key?(map, key) do
        {:halt, {true, Map.get(map, key)}}
      else
        {:cont, {false, nil}}
      end
    end)
  end

  defp fetch_optional(_map, _keys), do: {false, nil}

  defp stringify_keys(%{} = map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, _key, []), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp put_optional_true(map, key, value) when value in [true, "true"],
    do: Map.put(map, key, true)

  defp put_optional_true(map, _key, _value), do: map

  defp put_present(map, _key, :missing), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)
end

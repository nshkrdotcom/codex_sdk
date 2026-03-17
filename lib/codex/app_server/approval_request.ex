defmodule Codex.AppServer.ApprovalRequest do
  @moduledoc false

  alias Codex.Protocol.RequestPermissions

  def command_fields(%{} = params) do
    %{
      thread_id: fetch_any(params, ["threadId", "thread_id"]) || "",
      turn_id: fetch_any(params, ["turnId", "turn_id"]) || "",
      item_id: fetch_any(params, ["itemId", "item_id"]) || "",
      approval_id: fetch_any(params, ["approvalId", "approval_id"]),
      reason: fetch_any(params, ["reason", :reason]),
      command: fetch_any(params, ["command", :command]),
      cwd: fetch_any(params, ["cwd", :cwd]),
      command_actions:
        params
        |> fetch_any(["commandActions", "command_actions", :commandActions, :command_actions])
        |> deep_stringify_keys(),
      network_approval_context:
        params
        |> fetch_any([
          "networkApprovalContext",
          "network_approval_context",
          :networkApprovalContext,
          :network_approval_context
        ])
        |> deep_stringify_keys(),
      additional_permissions:
        params
        |> fetch_any([
          "additionalPermissions",
          "additional_permissions",
          :additionalPermissions,
          :additional_permissions
        ])
        |> RequestPermissions.RequestPermissionProfile.from_map(),
      skill_metadata:
        params
        |> fetch_any(["skillMetadata", "skill_metadata", :skillMetadata, :skill_metadata])
        |> deep_stringify_keys(),
      proposed_execpolicy_amendment:
        fetch_any(params, [
          "proposedExecpolicyAmendment",
          "proposed_execpolicy_amendment",
          :proposedExecpolicyAmendment,
          :proposed_execpolicy_amendment
        ]),
      proposed_network_policy_amendments:
        params
        |> fetch_any([
          "proposedNetworkPolicyAmendments",
          "proposed_network_policy_amendments",
          :proposedNetworkPolicyAmendments,
          :proposed_network_policy_amendments
        ])
        |> deep_stringify_keys(),
      available_decisions:
        params
        |> fetch_any([
          "availableDecisions",
          "available_decisions",
          :availableDecisions,
          :available_decisions
        ])
        |> deep_stringify_keys()
    }
  end

  def file_fields(%{} = params) do
    %{
      thread_id: fetch_any(params, ["threadId", "thread_id"]) || "",
      turn_id: fetch_any(params, ["turnId", "turn_id"]) || "",
      item_id: fetch_any(params, ["itemId", "item_id"]) || "",
      reason: fetch_any(params, ["reason", :reason]),
      grant_root: fetch_any(params, ["grantRoot", "grant_root", :grantRoot, :grant_root])
    }
  end

  def permissions_fields(%{} = params) do
    %{
      thread_id: fetch_any(params, ["threadId", "thread_id"]) || "",
      turn_id: fetch_any(params, ["turnId", "turn_id"]) || "",
      item_id: fetch_any(params, ["itemId", "item_id"]) || "",
      reason: fetch_any(params, ["reason", :reason]),
      permissions:
        params
        |> fetch_any(["permissions", :permissions])
        |> RequestPermissions.RequestPermissionProfile.from_map()
    }
  end

  @spec fetch_any(map(), [atom() | String.t()]) :: term()
  def fetch_any(%{} = map, keys) when is_list(keys) do
    Enum.reduce_while(keys, nil, fn key, _acc ->
      if Map.has_key?(map, key) do
        {:halt, Map.get(map, key)}
      else
        {:cont, nil}
      end
    end)
  end

  @spec deep_stringify_keys(term()) :: term()
  def deep_stringify_keys(nil), do: nil

  def deep_stringify_keys(%{} = map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), deep_stringify_keys(value)} end)
    |> Map.new()
  end

  def deep_stringify_keys(list) when is_list(list), do: Enum.map(list, &deep_stringify_keys/1)
  def deep_stringify_keys(other), do: other
end

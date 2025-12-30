defmodule Codex.AppServer.ApprovalDecision do
  @moduledoc false

  @type wire_decision :: String.t() | map()

  @spec from_hook(term()) :: wire_decision()
  def from_hook(:allow), do: "accept"

  def from_hook({:allow, opts}) when is_list(opts) do
    cond do
      Keyword.get(opts, :for_session, false) ->
        "acceptForSession"

      Keyword.get(opts, :grant_root) not in [nil, false] ->
        "acceptForSession"

      execpolicy_amendment = Keyword.get(opts, :execpolicy_amendment) ->
        %{
          "acceptWithExecpolicyAmendment" => %{
            "execpolicyAmendment" => List.wrap(execpolicy_amendment)
          }
        }

      true ->
        "accept"
    end
  end

  def from_hook({:deny, reason}) when reason in [:cancel, "cancel"], do: "cancel"
  def from_hook({:deny, _reason}), do: "decline"

  def from_hook(other) when other in [:decline, :cancel, "decline", "cancel"] do
    to_string(other)
  end

  def from_hook(_), do: "decline"
end

defmodule Codex.AppServer.ApprovalDecisionTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer.ApprovalDecision

  describe "from_hook/1" do
    test "encodes :allow as accept" do
      assert "accept" == ApprovalDecision.from_hook(:allow)
    end

    test "encodes allow-for-session decision" do
      assert "acceptForSession" == ApprovalDecision.from_hook({:allow, for_session: true})
    end

    test "encodes acceptWithExecpolicyAmendment decision" do
      assert %{
               "acceptWithExecpolicyAmendment" => %{
                 "execpolicyAmendment" => ["npm", "install"]
               }
             } ==
               ApprovalDecision.from_hook({:allow, execpolicy_amendment: ["npm", "install"]})
    end

    test "encodes deny decision as decline" do
      assert "decline" == ApprovalDecision.from_hook({:deny, "nope"})
    end
  end
end

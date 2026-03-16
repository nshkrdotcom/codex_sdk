defmodule Codex.AppServer.ApprovalDecisionTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer.ApprovalDecision
  alias Codex.Protocol.RequestPermissions

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

    test "encodes grant root approvals as acceptForSession" do
      assert "acceptForSession" ==
               ApprovalDecision.from_hook({:allow, grant_root: "/tmp"})
    end

    test "encodes deny decision as decline" do
      assert "decline" == ApprovalDecision.from_hook({:deny, "nope"})
    end

    test "encodes cancel decisions" do
      assert "cancel" == ApprovalDecision.from_hook({:deny, :cancel})
      assert "cancel" == ApprovalDecision.from_hook(:cancel)
    end
  end

  describe "from_permissions_hook/2" do
    test "grants the full requested profile for allow decisions" do
      requested =
        RequestPermissions.RequestPermissionProfile.from_map(%{
          "network" => %{"enabled" => true},
          "fileSystem" => %{
            "read" => ["/tmp/read-only"],
            "write" => ["/tmp/project"]
          }
        })

      assert %{
               "permissions" => %{
                 "network" => %{"enabled" => true},
                 "fileSystem" => %{
                   "read" => ["/tmp/read-only"],
                   "write" => ["/tmp/project"]
                 }
               },
               "scope" => "turn"
             } = ApprovalDecision.from_permissions_hook(:allow, requested)
    end

    test "intersects partial session grants with the originally requested profile" do
      requested =
        RequestPermissions.RequestPermissionProfile.from_map(%{
          "network" => %{"enabled" => true},
          "fileSystem" => %{
            "read" => ["/tmp/read-only"],
            "write" => ["/tmp/project", "/tmp/other"]
          }
        })

      decision =
        {:allow,
         permissions: %{
           network: %{enabled: true},
           file_system: %{read: ["/tmp/read-only", "/tmp/outside"], write: ["/tmp/project"]}
         },
         scope: :session}

      assert %{
               "permissions" => %{
                 "network" => %{"enabled" => true},
                 "fileSystem" => %{
                   "read" => ["/tmp/read-only"],
                   "write" => ["/tmp/project"]
                 }
               },
               "scope" => "session"
             } = ApprovalDecision.from_permissions_hook(decision, requested)
    end

    test "denials return an empty permission grant profile for the turn" do
      requested =
        RequestPermissions.RequestPermissionProfile.from_map(%{
          "network" => %{"enabled" => true}
        })

      assert %{"permissions" => %{}, "scope" => "turn"} ==
               ApprovalDecision.from_permissions_hook({:deny, "nope"}, requested)
    end
  end
end

defmodule Codex.Realtime.DiagnosticsTest do
  use ExUnit.Case, async: true

  alias Codex.Realtime.Diagnostics

  describe "extract_session_id/1" do
    test "extracts the session id from a map error payload" do
      error = %{
        "type" => "server_error",
        "message" =>
          "Please contact support with session ID in your message: sess_DLIJDJVh5Xwn7LWaBwnrD."
      }

      assert Diagnostics.extract_session_id(error) == "sess_DLIJDJVh5Xwn7LWaBwnrD"
    end

    test "returns nil when no session id is present" do
      assert Diagnostics.extract_session_id(%{"message" => "plain failure"}) == nil
    end
  end

  describe "skip_reason_for_error/1" do
    test "classifies quota failures" do
      assert Diagnostics.skip_reason_for_error(%{"type" => "insufficient_quota"}) ==
               "insufficient_quota"
    end

    test "classifies model access failures" do
      assert Diagnostics.skip_reason_for_error(%{"message" => "model_not_found"}) ==
               "realtime_model_unavailable"
    end

    test "classifies upstream server errors and preserves session id proof" do
      error = %{
        "type" => "server_error",
        "message" =>
          "The server had an error while processing your request. (include session ID in your message: sess_DLIJDJVh5Xwn7LWaBwnrD)."
      }

      assert Diagnostics.skip_reason_for_error(error) ==
               "realtime_upstream_server_error (session_id=sess_DLIJDJVh5Xwn7LWaBwnrD)"
    end
  end

  describe "format_probe_failure/1" do
    test "includes model, session id, events, and error message" do
      proof = %{
        model: "gpt-realtime",
        prompt: "Reply with exactly ok.",
        session_id: "sess_DLIJDJVh5Xwn7LWaBwnrD",
        session_created: nil,
        events: ["session.created", "error"],
        error: %{"message" => "The server had an error while processing your request."}
      }

      formatted = Diagnostics.format_probe_failure(proof)

      assert formatted =~ "gpt-realtime"
      assert formatted =~ "sess_DLIJDJVh5Xwn7LWaBwnrD"
      assert formatted =~ "session.created -> error"
      assert formatted =~ "The server had an error while processing your request."
    end
  end
end

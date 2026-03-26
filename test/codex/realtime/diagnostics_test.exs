defmodule Codex.Realtime.DiagnosticsTest do
  use ExUnit.Case, async: true

  alias Codex.Realtime.Diagnostics
  alias Codex.Realtime.ModelEvents

  defmodule ProbeWebSocket do
    use GenServer

    @spec start_link(keyword()) :: GenServer.on_start()
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    @spec send_message(pid(), map()) :: :ok
    def send_message(pid, message) when is_map(message) do
      GenServer.call(pid, {:send_message, message})
    end

    @spec close(pid()) :: :ok
    def close(pid) do
      GenServer.stop(pid, :normal)
      :ok
    end

    @impl true
    def init(opts) do
      session_pid = Keyword.fetch!(opts, :session_pid)
      test_pid = Keyword.fetch!(opts, :test_pid)

      send(
        session_pid,
        {:model_event,
         ModelEvents.raw_server_event(%{
           "type" => "session.created",
           "session" => %{"id" => "sess_probe_123"}
         })}
      )

      {:ok, %{session_pid: session_pid, test_pid: test_pid}}
    end

    @impl true
    def handle_call({:send_message, message}, _from, state) do
      send(state.test_pid, {:probe_sent, message})

      send(
        state.session_pid,
        {:model_event,
         ModelEvents.raw_server_event(%{
           "type" => "response.done",
           "response" => %{"status" => "completed"}
         })}
      )

      {:reply, :ok, state}
    end
  end

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

    test "classifies schema compatibility failures as protocol incompatibility" do
      assert Diagnostics.skip_reason_for_error(%{
               "type" => "invalid_request_error",
               "code" => "unknown_parameter",
               "message" => "Unknown parameter: 'response.output_modalities'."
             }) == "realtime_protocol_incompatible"
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

  describe "probe_text_turn/1" do
    test "sends a minimal probe without response.output_modalities" do
      assert {:ok, %{session_id: "sess_probe_123"}} =
               Diagnostics.probe_text_turn(
                 timeout_ms: 100,
                 websocket_module: ProbeWebSocket,
                 websocket_opts: [test_pid: self()]
               )

      assert_receive {:probe_sent, %{"type" => "response.create", "response" => response}}

      refute Map.has_key?(response, "output_modalities")
      assert response["conversation"] == "none"

      assert get_in(response, ["input", Access.at(0), "content", Access.at(0), "text"]) ==
               "Reply with exactly ok."
    end
  end
end

defmodule Codex.Config.DefaultsTest do
  use ExUnit.Case, async: false

  alias Codex.Config.Defaults

  setup do
    original_env = Application.get_all_env(:codex_sdk)

    on_exit(fn ->
      # Remove any keys we set during tests
      for {key, _val} <- Application.get_all_env(:codex_sdk),
          not Keyword.has_key?(original_env, key) do
        Application.delete_env(:codex_sdk, key)
      end

      # Restore original values
      for {key, val} <- original_env do
        Application.put_env(:codex_sdk, key, val)
      end
    end)

    :ok
  end

  # ── Transport timeouts ──────────────────────────────────────────────────

  describe "transport timeouts" do
    test "exec_timeout_ms/0 returns 3_600_000" do
      assert Defaults.exec_timeout_ms() == 3_600_000
    end

    test "transport_close_grace_ms/0 returns 2_000" do
      assert Defaults.transport_close_grace_ms() == 2_000
    end

    test "transport_shutdown_grace_ms/0 returns 250" do
      assert Defaults.transport_shutdown_grace_ms() == 250
    end

    test "transport_kill_grace_ms/0 returns 250" do
      assert Defaults.transport_kill_grace_ms() == 250
    end

    test "transport_max_buffer_size/0 returns 1_048_576" do
      assert Defaults.transport_max_buffer_size() == 1_048_576
    end

    test "transport_max_stderr_buffer_size/0 returns 262_144" do
      assert Defaults.transport_max_stderr_buffer_size() == 262_144
    end

    test "transport_call_timeout_ms/0 returns 5_000" do
      assert Defaults.transport_call_timeout_ms() == 5_000
    end

    test "transport_force_close_timeout_ms/0 returns 500" do
      assert Defaults.transport_force_close_timeout_ms() == 500
    end

    test "transport_headless_timeout_ms/0 returns 5_000" do
      assert Defaults.transport_headless_timeout_ms() == 5_000
    end

    test "transport_finalize_delay_ms/0 returns 25" do
      assert Defaults.transport_finalize_delay_ms() == 25
    end

    test "transport_max_lines_per_batch/0 returns 200" do
      assert Defaults.transport_max_lines_per_batch() == 200
    end
  end

  # ── MCP timeouts ────────────────────────────────────────────────────────

  describe "MCP timeouts" do
    test "mcp_init_timeout_ms/0 returns 10_000" do
      assert Defaults.mcp_init_timeout_ms() == 10_000
    end

    test "mcp_list_timeout_ms/0 returns 30_000" do
      assert Defaults.mcp_list_timeout_ms() == 30_000
    end

    test "mcp_call_timeout_ms/0 returns 60_000" do
      assert Defaults.mcp_call_timeout_ms() == 60_000
    end

    test "mcp_default_retries/0 returns 3" do
      assert Defaults.mcp_default_retries() == 3
    end

    test "mcp_notification_timeout_ms/0 returns 10_000" do
      assert Defaults.mcp_notification_timeout_ms() == 10_000
    end

    test "mcp_server_request_timeout_ms/0 returns 30_000" do
      assert Defaults.mcp_server_request_timeout_ms() == 30_000
    end
  end

  # ── App-server timeouts ─────────────────────────────────────────────────

  describe "app-server timeouts" do
    test "app_server_init_timeout_ms/0 returns 10_000" do
      assert Defaults.app_server_init_timeout_ms() == 10_000
    end

    test "app_server_request_timeout_ms/0 returns 30_000" do
      assert Defaults.app_server_request_timeout_ms() == 30_000
    end

    test "approval_timeout_ms/0 returns 30_000" do
      assert Defaults.approval_timeout_ms() == 30_000
    end
  end

  # ── Tool timeouts ───────────────────────────────────────────────────────

  describe "tool timeouts" do
    test "shell_timeout_ms/0 returns 60_000" do
      assert Defaults.shell_timeout_ms() == 60_000
    end

    test "shell_max_output_bytes/0 returns 10_000" do
      assert Defaults.shell_max_output_bytes() == 10_000
    end

    test "file_search_max_results/0 returns 100" do
      assert Defaults.file_search_max_results() == 100
    end

    test "web_search_max_results/0 returns 10" do
      assert Defaults.web_search_max_results() == 10
    end
  end

  # ── OAuth/HTTP timeouts ─────────────────────────────────────────────────

  describe "OAuth/HTTP timeouts" do
    test "oauth_http_timeout_ms/0 returns 10_000" do
      assert Defaults.oauth_http_timeout_ms() == 10_000
    end

    test "oauth_refresh_skew_ms/0 returns 30_000" do
      assert Defaults.oauth_refresh_skew_ms() == 30_000
    end

    test "remote_models_http_timeout_ms/0 returns 10_000" do
      assert Defaults.remote_models_http_timeout_ms() == 10_000
    end

    test "sessions_apply_timeout_ms/0 returns 60_000" do
      assert Defaults.sessions_apply_timeout_ms() == 60_000
    end
  end

  # ── Retry/backoff ───────────────────────────────────────────────────────

  describe "retry/backoff" do
    test "backoff_base_delay_ms/0 returns 100" do
      assert Defaults.backoff_base_delay_ms() == 100
    end

    test "backoff_max_ms/0 returns 5_000" do
      assert Defaults.backoff_max_ms() == 5_000
    end

    test "backoff_max_exponent/0 returns 20" do
      assert Defaults.backoff_max_exponent() == 20
    end

    test "retry_max_attempts/0 returns 4" do
      assert Defaults.retry_max_attempts() == 4
    end

    test "retry_base_delay_ms/0 returns 200" do
      assert Defaults.retry_base_delay_ms() == 200
    end

    test "retry_max_delay_ms/0 returns 10_000" do
      assert Defaults.retry_max_delay_ms() == 10_000
    end

    test "rate_limit_default_delay_ms/0 returns 60_000" do
      assert Defaults.rate_limit_default_delay_ms() == 60_000
    end

    test "rate_limit_max_delay_ms/0 returns 300_000" do
      assert Defaults.rate_limit_max_delay_ms() == 300_000
    end

    test "rate_limit_multiplier/0 returns 2.0" do
      assert Defaults.rate_limit_multiplier() == 2.0
    end
  end

  # ── Buffer/size limits ──────────────────────────────────────────────────

  describe "buffer/size limits" do
    test "stream_queue_pop_timeout_ms/0 returns 5_000" do
      assert Defaults.stream_queue_pop_timeout_ms() == 5_000
    end

    test "max_agent_turns/0 returns 10" do
      assert Defaults.max_agent_turns() == 10
    end
  end

  # ── URLs ────────────────────────────────────────────────────────────────

  describe "URLs" do
    test "openai_api_base_url/0 returns default API URL" do
      assert Defaults.openai_api_base_url() == "https://api.openai.com/v1"
    end

    test "openai_realtime_ws_url/0 returns WebSocket URL" do
      assert Defaults.openai_realtime_ws_url() == "wss://api.openai.com/v1/realtime"
    end

    test "sessions_dir/0 returns ~/.codex/sessions" do
      assert Defaults.sessions_dir() == Path.expand("~/.codex/sessions")
    end
  end

  # ── Model defaults ─────────────────────────────────────────────────────

  describe "model defaults" do
    test "default_api_model/0 returns gpt-5.3-codex" do
      assert Defaults.default_api_model() == "gpt-5.3-codex"
    end

    test "default_chatgpt_model/0 returns gpt-5.3-codex" do
      assert Defaults.default_chatgpt_model() == "gpt-5.3-codex"
    end

    test "remote_models_cache_ttl_seconds/0 returns 300" do
      assert Defaults.remote_models_cache_ttl_seconds() == 300
    end
  end

  # ── Protocol constants ──────────────────────────────────────────────────

  describe "protocol constants" do
    test "mcp_protocol_version/0 returns version string" do
      assert Defaults.mcp_protocol_version() == "2025-06-18"
    end

    test "jsonrpc_version/0 returns 2.0" do
      assert Defaults.jsonrpc_version() == "2.0"
    end

    test "mcp_tool_name_delimiter/0 returns __" do
      assert Defaults.mcp_tool_name_delimiter() == "__"
    end

    test "mcp_max_tool_name_length/0 returns 64" do
      assert Defaults.mcp_max_tool_name_length() == 64
    end
  end

  # ── File paths ──────────────────────────────────────────────────────────

  describe "file paths" do
    test "system_config_path/0 returns /etc/codex/config.toml" do
      assert Defaults.system_config_path() == "/etc/codex/config.toml"
    end

    test "project_root_markers/0 returns [\".git\"]" do
      assert Defaults.project_root_markers() == [".git"]
    end
  end

  # ── Files/attachments ──────────────────────────────────────────────────

  describe "files/attachments" do
    test "attachment_ttl_ms/0 returns 86_400_000" do
      assert Defaults.attachment_ttl_ms() == 86_400_000
    end

    test "attachment_cleanup_interval_ms/0 returns 60_000" do
      assert Defaults.attachment_cleanup_interval_ms() == 60_000
    end
  end

  # ── Audio/voice ─────────────────────────────────────────────────────────

  describe "audio/voice" do
    test "pcm16_sample_rate/0 returns 24_000" do
      assert Defaults.pcm16_sample_rate() == 24_000
    end

    test "pcm16_bytes_per_sample/0 returns 2" do
      assert Defaults.pcm16_bytes_per_sample() == 2
    end

    test "g711_sample_rate/0 returns 8_000" do
      assert Defaults.g711_sample_rate() == 8_000
    end

    test "g711_bytes_per_sample/0 returns 1" do
      assert Defaults.g711_bytes_per_sample() == 1
    end

    test "voice_default_sample_rate/0 returns 24_000" do
      assert Defaults.voice_default_sample_rate() == 24_000
    end

    test "tts_buffer_size/0 returns 120" do
      assert Defaults.tts_buffer_size() == 120
    end

    test "tts_stream_timeout_ms/0 returns 30_000" do
      assert Defaults.tts_stream_timeout_ms() == 30_000
    end

    test "stt_model/0 returns gpt-4o-transcribe" do
      assert Defaults.stt_model() == "gpt-4o-transcribe"
    end

    test "tts_model/0 returns gpt-4o-mini-tts" do
      assert Defaults.tts_model() == "gpt-4o-mini-tts"
    end

    test "tts_default_voice/0 returns :ash" do
      assert Defaults.tts_default_voice() == :ash
    end

    test "stt_default_turn_detection/0 returns semantic_vad map" do
      assert Defaults.stt_default_turn_detection() == %{"type" => "semantic_vad"}
    end
  end

  # ── Telemetry ───────────────────────────────────────────────────────────

  describe "telemetry" do
    test "telemetry_otel_handler_id/0 returns handler id" do
      assert Defaults.telemetry_otel_handler_id() == "codex-otel-tracing"
    end

    test "telemetry_default_originator/0 returns :sdk" do
      assert Defaults.telemetry_default_originator() == :sdk
    end

    test "telemetry_processor_name/0 returns :codex_sdk_processor" do
      assert Defaults.telemetry_processor_name() == :codex_sdk_processor
    end
  end

  # ── Client identity ────────────────────────────────────────────────────

  describe "client identity" do
    test "client_name/0 returns codex-elixir" do
      assert Defaults.client_name() == "codex-elixir"
    end

    test "client_version/0 returns version or 0.0.0" do
      version = Defaults.client_version()
      assert is_binary(version)
      # Should either be the app version or the fallback
      assert version =~ ~r/^\d+\.\d+\.\d+/
    end
  end

  # ── Preserved env keys ─────────────────────────────────────────────────

  describe "preserved env keys" do
    test "preserved_env_keys/0 returns list of env key strings" do
      keys = Defaults.preserved_env_keys()
      assert is_list(keys)
      assert "HOME" in keys
      assert "PATH" in keys
      assert "CODEX_HOME" in keys
      assert length(keys) == 10
    end
  end

  # ── Runtime overrides via Application.get_env ──────────────────────────

  describe "runtime overrides" do
    test "rate_limit_default_delay_ms can be overridden via app env" do
      Application.put_env(:codex_sdk, :rate_limit_default_delay_ms, 120_000)
      assert Defaults.rate_limit_default_delay_ms() == 120_000
    end

    test "rate_limit_max_delay_ms can be overridden via app env" do
      Application.put_env(:codex_sdk, :rate_limit_max_delay_ms, 600_000)
      assert Defaults.rate_limit_max_delay_ms() == 600_000
    end

    test "rate_limit_multiplier can be overridden via app env" do
      Application.put_env(:codex_sdk, :rate_limit_multiplier, 3.0)
      assert Defaults.rate_limit_multiplier() == 3.0
    end

    test "attachment_ttl_ms can be overridden via app env" do
      Application.put_env(:codex_sdk, :attachment_ttl_ms, 3_600_000)
      assert Defaults.attachment_ttl_ms() == 3_600_000
    end

    test "attachment_cleanup_interval_ms can be overridden via app env" do
      Application.put_env(:codex_sdk, :attachment_cleanup_interval_ms, 120_000)
      assert Defaults.attachment_cleanup_interval_ms() == 120_000
    end

    test "default_transport can be overridden via app env" do
      Application.put_env(:codex_sdk, :default_transport, :exec)
      assert Defaults.default_transport() == :exec
    end
  end

  # ── TTS instructions default ────────────────────────────────────────────

  describe "TTS instructions" do
    test "tts_default_instructions/0 returns instruction string" do
      instructions = Defaults.tts_default_instructions()
      assert is_binary(instructions)
      assert String.contains?(instructions, "partial sentences")
    end
  end
end

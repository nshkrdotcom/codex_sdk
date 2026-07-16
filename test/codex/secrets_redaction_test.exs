defmodule Codex.SecretsRedactionTest do
  use ExUnit.Case, async: true

  alias Codex.Auth.Store
  alias Codex.AppServer.Sanitizer
  alias Codex.GovernedAuthority
  alias Codex.MCP.Transport.StreamableHTTP
  alias Codex.OAuth
  alias Codex.Realtime.Config
  alias Codex.Voice.Models.OpenAIProvider
  alias Codex.Voice.Models.OpenAISTT
  alias Codex.Voice.Models.OpenAITTS
  alias Codex.TestSupport.GovernedAuthority, as: GovernedAuthorityFixture

  test "auth credentials never appear in inspect output" do
    tokens = %Store.Tokens{
      access_token: "LEAK-ACCESS",
      refresh_token: "LEAK-REFRESH",
      id_token: "LEAK-ID"
    }

    bedrock = %Store.BedrockCredentials{api_key: "LEAK-BEDROCK", region: "us-east-1"}

    record = %Store.Record{
      auth_mode: :chatgpt,
      openai_api_key: "LEAK-OPENAI",
      bedrock_api_key: bedrock,
      tokens: tokens
    }

    assert_redacted([tokens, bedrock, record], [
      "LEAK-ACCESS",
      "LEAK-REFRESH",
      "LEAK-ID",
      "LEAK-BEDROCK",
      "LEAK-OPENAI"
    ])
  end

  test "runtime client structs redact keys, bearer tokens, and authorization headers" do
    structs = [
      %Codex.Options{api_key: "LEAK-OPTIONS"},
      %Config.ModelConfig{
        api_key: "LEAK-REALTIME",
        headers: %{"authorization" => "Bearer LEAK-HEADER"}
      },
      %StreamableHTTP.State{
        bearer_token: "LEAK-BEARER",
        oauth_tokens: %{access_token: "LEAK-MCP-OAUTH"}
      },
      %OpenAIProvider{api_key: "LEAK-VOICE-PROVIDER"},
      %OpenAISTT{api_key: "LEAK-STT"},
      %Codex.Voice.Models.OpenAISTTSession{api_key: "LEAK-STT-SESSION"},
      %OpenAITTS{api_key: "LEAK-TTS"}
    ]

    assert_redacted(structs, [
      "LEAK-OPTIONS",
      "LEAK-REALTIME",
      "LEAK-HEADER",
      "LEAK-BEARER",
      "LEAK-MCP-OAUTH",
      "LEAK-VOICE-PROVIDER",
      "LEAK-STT",
      "LEAK-STT-SESSION",
      "LEAK-TTS"
    ])
  end

  test "OAuth flow state redacts verifier, state, device code, and nested auth" do
    pkce = %OAuth.PKCE{
      verifier: "LEAK-VERIFIER",
      challenge: "public-challenge",
      method: "S256"
    }

    pending = %OAuth.Session.PendingLogin{
      provider: :openai,
      flow: :browser_code,
      storage: :memory,
      context: :context,
      authorize_url: "https://example.invalid/?state=LEAK-STATE",
      state: "LEAK-STATE",
      pkce: pkce,
      redirect_uri: "http://localhost/callback",
      loopback_server: nil
    }

    pending_device = %OAuth.Session.PendingDeviceLogin{
      provider: :openai,
      flow: :device_code,
      storage: :memory,
      context: :context,
      verification_url: "https://example.invalid/device",
      user_code: "LEAK-USER-CODE",
      device_code: "LEAK-DEVICE-CODE",
      interval_ms: 1_000
    }

    loopback = %OAuth.LoopbackServer{
      pid: self(),
      callback_url: "http://localhost/callback",
      port: 1,
      callback_path: "/callback",
      expected_state: "LEAK-LOOPBACK-STATE"
    }

    loopback_state = %OAuth.LoopbackServer.State{
      expected_state: "LEAK-INTERNAL-STATE",
      result: {:ok, %{code: "LEAK-AUTH-CODE"}}
    }

    context =
      struct(OAuth.Context,
        child_process_env: %{"OPENAI_API_KEY" => "LEAK-CONTEXT-ENV"},
        effective_config: %{"credential" => "LEAK-CONTEXT-CONFIG"}
      )

    session =
      struct(OAuth.Session,
        context: context,
        auth_record: %Store.Record{openai_api_key: "LEAK-SESSION-AUTH"}
      )

    assert_redacted([pkce, pending, pending_device, loopback, loopback_state, context, session], [
      "LEAK-VERIFIER",
      "LEAK-STATE",
      "LEAK-USER-CODE",
      "LEAK-DEVICE-CODE",
      "LEAK-LOOPBACK-STATE",
      "LEAK-INTERNAL-STATE",
      "LEAK-AUTH-CODE",
      "LEAK-CONTEXT-ENV",
      "LEAK-CONTEXT-CONFIG",
      "LEAK-SESSION-AUTH"
    ])
  end

  test "governed materialization cannot expose or encode transient launch secrets" do
    sentinel = "LEAK-GOVERNED-MATERIALIZATION"

    attrs =
      GovernedAuthorityFixture.refs(
        command: "/secret/path/#{sentinel}/codex",
        cwd: "/tmp/#{sentinel}/workspace",
        config_root: "/tmp/#{sentinel}/home",
        auth_root: "/tmp/#{sentinel}/home",
        base_url: "https://#{sentinel}.example/v1",
        env: %{
          "CODEX_HOME" => "/tmp/#{sentinel}/home",
          "OPENAI_BASE_URL" => "https://#{sentinel}.example/v1",
          "OPENAI_API_KEY" => sentinel
        }
      )

    assert {:ok, authority} = GovernedAuthority.new(attrs)
    refute inspect(authority) =~ sentinel

    assert_raise ArgumentError, ~r/transient and cannot be encoded/, fn ->
      Jason.encode!(authority)
    end

    redacted = GovernedAuthority.redacted(authority)
    refute inspect(redacted) =~ sentinel
    assert redacted.env_keys == ["CODEX_HOME", "OPENAI_API_KEY", "OPENAI_BASE_URL"]
  end

  test "app-server sanitizer redacts credential fields and text sentinels but preserves usage" do
    sanitized =
      Sanitizer.term(%{
        "apiKey" => "LEAK-API-KEY",
        "nested" => %{"refreshToken" => "LEAK-REFRESH"},
        "inputTokens" => 13,
        "credentialRef" => "credential-ref-safe",
        "message" => "Authorization: Bearer LEAK-BEARER"
      })

    assert sanitized["apiKey"] == "[REDACTED]"
    assert sanitized["nested"]["refreshToken"] == "[REDACTED]"
    assert sanitized["inputTokens"] == 13
    assert sanitized["credentialRef"] == "credential-ref-safe"
    assert sanitized["message"] == "Authorization: [REDACTED]"
    refute inspect(sanitized) =~ "LEAK-"
  end

  test "VERSION file matches mix.exs" do
    assert File.read!("VERSION") |> String.trim() == Mix.Project.config()[:version]
  end

  defp assert_redacted(structs, leaks) do
    inspected = Enum.map_join(structs, "\n", &inspect/1)

    Enum.each(leaks, fn leak ->
      refute inspected =~ leak
    end)
  end
end

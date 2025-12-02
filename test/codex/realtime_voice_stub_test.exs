defmodule Codex.RealtimeVoiceStubTest do
  use ExUnit.Case, async: true

  test "realtime stubs return clear unsupported errors" do
    assert {:error, %Codex.Error{kind: :unsupported_feature, message: message, details: details}} =
             Codex.Realtime.connect(%{})

    assert message =~ "Realtime support is not available"
    assert details[:feature] == :realtime
  end

  test "voice stubs return clear unsupported errors" do
    assert {:error, %Codex.Error{kind: :unsupported_feature, message: message, details: details}} =
             Codex.Voice.stream(%{})

    assert message =~ "Voice support is not available"
    assert details[:feature] == :voice
  end
end

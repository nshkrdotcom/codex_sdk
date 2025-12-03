# Covers ADR-014 (realtime/voice stubs)
Mix.Task.run("app.start")

defmodule CodexExamples.LiveRealtimeVoiceStub do
  @moduledoc false

  def main(_argv) do
    IO.puts("Realtime and voice support are intentionally stubbed in this SDK.")

    IO.inspect(Codex.Realtime.connect(), label: "Codex.Realtime.connect/0")
    IO.inspect(Codex.Realtime.stream(), label: "Codex.Realtime.stream/0")
    IO.inspect(Codex.Voice.stream(), label: "Codex.Voice.stream/0")
    IO.inspect(Codex.Voice.call(), label: "Codex.Voice.call/0")
  end
end

CodexExamples.LiveRealtimeVoiceStub.main(System.argv())

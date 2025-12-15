defmodule Codex.Transport.ExecJsonl do
  @moduledoc false

  @behaviour Codex.Transport

  alias Codex.Thread

  @impl true
  def run_turn(%Thread{} = thread, input, turn_opts) when is_binary(input) do
    Thread.run_turn_exec_jsonl(thread, input, turn_opts)
  end

  @impl true
  def run_turn_streamed(%Thread{} = thread, input, turn_opts) when is_binary(input) do
    Thread.run_turn_streamed_exec_jsonl(thread, input, turn_opts)
  end
end

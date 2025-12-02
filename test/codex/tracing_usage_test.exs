defmodule Codex.TracingUsageTest do
  use ExUnit.Case, async: true

  alias Codex.Options
  alias Codex.RunConfig
  alias Codex.RunResultStreaming
  alias Codex.Telemetry
  alias Codex.Thread
  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.TestSupport.FixtureScripts

  test "RunConfig accepts tracing metadata and telemetry attributes include them" do
    {:ok, config} =
      RunConfig.new(%{
        workflow: "deploy",
        group: "team-a",
        trace_id: "trace-123",
        trace_include_sensitive_data: true,
        tracing_disabled: false
      })

    assert config.workflow == "deploy"
    assert config.group == "team-a"
    assert config.trace_id == "trace-123"
    assert config.trace_include_sensitive_data
    refute config.tracing_disabled

    attrs =
      Telemetry.thread_span_attributes(%{
        thread_id: "t1",
        turn_id: "turn1",
        workflow: config.workflow,
        group: config.group,
        trace_id: config.trace_id,
        trace_sensitive: config.trace_include_sensitive_data
      })

    assert attrs[:"codex.workflow"] == "deploy"
    assert attrs[:"codex.group"] == "team-a"
    assert attrs[:"codex.trace_id"] == "trace-123"
    assert attrs[:"codex.trace.sensitive_data"] == true
  end

  test "streamed runs aggregate usage across turns" do
    {script_path, state_file} =
      FixtureScripts.sequential_fixtures([
        "thread_auto_run_step1.jsonl",
        "thread_auto_run_step2.jsonl"
      ])

    on_exit(fn ->
      File.rm_rf(script_path)
      File.rm_rf(state_file)
    end)

    {:ok, codex_opts} =
      Options.new(%{
        api_key: "test",
        codex_path_override: script_path
      })

    {:ok, thread_opts} = ThreadOptions.new(%{})
    thread = Thread.build(codex_opts, thread_opts)

    {:ok, result} = Thread.run_streamed(thread, "aggregate usage")

    _ = result |> RunResultStreaming.raw_events() |> Enum.to_list()

    assert RunResultStreaming.usage(result) == %{
             "input_tokens" => 15,
             "cached_input_tokens" => 0,
             "output_tokens" => 11,
             "total_tokens" => 26
           }
  end
end

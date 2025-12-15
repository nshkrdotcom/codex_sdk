defmodule Codex.TestSupport.FixtureScripts do
  @moduledoc false

  @fixtures_dir Path.join([File.cwd!(), "integration", "fixtures", "python"])

  @doc """
  Returns a shell script path that simply cats the given fixture file.
  """
  @spec cat_fixture(Path.t()) :: Path.t()
  def cat_fixture(fixture_name) do
    fixture_path = Path.join(@fixtures_dir, fixture_name)

    unless File.exists?(fixture_path) do
      raise ArgumentError, "fixture #{fixture_name} does not exist in #{@fixtures_dir}"
    end

    script_body = """
    #!/usr/bin/env bash
    cat "#{fixture_path}"
    """

    write_script(script_body)
  end

  @doc """
  Returns `{script_path, state_file}` where the script emits fixtures sequentially on each execution.
  After the final fixture is emitted the sequence resets, allowing reuse across tests. Callers are
  responsible for cleaning up the script and state files via `on_exit/1`.
  """
  @spec sequential_fixtures([Path.t()]) :: {Path.t(), Path.t()}
  def sequential_fixtures(fixture_names) when is_list(fixture_names) and fixture_names != [] do
    Enum.each(fixture_names, &assert_fixture!/1)

    state_file =
      Path.join(System.tmp_dir!(), "codex_script_state_#{System.unique_integer([:positive])}")

    script_body = """
    #!/usr/bin/env bash
    STATE_FILE="#{state_file}"
    if [ ! -f "$STATE_FILE" ]; then
      echo 0 > "$STATE_FILE"
    fi

    CURRENT=$(cat "$STATE_FILE")
    NEXT=$((CURRENT + 1))

    case "$NEXT" in
    #{sequence_case_clauses(fixture_names)}
    *)
      NEXT=1
      #{emit_fixture(Enum.at(fixture_names, 0))}
      ;;
    esac

    echo "$NEXT" > "$STATE_FILE"
    """

    {write_script(script_body), state_file}
  end

  @doc """
  Returns a script that writes to `touch_path` once the process starts.
  Useful for testing stream laziness.
  """
  @spec touch_on_start(Path.t(), Path.t()) :: Path.t()
  def touch_on_start(fixture_name, touch_path) do
    assert_fixture!(fixture_name)

    script_body = """
    #!/usr/bin/env bash
    touch "#{touch_path}"
    cat "#{Path.join(@fixtures_dir, fixture_name)}"
    """

    write_script(script_body)
  end

  @doc """
  Returns a script that records codex arguments to `capture_path` before streaming the fixture.
  """
  @spec capture_args(Path.t(), Path.t()) :: Path.t()
  def capture_args(fixture_name, capture_path) do
    assert_fixture!(fixture_name)

    script_body = """
    #!/usr/bin/env bash
    echo "$@" > "#{capture_path}"
    cat "#{Path.join(@fixtures_dir, fixture_name)}"
    """

    write_script(script_body)
  end

  @doc """
  Returns a temporary executable that emulates `codex app-server`.

  This is used by deterministic integration tests (no real codex install required).

  ## Options

  - `:scenario` - `:basic` or `:command_approval`
  - `:expected_decision` - JSON value expected in the approval response (required for `:command_approval`)
  """
  @spec mock_app_server(keyword()) :: Path.t()
  def mock_app_server(opts \\ []) when is_list(opts) do
    scenario = Keyword.get(opts, :scenario, :basic)
    expected_decision = Keyword.get(opts, :expected_decision)

    expected_decision_json =
      if is_nil(expected_decision), do: "null", else: Jason.encode!(expected_decision)

    script_body = """
    #!/usr/bin/env python3
    import json
    import sys

    SCENARIO = #{inspect(to_string(scenario))}
    EXPECTED_DECISION = json.loads('''#{expected_decision_json}''')

    def send(obj):
        sys.stdout.write(json.dumps(obj) + \"\\n\")
        sys.stdout.flush()

    def fail(message):
        sys.stderr.write(message + \"\\n\")
        sys.stderr.flush()
        sys.exit(2)

    def read_json():
        line = sys.stdin.readline()
        if not line:
            return None
        line = line.strip()
        if not line:
            return {}
        return json.loads(line)

    def main():
        if len(sys.argv) < 2 or sys.argv[1] != \"app-server\":
            fail(\"unsupported invocation: \" + \" \".join(sys.argv))

        thread_id = \"thr_1\"
        turn_id = \"turn_1\"

        while True:
            msg = read_json()
            if msg is None:
                return 0

            if isinstance(msg, dict) and \"method\" in msg and \"id\" in msg:
                method = msg.get(\"method\")
                req_id = msg.get(\"id\")
                params = msg.get(\"params\") or {}

                if method == \"initialize\":
                    send({\"id\": req_id, \"result\": {\"userAgent\": \"codex/0.0.0\"}})
                    continue

                if method == \"thread/start\":
                    send({\"id\": req_id, \"result\": {\"thread\": {\"id\": thread_id}}})
                    continue

                if method == \"thread/resume\":
                    send({\"id\": req_id, \"result\": {\"thread\": {\"id\": thread_id}}})
                    continue

                if method == \"turn/start\":
                    if params.get(\"threadId\") != thread_id:
                        fail(\"turn/start threadId mismatch\")

                    send({
                        \"id\": req_id,
                        \"result\": {\"turn\": {\"id\": turn_id, \"items\": [], \"status\": \"inProgress\", \"error\": None}}
                    })

                    if SCENARIO == \"command_approval\":
                        approval_id = 7
                        send({
                            \"id\": approval_id,
                            \"method\": \"item/commandExecution/requestApproval\",
                            \"params\": {
                                \"threadId\": thread_id,
                                \"turnId\": turn_id,
                                \"itemId\": \"item_1\"
                            }
                        })

                        response = read_json()
                        if response is None:
                            fail(\"expected approval response, got EOF\")

                        if response.get(\"id\") != approval_id:
                            fail(\"approval response id mismatch\")

                        decision = (response.get(\"result\") or {}).get(\"decision\")
                        if decision != EXPECTED_DECISION:
                            fail(\"approval decision mismatch: got \" + json.dumps(decision))

                    send({\"method\": \"turn/started\", \"params\": {\"threadId\": thread_id, \"turn\": {\"id\": turn_id, \"status\": \"inProgress\", \"items\": [], \"error\": None}}})
                    send({\"method\": \"item/agentMessage/delta\", \"params\": {\"threadId\": thread_id, \"turnId\": turn_id, \"itemId\": \"msg_1\", \"delta\": \"hi\"}})
                    send({\"method\": \"item/completed\", \"params\": {\"threadId\": thread_id, \"turnId\": turn_id, \"item\": {\"type\": \"agentMessage\", \"id\": \"msg_1\", \"text\": \"hi\"}}})
                    send({\"method\": \"turn/completed\", \"params\": {\"threadId\": thread_id, \"turn\": {\"id\": turn_id, \"status\": \"completed\", \"items\": [], \"error\": None}}})
                    continue

                send({\"id\": req_id, \"error\": {\"code\": -32000, \"message\": \"unknown method\"}})
                continue

            # notifications from the client (e.g. initialized) are ignored

    if __name__ == \"__main__\":
        sys.exit(main())
    """

    write_script(script_body)
  end

  defp sequence_case_clauses(fixture_names) do
    fixture_names
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {fixture, idx} ->
      """
      #{idx})
        #{emit_fixture(fixture)}
        ;;
      """
    end)
  end

  defp emit_fixture(fixture_name) do
    ~s(cat "#{Path.join(@fixtures_dir, fixture_name)}")
  end

  defp assert_fixture!(fixture_name) do
    fixture = Path.join(@fixtures_dir, fixture_name)

    unless File.exists?(fixture) do
      raise ArgumentError, "fixture #{fixture_name} does not exist in #{@fixtures_dir}"
    end
  end

  defp write_script(body) do
    path = Path.join(System.tmp_dir!(), "mock_codex_#{System.unique_integer([:positive])}")
    File.write!(path, body)
    File.chmod!(path, 0o755)
    path
  end
end

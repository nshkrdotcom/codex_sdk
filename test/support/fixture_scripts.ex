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

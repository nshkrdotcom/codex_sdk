defmodule Codex.ContractCase do
  @moduledoc """
  Shared helpers for contract parity tests that compare Elixir behavior with
  Python-generated fixtures.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Codex.ContractCase

      @moduletag :contract
    end
  end

  setup context do
    if context[:pending] do
      {:ok, skip: "pending parity fixture"}
    else
      :ok
    end
  end

  @doc """
  Returns the absolute path to a fixture, raising if it does not exist.
  """
  @spec fixture_path!(Path.t()) :: Path.t()
  def fixture_path!(relative_path) do
    base =
      Path.join([
        File.cwd!(),
        "integration",
        "fixtures"
      ])

    path = Path.join(base, relative_path)

    unless File.exists?(path) do
      flunk("""
      expected fixture to exist at #{path}.
      run `python3 scripts/harvest_python_fixtures.py` to generate parity fixtures.
      """)
    end

    path
  end

  @doc """
  Loads a JSONL fixture file, returning the decoded events as a list of maps.
  """
  @spec load_jsonl_fixture(Path.t()) :: [map()]
  def load_jsonl_fixture(path) do
    path
    |> File.stream!([], :line)
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Enum.map(&decode_json!/1)
  end

  defp decode_json!(line) do
    case Jason.decode(line) do
      {:ok, data} ->
        data

      {:error, reason} ->
        flunk("failed to decode JSON fixture line: #{inspect(reason)}")
    end
  end
end

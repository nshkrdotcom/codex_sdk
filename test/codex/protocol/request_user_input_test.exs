defmodule Codex.Protocol.RequestUserInputTest do
  use ExUnit.Case, async: true

  alias Codex.Protocol.RequestUserInput

  test "question parsing handles options" do
    data = %{
      "id" => "q1",
      "header" => "Choose a mode",
      "question" => "Which mode?",
      "options" => [
        %{"label" => "A", "description" => "Option A"},
        %{"label" => "B", "description" => "Option B"}
      ]
    }

    assert %RequestUserInput.Question{
             id: "q1",
             header: "Choose a mode",
             question: "Which mode?",
             options: [
               %RequestUserInput.Option{label: "A", description: "Option A"},
               %RequestUserInput.Option{label: "B", description: "Option B"}
             ]
           } = RequestUserInput.Question.from_map(data)
  end

  test "response encodes answers map" do
    response = %RequestUserInput.Response{
      answers: %{"q1" => %RequestUserInput.Answer{answers: ["yes"]}}
    }

    assert %{"answers" => %{"q1" => %{"answers" => ["yes"]}}} =
             RequestUserInput.Response.to_map(response)
  end
end

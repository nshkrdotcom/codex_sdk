defmodule Codex.Protocol.RequestUserInputTest do
  use ExUnit.Case, async: true

  alias Codex.Protocol.RequestUserInput

  test "question parsing handles options" do
    data = %{
      "id" => "q1",
      "header" => "Choose a mode",
      "question" => "Which mode?",
      "isOther" => true,
      "isSecret" => true,
      "future_field" => "preserved",
      "options" => [
        %{"label" => "A", "description" => "Option A", "rank" => 1},
        %{"label" => "B", "description" => "Option B"}
      ]
    }

    assert %RequestUserInput.Question{
             id: "q1",
             header: "Choose a mode",
             question: "Which mode?",
             is_other: true,
             is_secret: true,
             extra: %{"future_field" => "preserved"},
             options: [
               %RequestUserInput.Option{
                 label: "A",
                 description: "Option A",
                 extra: %{"rank" => 1}
               },
               %RequestUserInput.Option{label: "B", description: "Option B"}
             ]
           } = RequestUserInput.Question.from_map(data)
  end

  test "question encoding preserves flags" do
    question = %RequestUserInput.Question{
      id: "q1",
      header: "Choose a mode",
      question: "Which mode?",
      is_other: true,
      is_secret: true,
      options: [
        %RequestUserInput.Option{label: "A", description: "Option A"}
      ]
    }

    assert %{
             "id" => "q1",
             "header" => "Choose a mode",
             "question" => "Which mode?",
             "isOther" => true,
             "isSecret" => true,
             "options" => [%{"label" => "A", "description" => "Option A"}]
           } = RequestUserInput.Question.to_map(question)
  end

  test "question encoding preserves unknown fields" do
    question = %RequestUserInput.Question{
      id: "q1",
      header: "Choose a mode",
      question: "Which mode?",
      options: [
        %RequestUserInput.Option{label: "A", description: "Option A", extra: %{"rank" => 1}}
      ],
      extra: %{"future_field" => "preserved"}
    }

    assert %{
             "future_field" => "preserved",
             "options" => [%{"label" => "A", "description" => "Option A", "rank" => 1}]
           } = RequestUserInput.Question.to_map(question)
  end

  test "response encodes answers map" do
    response = %RequestUserInput.Response{
      answers: %{"q1" => %RequestUserInput.Answer{answers: ["yes"]}}
    }

    assert %{"answers" => %{"q1" => %{"answers" => ["yes"]}}} =
             RequestUserInput.Response.to_map(response)
  end
end

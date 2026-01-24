defmodule Codex.Protocol.RequestUserInput do
  @moduledoc """
  Types for agent-to-user input requests.

  The RequestUserInput tool allows the agent to interactively ask
  the user questions during execution.
  """

  defmodule Question do
    @moduledoc "A question to present to the user"
    use TypedStruct
    alias Codex.Protocol.RequestUserInput.Option

    typedstruct do
      field(:id, String.t(), enforce: true)
      field(:header, String.t(), enforce: true)
      field(:question, String.t(), enforce: true)
      field(:options, [Option.t()] | nil)
    end

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        id: Map.fetch!(data, "id"),
        header: Map.fetch!(data, "header"),
        question: Map.fetch!(data, "question"),
        options: data |> Map.get("options") |> parse_options()
      }
    end

    defp parse_options(nil), do: nil
    defp parse_options(opts), do: Enum.map(opts, &Option.from_map/1)
  end

  defmodule Option do
    @moduledoc "An option for a question"
    use TypedStruct

    typedstruct do
      field(:label, String.t(), enforce: true)
      field(:description, String.t(), enforce: true)
    end

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        label: Map.fetch!(data, "label"),
        description: Map.fetch!(data, "description")
      }
    end
  end

  defmodule Answer do
    @moduledoc "An answer to a question"
    use TypedStruct

    typedstruct do
      field(:answers, [String.t()], enforce: true)
    end

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{answers: answers}) do
      %{"answers" => answers}
    end
  end

  defmodule Response do
    @moduledoc "Response containing answers to all questions"
    use TypedStruct

    typedstruct do
      field(:answers, %{String.t() => Answer.t()}, enforce: true)
    end

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{answers: answers}) do
      encoded =
        answers
        |> Enum.map(fn {k, v} -> {k, Answer.to_map(v)} end)
        |> Map.new()

      %{"answers" => encoded}
    end
  end
end

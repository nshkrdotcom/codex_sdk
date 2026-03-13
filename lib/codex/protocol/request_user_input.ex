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
      field(:is_other, boolean(), default: false)
      field(:is_secret, boolean(), default: false)
      field(:options, [Option.t()] | nil)
    end

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        id: Map.fetch!(data, "id"),
        header: Map.fetch!(data, "header"),
        question: Map.fetch!(data, "question"),
        is_other: fetch_optional(data, ["isOther", "is_other"], false),
        is_secret: fetch_optional(data, ["isSecret", "is_secret"], false),
        options: data |> Map.get("options") |> parse_options()
      }
    end

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = question) do
      %{
        "id" => question.id,
        "header" => question.header,
        "question" => question.question,
        "isOther" => question.is_other,
        "isSecret" => question.is_secret
      }
      |> put_optional("options", encode_options(question.options))
    end

    defp parse_options(nil), do: nil
    defp parse_options(opts), do: Enum.map(opts, &Option.from_map/1)

    defp encode_options(nil), do: nil
    defp encode_options(options), do: Enum.map(options, &Option.to_map/1)

    defp fetch_optional(map, keys, default) do
      Enum.find_value(keys, default, fn key ->
        if Map.has_key?(map, key), do: Map.get(map, key), else: nil
      end)
    end

    defp put_optional(map, _key, nil), do: map
    defp put_optional(map, key, value), do: Map.put(map, key, value)
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

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = option) do
      %{"label" => option.label, "description" => option.description}
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

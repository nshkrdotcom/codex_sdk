defmodule Codex.Protocol.RequestUserInput do
  @moduledoc """
  Types for agent-to-user input requests.

  The RequestUserInput tool allows the agent to interactively ask
  the user questions during execution.
  """

  defmodule Question do
    @moduledoc "A question to present to the user"
    use TypedStruct

    alias CliSubprocessCore.Schema.Conventions
    alias Codex.Protocol.RequestUserInput.Option
    alias Codex.Schema

    @known_fields ["id", "header", "question", "isOther", "isSecret", "options"]
    @schema Zoi.map(
              %{
                "id" => Conventions.trimmed_string() |> Zoi.min(1),
                "header" => Conventions.trimmed_string() |> Zoi.min(1),
                "question" => Conventions.trimmed_string() |> Zoi.min(1),
                "isOther" => Zoi.default(Zoi.optional(Zoi.nullish(Zoi.boolean())), false),
                "isSecret" => Zoi.default(Zoi.optional(Zoi.nullish(Zoi.boolean())), false),
                "options" => Zoi.optional(Zoi.nullish(Zoi.array(Zoi.map(Zoi.any(), Zoi.any()))))
              },
              unrecognized_keys: :preserve
            )

    typedstruct do
      field(:id, String.t(), enforce: true)
      field(:header, String.t(), enforce: true)
      field(:question, String.t(), enforce: true)
      field(:is_other, boolean(), default: false)
      field(:is_secret, boolean(), default: false)
      field(:options, [Option.t()] | nil)
      field(:extra, map(), default: %{})
    end

    @spec schema() :: Zoi.schema()
    def schema, do: @schema

    @spec parse(map() | keyword() | t()) ::
            {:ok, t()}
            | {:error,
               {:invalid_request_user_input_question, CliSubprocessCore.Schema.error_detail()}}
    def parse(%__MODULE__{} = question), do: {:ok, question}
    def parse(data) when is_list(data), do: parse(Enum.into(data, %{}))

    def parse(data) do
      case Schema.parse(@schema, normalize_input(data), :invalid_request_user_input_question) do
        {:ok, parsed} ->
          {known, extra} = Schema.split_extra(parsed, @known_fields)

          {:ok,
           %__MODULE__{
             id: Map.fetch!(known, "id"),
             header: Map.fetch!(known, "header"),
             question: Map.fetch!(known, "question"),
             is_other: Map.get(known, "isOther", false),
             is_secret: Map.get(known, "isSecret", false),
             options: parse_options(Map.get(known, "options")),
             extra: extra
           }}

        {:error, {:invalid_request_user_input_question, details}} ->
          {:error, {:invalid_request_user_input_question, details}}
      end
    end

    @spec parse!(map() | keyword() | t()) :: t()
    def parse!(%__MODULE__{} = question), do: question
    def parse!(data) when is_list(data), do: parse!(Enum.into(data, %{}))

    def parse!(data) do
      parsed =
        Schema.parse!(@schema, normalize_input(data), :invalid_request_user_input_question)

      {known, extra} = Schema.split_extra(parsed, @known_fields)

      %__MODULE__{
        id: Map.fetch!(known, "id"),
        header: Map.fetch!(known, "header"),
        question: Map.fetch!(known, "question"),
        is_other: Map.get(known, "isOther", false),
        is_secret: Map.get(known, "isSecret", false),
        options: parse_options(Map.get(known, "options")),
        extra: extra
      }
    end

    @spec from_map(map()) :: t()
    def from_map(data), do: parse!(data)

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
      |> Map.merge(question.extra)
    end

    defp normalize_input(%{} = data) do
      data
      |> Enum.map(fn
        {key, value} -> {normalize_key(key), normalize_nested_value(value)}
      end)
      |> Map.new()
    end

    defp normalize_input(other), do: other

    defp normalize_key(:is_other), do: "isOther"
    defp normalize_key("is_other"), do: "isOther"
    defp normalize_key(:is_secret), do: "isSecret"
    defp normalize_key("is_secret"), do: "isSecret"
    defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
    defp normalize_key(key), do: key

    defp normalize_nested_value(%{} = value), do: normalize_input(value)

    defp normalize_nested_value(value) when is_list(value),
      do: Enum.map(value, &normalize_nested_value/1)

    defp normalize_nested_value(value), do: value

    defp parse_options(nil), do: nil
    defp parse_options(opts), do: Enum.map(opts, &Option.parse!/1)

    defp encode_options(nil), do: nil
    defp encode_options(options), do: Enum.map(options, &Option.to_map/1)

    defp put_optional(map, _key, nil), do: map
    defp put_optional(map, key, value), do: Map.put(map, key, value)
  end

  defmodule Option do
    @moduledoc "An option for a question"
    use TypedStruct

    alias CliSubprocessCore.Schema.Conventions
    alias Codex.Schema

    @known_fields ["label", "description"]
    @schema Zoi.map(
              %{
                "label" => Conventions.trimmed_string() |> Zoi.min(1),
                "description" => Conventions.trimmed_string()
              },
              unrecognized_keys: :preserve
            )

    typedstruct do
      field(:label, String.t(), enforce: true)
      field(:description, String.t(), enforce: true)
      field(:extra, map(), default: %{})
    end

    @spec schema() :: Zoi.schema()
    def schema, do: @schema

    @spec parse(map() | keyword() | t()) ::
            {:ok, t()}
            | {:error,
               {:invalid_request_user_input_option, CliSubprocessCore.Schema.error_detail()}}
    def parse(%__MODULE__{} = option), do: {:ok, option}
    def parse(data) when is_list(data), do: parse(Enum.into(data, %{}))

    def parse(data) do
      case Schema.parse(@schema, normalize_input(data), :invalid_request_user_input_option) do
        {:ok, parsed} ->
          {known, extra} = Schema.split_extra(parsed, @known_fields)

          {:ok,
           %__MODULE__{label: known["label"], description: known["description"], extra: extra}}

        {:error, {:invalid_request_user_input_option, details}} ->
          {:error, {:invalid_request_user_input_option, details}}
      end
    end

    @spec parse!(map() | keyword() | t()) :: t()
    def parse!(%__MODULE__{} = option), do: option
    def parse!(data) when is_list(data), do: parse!(Enum.into(data, %{}))

    def parse!(data) do
      parsed = Schema.parse!(@schema, normalize_input(data), :invalid_request_user_input_option)
      {known, extra} = Schema.split_extra(parsed, @known_fields)
      %__MODULE__{label: known["label"], description: known["description"], extra: extra}
    end

    @spec from_map(map()) :: t()
    def from_map(data), do: parse!(data)

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = option) do
      %{"label" => option.label, "description" => option.description}
      |> Map.merge(option.extra)
    end

    defp normalize_input(%{} = data) do
      data
      |> Enum.map(fn
        {key, value} when is_atom(key) -> {Atom.to_string(key), value}
        pair -> pair
      end)
      |> Map.new()
    end

    defp normalize_input(other), do: other
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

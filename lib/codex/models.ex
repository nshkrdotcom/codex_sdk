defmodule Codex.Models do
  @moduledoc """
  Known Codex models and their defaults.
  """

  @type reasoning_effort :: :minimal | :low | :medium | :high | :xhigh
  @type model :: %{
          id: String.t(),
          default_reasoning_effort: reasoning_effort(),
          tool_enabled?: boolean(),
          default?: boolean()
        }

  @models [
    %{
      id: "gpt-5.1-codex-max",
      default_reasoning_effort: :medium,
      tool_enabled?: true,
      default?: true
    },
    %{
      id: "gpt-5.1-codex",
      default_reasoning_effort: :medium,
      tool_enabled?: true,
      default?: false
    },
    %{
      id: "gpt-5.1-codex-mini",
      default_reasoning_effort: :medium,
      tool_enabled?: true,
      default?: false
    },
    %{id: "gpt-5.1", default_reasoning_effort: :medium, tool_enabled?: false, default?: false}
  ]

  @reasoning_efforts [:minimal, :low, :medium, :high, :xhigh]
  @default_model "gpt-5.1-codex-max"

  @doc """
  Returns the list of supported models with metadata describing defaults.
  """
  @spec list() :: nonempty_list(model())
  def list, do: @models

  @doc """
  Returns the SDK default model, honoring environment overrides when present.
  """
  @spec default_model() :: String.t()
  def default_model do
    System.get_env("CODEX_MODEL") ||
      System.get_env("CODEX_MODEL_DEFAULT") ||
      @default_model
  end

  @doc """
  Returns the default reasoning effort for the given model (or the default model).
  """
  @spec default_reasoning_effort(String.t() | atom() | nil) :: reasoning_effort() | nil
  def default_reasoning_effort(model \\ default_model()) do
    model
    |> normalize_model()
    |> case do
      nil -> nil
      normalized -> find_model(normalized) |> Map.get(:default_reasoning_effort)
    end
  end

  @doc """
  Parses a reasoning effort value into its canonical atom form.
  """
  @spec normalize_reasoning_effort(String.t() | atom() | nil) ::
          {:ok, reasoning_effort() | nil} | {:error, term()}
  def normalize_reasoning_effort(nil), do: {:ok, nil}

  def normalize_reasoning_effort(value) when is_atom(value) do
    if value in @reasoning_efforts do
      {:ok, value}
    else
      {:error, {:invalid_reasoning_effort, value}}
    end
  end

  def normalize_reasoning_effort(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()

    case normalized do
      "" -> {:ok, nil}
      "extra_high" -> {:ok, :xhigh}
      "extra-high" -> {:ok, :xhigh}
      "minimal" -> {:ok, :minimal}
      "low" -> {:ok, :low}
      "medium" -> {:ok, :medium}
      "high" -> {:ok, :high}
      "xhigh" -> {:ok, :xhigh}
      other -> {:error, {:invalid_reasoning_effort, other}}
    end
  end

  def normalize_reasoning_effort(value), do: {:error, {:invalid_reasoning_effort, value}}

  @doc """
  Returns `true` when the given model supports tool execution.
  """
  @spec tool_enabled?(String.t() | atom() | nil) :: boolean()
  def tool_enabled?(model) do
    model
    |> normalize_model()
    |> case do
      nil -> false
      normalized -> find_model(normalized) |> Map.get(:tool_enabled?, false)
    end
  end

  @doc """
  Lists the valid reasoning effort values understood by the SDK.
  """
  @spec reasoning_efforts() :: nonempty_list(reasoning_effort())
  def reasoning_efforts, do: @reasoning_efforts

  @doc """
  Renders a normalized reasoning effort as the CLI-friendly string value.
  """
  @spec reasoning_effort_to_string(reasoning_effort()) :: String.t()
  def reasoning_effort_to_string(effort) when effort in @reasoning_efforts do
    Atom.to_string(effort)
  end

  defp find_model(model) do
    Enum.find(@models, %{default_reasoning_effort: nil, tool_enabled?: false}, &(&1.id == model))
  end

  defp normalize_model(nil), do: nil
  defp normalize_model(model) when is_binary(model), do: model
  defp normalize_model(model), do: to_string(model)
end

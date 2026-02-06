defmodule Codex.Config.OptionNormalizers do
  @moduledoc false

  @type tagged_error :: {:error, {atom(), term()}}

  @spec normalize_reasoning_summary(term(), atom()) :: {:ok, String.t() | nil} | tagged_error()
  def normalize_reasoning_summary(value, error_tag \\ :invalid_model_reasoning_summary)

  def normalize_reasoning_summary(nil, _error_tag), do: {:ok, nil}

  def normalize_reasoning_summary(value, error_tag) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_reasoning_summary(error_tag)
  end

  def normalize_reasoning_summary(value, error_tag) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "" -> {:ok, nil}
      "auto" -> {:ok, "auto"}
      "concise" -> {:ok, "concise"}
      "detailed" -> {:ok, "detailed"}
      "none" -> {:ok, "none"}
      other -> {:error, {error_tag, other}}
    end
  end

  def normalize_reasoning_summary(value, error_tag), do: {:error, {error_tag, value}}

  @spec normalize_model_verbosity(term(), atom()) :: {:ok, String.t() | nil} | tagged_error()
  def normalize_model_verbosity(value, error_tag \\ :invalid_model_verbosity)

  def normalize_model_verbosity(nil, _error_tag), do: {:ok, nil}

  def normalize_model_verbosity(value, error_tag) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_model_verbosity(error_tag)
  end

  def normalize_model_verbosity(value, error_tag) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "" -> {:ok, nil}
      "low" -> {:ok, "low"}
      "medium" -> {:ok, "medium"}
      "high" -> {:ok, "high"}
      other -> {:error, {error_tag, other}}
    end
  end

  def normalize_model_verbosity(value, error_tag), do: {:error, {error_tag, value}}

  @spec normalize_history_persistence(term(), atom()) :: {:ok, String.t() | nil} | tagged_error()
  def normalize_history_persistence(value, error_tag \\ :invalid_history_persistence)

  def normalize_history_persistence(nil, _error_tag), do: {:ok, nil}

  def normalize_history_persistence(value, error_tag) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_history_persistence(error_tag)
  end

  def normalize_history_persistence(value, _error_tag) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, nil}
      trimmed -> {:ok, trimmed}
    end
  end

  def normalize_history_persistence(value, error_tag), do: {:error, {error_tag, value}}
end

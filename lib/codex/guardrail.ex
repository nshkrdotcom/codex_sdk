defmodule Codex.Guardrail do
  @moduledoc """
  Represents an input or output guardrail invoked around agent execution.
  """

  defstruct name: nil, stage: :input, handler: nil, run_in_parallel: false

  @type stage :: :input | :output

  @type t :: %__MODULE__{
          name: String.t(),
          stage: stage(),
          handler: function(),
          run_in_parallel: boolean()
        }

  @doc """
  Builds a guardrail definition.
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    name = Keyword.get(opts, :name, "guardrail")
    stage = Keyword.get(opts, :stage, :input)
    handler = Keyword.get(opts, :handler)
    run_in_parallel = Keyword.get(opts, :run_in_parallel, false)

    %__MODULE__{
      name: to_string(name),
      stage: stage,
      handler: handler,
      run_in_parallel: run_in_parallel
    }
  end

  @doc """
  Executes the guardrail handler against the given payload and context.
  """
  @spec run(t(), term(), map()) :: :ok | {:reject, String.t()} | {:tripwire, String.t()}
  def run(%__MODULE__{handler: handler}, payload, context) when is_function(handler, 2) do
    normalize_result(handler.(payload, context))
  end

  def run(%__MODULE__{handler: handler}, payload, _context) when is_function(handler, 1) do
    normalize_result(handler.(payload))
  end

  def run(_guardrail, _payload, _context), do: :ok

  defp normalize_result(:ok), do: :ok
  defp normalize_result(:allow), do: :ok
  defp normalize_result({:ok, _val}), do: :ok
  defp normalize_result({:allow, _val}), do: :ok
  defp normalize_result({:reject, message}), do: {:reject, message || "rejected"}
  defp normalize_result({:deny, message}), do: {:reject, message || "rejected"}
  defp normalize_result({:tripwire, message}), do: {:tripwire, message || "tripwire triggered"}

  defp normalize_result({:raise_exception, message}),
    do: {:tripwire, message || "tripwire triggered"}

  defp normalize_result(:deny), do: {:reject, "rejected"}
  defp normalize_result(false), do: {:reject, "rejected"}
  defp normalize_result(_other), do: :ok
end

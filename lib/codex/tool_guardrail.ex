defmodule Codex.ToolGuardrail do
  @moduledoc """
  Guardrail applied before or after tool invocation.
  """

  defstruct name: nil, stage: :input, handler: nil, run_in_parallel: false, behavior: :allow

  @type stage :: :input | :output

  @type t :: %__MODULE__{
          name: String.t(),
          stage: stage(),
          handler: function(),
          run_in_parallel: boolean(),
          behavior: :allow | :reject_content | :raise_exception
        }

  @doc """
  Builds a tool guardrail definition.
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    name = Keyword.get(opts, :name, "tool_guardrail")
    stage = Keyword.get(opts, :stage, :input)
    handler = Keyword.get(opts, :handler)
    run_in_parallel = Keyword.get(opts, :run_in_parallel, false)
    behavior = Keyword.get(opts, :behavior, :allow)

    %__MODULE__{
      name: to_string(name),
      stage: stage,
      handler: handler,
      run_in_parallel: run_in_parallel,
      behavior: behavior
    }
  end

  @doc """
  Runs the guardrail handler for a tool call.
  """
  @spec run(t(), map(), term(), map()) ::
          :ok | {:reject, String.t()} | {:tripwire, String.t()}
  def run(%__MODULE__{handler: handler}, event, payload, context) when is_function(handler, 3) do
    normalize_result(handler.(event, payload, context))
  end

  def run(%__MODULE__{handler: handler}, event, payload, _context) when is_function(handler, 2) do
    normalize_result(handler.(event, payload))
  end

  def run(_guardrail, _event, _payload, _context), do: :ok

  defp normalize_result(:ok), do: :ok
  defp normalize_result({:ok, _val}), do: :ok
  defp normalize_result({:reject, message}), do: {:reject, message || "rejected"}
  defp normalize_result({:tripwire, message}), do: {:tripwire, message || "tripwire triggered"}
  defp normalize_result(_other), do: :ok
end

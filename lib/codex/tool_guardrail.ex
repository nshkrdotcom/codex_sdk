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
  def run(%__MODULE__{handler: handler, behavior: behavior}, event, payload, context)
      when is_function(handler, 3) do
    normalize_result(handler.(event, payload, context), behavior)
  end

  def run(%__MODULE__{handler: handler, behavior: behavior}, event, payload, _context)
      when is_function(handler, 2) do
    normalize_result(handler.(event, payload), behavior)
  end

  def run(_guardrail, _event, _payload, _context), do: :ok

  defp normalize_result(:ok, _behavior), do: :ok
  defp normalize_result(:allow, _behavior), do: :ok
  defp normalize_result({:ok, _val}, _behavior), do: :ok
  defp normalize_result({:allow, _val}, _behavior), do: :ok

  defp normalize_result({:reject, message}, behavior),
    do: {:reject, message || default_message(behavior)}

  defp normalize_result({:reject_content, message}, behavior),
    do: {:reject, message || default_message(behavior)}

  defp normalize_result({:tripwire, message}, _behavior),
    do: {:tripwire, message || "tripwire triggered"}

  defp normalize_result({:raise_exception, message}, _behavior),
    do: {:tripwire, message || "tripwire triggered"}

  defp normalize_result({:deny, message}, behavior),
    do: {:reject, message || default_message(behavior)}

  defp normalize_result(:deny, behavior), do: {:reject, default_message(behavior)}
  defp normalize_result(false, behavior), do: {:reject, default_message(behavior)}
  defp normalize_result(_other, _behavior), do: :ok

  defp default_message(:reject_content), do: "rejected"
  defp default_message(:raise_exception), do: "tripwire triggered"
  defp default_message(_), do: "rejected"
end

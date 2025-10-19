defmodule Codex.Thread.Options do
  @moduledoc """
  Per-thread configuration options.
  """

  @enforce_keys []
  defstruct metadata: %{},
            labels: %{},
            auto_run: false,
            approval_policy: nil,
            approval_hook: nil,
            approval_timeout_ms: 30_000,
            sandbox: :default,
            attachments: []

  @type t :: %__MODULE__{
          metadata: map(),
          labels: map(),
          auto_run: boolean(),
          approval_policy: module() | nil,
          approval_hook: module() | nil,
          approval_timeout_ms: pos_integer(),
          sandbox: :default | :strict | :permissive,
          attachments: [map()] | []
        }

  @doc """
  Builds a thread options struct from various inputs.
  """
  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = opts), do: {:ok, opts}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    metadata = Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    labels = Map.get(attrs, :labels, Map.get(attrs, "labels", %{}))
    auto_run = Map.get(attrs, :auto_run, Map.get(attrs, "auto_run", false))
    approval_policy = Map.get(attrs, :approval_policy, Map.get(attrs, "approval_policy"))
    approval_hook = Map.get(attrs, :approval_hook, Map.get(attrs, "approval_hook"))

    approval_timeout_ms =
      Map.get(attrs, :approval_timeout_ms, Map.get(attrs, "approval_timeout_ms", 30_000))

    sandbox = Map.get(attrs, :sandbox, Map.get(attrs, "sandbox", :default))
    attachments = Map.get(attrs, :attachments, Map.get(attrs, "attachments", []))

    with {:ok, metadata} <- ensure_map(metadata, :metadata),
         {:ok, labels} <- ensure_map(labels, :labels),
         {:ok, attachments} <- ensure_list(attachments, :attachments),
         true <-
           sandbox in [:default, :strict, :permissive] or {:error, {:invalid_sandbox, sandbox}},
         true <- is_boolean(auto_run) or {:error, {:invalid_auto_run, auto_run}},
         true <-
           (is_integer(approval_timeout_ms) and approval_timeout_ms > 0) or
             {:error, {:invalid_timeout, approval_timeout_ms}} do
      {:ok,
       %__MODULE__{
         metadata: metadata,
         labels: labels,
         auto_run: auto_run,
         approval_policy: approval_policy,
         approval_hook: approval_hook,
         approval_timeout_ms: approval_timeout_ms,
         sandbox: sandbox,
         attachments: attachments
       }}
    else
      {:error, _} = error -> error
    end
  end

  defp ensure_map(value, _field) when is_map(value), do: {:ok, value}
  defp ensure_map(nil, _field), do: {:ok, %{}}
  defp ensure_map(value, field), do: {:error, {:invalid_map, field, value}}

  defp ensure_list(value, _field) when is_list(value), do: {:ok, value}
  defp ensure_list(nil, _field), do: {:ok, []}
  defp ensure_list(value, field), do: {:error, {:invalid_list, field, value}}
end

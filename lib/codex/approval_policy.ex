defmodule Codex.ApprovalPolicy do
  @moduledoc false

  @type granular_policy :: %{
          required(:type) => :granular,
          optional(:sandbox_approval) => boolean(),
          optional(:rules) => boolean(),
          optional(:skill_approval) => boolean(),
          optional(:request_permissions) => boolean(),
          optional(:mcp_elicitations) => boolean()
        }

  @type t ::
          :untrusted
          | :on_failure
          | :on_request
          | :never
          | String.t()
          | granular_policy()

  @spec normalize(term()) :: {:ok, t() | nil} | {:error, term()}
  def normalize(nil), do: {:ok, nil}
  def normalize(:untrusted), do: {:ok, :untrusted}
  def normalize(:on_failure), do: {:ok, :on_failure}
  def normalize(:on_request), do: {:ok, :on_request}
  def normalize(:never), do: {:ok, :never}
  def normalize("untrusted"), do: {:ok, :untrusted}
  def normalize("on-failure"), do: {:ok, :on_failure}
  def normalize("on-request"), do: {:ok, :on_request}
  def normalize("never"), do: {:ok, :never}
  def normalize(value) when is_list(value), do: value |> Map.new() |> normalize()

  def normalize(%{} = value) do
    case granular_body(value) do
      {:ok, granular} ->
        {:ok, normalize_granular(granular)}

      :error ->
        case fetch_any(value, [:type, "type"]) do
          type when type in [:granular, "granular"] ->
            {:ok, normalize_granular(value)}

          _ ->
            {:error, {:invalid_ask_for_approval, value}}
        end
    end
  end

  def normalize(value) when is_binary(value), do: {:ok, value}
  def normalize(value), do: {:error, {:invalid_ask_for_approval, value}}

  @spec to_external(term()) :: String.t() | map() | nil
  def to_external(policy) do
    case normalize(policy) do
      {:ok, nil} ->
        nil

      {:ok, :untrusted} ->
        "untrusted"

      {:ok, :on_failure} ->
        "on-failure"

      {:ok, :on_request} ->
        "on-request"

      {:ok, :never} ->
        "never"

      {:ok, %{} = granular} ->
        %{
          "granular" => %{
            "sandbox_approval" => Map.get(granular, :sandbox_approval, false),
            "rules" => Map.get(granular, :rules, false),
            "skill_approval" => Map.get(granular, :skill_approval, false),
            "request_permissions" => Map.get(granular, :request_permissions, false),
            "mcp_elicitations" => Map.get(granular, :mcp_elicitations, false)
          }
        }

      {:ok, value} when is_binary(value) ->
        value

      {:error, _reason} ->
        nil
    end
  end

  defp granular_body(%{} = value) do
    case fetch_any(value, [:granular, "granular"]) do
      %{} = granular -> {:ok, granular}
      granular when is_list(granular) -> {:ok, Map.new(granular)}
      _ -> :error
    end
  end

  defp normalize_granular(value) do
    %{
      type: :granular,
      sandbox_approval:
        granular_boolean(value, [
          :sandbox_approval,
          "sandbox_approval",
          :sandboxApproval,
          "sandboxApproval"
        ]),
      rules: granular_boolean(value, [:rules, "rules"]),
      skill_approval:
        granular_boolean(value, [
          :skill_approval,
          "skill_approval",
          :skillApproval,
          "skillApproval"
        ]),
      request_permissions:
        granular_boolean(value, [
          :request_permissions,
          "request_permissions",
          :requestPermissions,
          "requestPermissions"
        ]),
      mcp_elicitations:
        granular_boolean(value, [
          :mcp_elicitations,
          "mcp_elicitations",
          :mcpElicitations,
          "mcpElicitations"
        ])
    }
  end

  defp granular_boolean(map, keys) do
    case fetch_any(map, keys) do
      true -> true
      _ -> false
    end
  end

  defp fetch_any(map, keys) when is_map(map) and is_list(keys) do
    Enum.reduce_while(keys, nil, fn key, _acc ->
      case Map.fetch(map, key) do
        {:ok, value} -> {:halt, value}
        :error -> {:cont, nil}
      end
    end)
  end
end

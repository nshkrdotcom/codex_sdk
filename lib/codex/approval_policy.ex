defmodule Codex.ApprovalPolicy do
  @moduledoc false

  @granular_flag_keys %{
    sandbox_approval: [
      :sandbox_approval,
      "sandbox_approval",
      :sandboxApproval,
      "sandboxApproval"
    ],
    rules: [:rules, "rules"],
    skill_approval: [
      :skill_approval,
      "skill_approval",
      :skillApproval,
      "skillApproval"
    ],
    request_permissions: [
      :request_permissions,
      "request_permissions",
      :requestPermissions,
      "requestPermissions"
    ],
    mcp_elicitations: [
      :mcp_elicitations,
      "mcp_elicitations",
      :mcpElicitations,
      "mcpElicitations"
    ]
  }

  @granular_type_keys [:type, "type"]
  @external_tag_keys [:granular, "granular"]

  @inline_granular_keys @granular_flag_keys
                        |> Map.values()
                        |> List.flatten()
                        |> Kernel.++(@granular_type_keys)

  @nested_granular_keys @granular_flag_keys |> Map.values() |> List.flatten()

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
    with {:ok, granular_tag} <- fetch_unique_any(value, @external_tag_keys, :granular),
         {:ok, granular_type} <- fetch_unique_any(value, @granular_type_keys, :type) do
      normalize_map(value, granular_tag, granular_type)
    end
  end

  def normalize(value) when is_binary(value), do: {:ok, value}
  def normalize(value), do: {:error, {:invalid_ask_for_approval, value}}

  @spec to_external(term()) :: {:ok, String.t() | map() | nil} | {:error, term()}
  def to_external(policy) do
    case normalize(policy) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, :untrusted} ->
        {:ok, "untrusted"}

      {:ok, :on_failure} ->
        {:ok, "on-failure"}

      {:ok, :on_request} ->
        {:ok, "on-request"}

      {:ok, :never} ->
        {:ok, "never"}

      {:ok, %{} = granular} ->
        {:ok,
         %{
           "granular" => %{
             "sandbox_approval" => Map.get(granular, :sandbox_approval, false),
             "rules" => Map.get(granular, :rules, false),
             "skill_approval" => Map.get(granular, :skill_approval, false),
             "request_permissions" => Map.get(granular, :request_permissions, false),
             "mcp_elicitations" => Map.get(granular, :mcp_elicitations, false)
           }
         }}

      {:ok, value} when is_binary(value) ->
        {:ok, value}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_granular_body(%{} = granular, _source), do: {:ok, granular}

  defp normalize_granular_body(granular, _source) when is_list(granular),
    do: {:ok, Map.new(granular)}

  defp normalize_granular_body(_granular, source) do
    {:error, {:invalid_ask_for_approval, {:invalid_granular_shape, source}}}
  end

  defp normalize_map(value, granular_tag, _granular_type) when not is_nil(granular_tag) do
    case validate_allowed_keys(value, @external_tag_keys) do
      :ok -> normalize_tagged_granular(granular_tag, value)
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_map(value, nil, granular_type) when granular_type in [:granular, "granular"] do
    normalize_granular(value, @inline_granular_keys)
  end

  defp normalize_map(value, nil, _granular_type) do
    {:error, {:invalid_ask_for_approval, value}}
  end

  defp normalize_tagged_granular(granular_tag, source) do
    with {:ok, granular} <- normalize_granular_body(granular_tag, source) do
      normalize_granular(granular, @nested_granular_keys)
    end
  end

  defp normalize_granular(value, allowed_keys) do
    with :ok <- validate_allowed_keys(value, allowed_keys),
         {:ok, sandbox_approval} <- normalize_granular_flag(value, :sandbox_approval),
         {:ok, rules} <- normalize_granular_flag(value, :rules),
         {:ok, skill_approval} <- normalize_granular_flag(value, :skill_approval),
         {:ok, request_permissions} <- normalize_granular_flag(value, :request_permissions),
         {:ok, mcp_elicitations} <- normalize_granular_flag(value, :mcp_elicitations) do
      {:ok,
       %{
         type: :granular,
         sandbox_approval: sandbox_approval,
         rules: rules,
         skill_approval: skill_approval,
         request_permissions: request_permissions,
         mcp_elicitations: mcp_elicitations
       }}
    end
  end

  defp normalize_granular_flag(map, key) do
    values =
      @granular_flag_keys
      |> Map.fetch!(key)
      |> Enum.filter(&Map.has_key?(map, &1))
      |> Enum.map(&Map.get(map, &1))

    cond do
      values == [] ->
        {:ok, false}

      Enum.any?(values, &(not is_boolean(&1))) ->
        {:error, {:invalid_ask_for_approval, {:invalid_granular_flag, key, values}}}

      Enum.uniq(values) |> length() > 1 ->
        {:error, {:invalid_ask_for_approval, {:conflicting_granular_flag, key, values}}}

      true ->
        {:ok, hd(values)}
    end
  end

  defp validate_allowed_keys(map, allowed_keys) when is_map(map) do
    unknown =
      map
      |> Map.keys()
      |> Enum.reject(&(&1 in allowed_keys))

    if unknown == [] do
      :ok
    else
      {:error, {:invalid_ask_for_approval, {:unknown_granular_keys, unknown, map}}}
    end
  end

  defp fetch_unique_any(map, keys, label) when is_map(map) and is_list(keys) do
    values =
      keys
      |> Enum.filter(&Map.has_key?(map, &1))
      |> Enum.map(&Map.get(map, &1))

    cond do
      values == [] ->
        {:ok, nil}

      Enum.uniq(values) |> length() > 1 ->
        {:error, {:invalid_ask_for_approval, {:conflicting_granular_key, label, values}}}

      true ->
        {:ok, hd(values)}
    end
  end
end

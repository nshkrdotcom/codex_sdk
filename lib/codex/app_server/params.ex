defmodule Codex.AppServer.Params do
  @moduledoc false

  @spec normalize_map(map() | keyword() | nil) :: map()
  def normalize_map(nil), do: %{}
  def normalize_map(%{} = map), do: map
  def normalize_map(list) when is_list(list), do: Map.new(list)

  @spec ask_for_approval(atom() | String.t() | nil) :: String.t() | nil
  def ask_for_approval(nil), do: nil
  def ask_for_approval(:untrusted), do: "untrusted"
  def ask_for_approval(:on_failure), do: "on-failure"
  def ask_for_approval(:on_request), do: "on-request"
  def ask_for_approval(:never), do: "never"
  def ask_for_approval("untrusted"), do: "untrusted"
  def ask_for_approval("on-failure"), do: "on-failure"
  def ask_for_approval("on-request"), do: "on-request"
  def ask_for_approval("never"), do: "never"
  def ask_for_approval(value) when is_binary(value), do: value
  def ask_for_approval(_), do: nil

  @type sandbox_policy ::
          String.t()
          | %{String.t() => String.t()}
          | nil

  @spec sandbox_mode(atom() | String.t() | {atom(), atom()} | nil) :: sandbox_policy()
  def sandbox_mode(nil), do: nil
  def sandbox_mode(:strict), do: "read-only"
  def sandbox_mode(:default), do: "workspace-write"
  def sandbox_mode(:permissive), do: "danger-full-access"
  def sandbox_mode(:read_only), do: "read-only"
  def sandbox_mode(:workspace_write), do: "workspace-write"
  def sandbox_mode(:danger_full_access), do: "danger-full-access"

  def sandbox_mode(:external_sandbox),
    do: %{"type" => "external-sandbox", "network_access" => "restricted"}

  def sandbox_mode({:external_sandbox, :enabled}),
    do: %{"type" => "external-sandbox", "network_access" => "enabled"}

  def sandbox_mode({:external_sandbox, :restricted}),
    do: %{"type" => "external-sandbox", "network_access" => "restricted"}

  def sandbox_mode("read-only"), do: "read-only"
  def sandbox_mode("workspace-write"), do: "workspace-write"
  def sandbox_mode("danger-full-access"), do: "danger-full-access"

  def sandbox_mode("external-sandbox"),
    do: %{"type" => "external-sandbox", "network_access" => "restricted"}

  def sandbox_mode(value) when is_binary(value), do: value
  def sandbox_mode(_), do: nil

  @type app_sandbox_policy :: map() | nil

  @spec sandbox_policy(term()) :: app_sandbox_policy()
  def sandbox_policy(nil), do: nil
  def sandbox_policy(%{} = policy), do: normalize_sandbox_policy(policy)

  def sandbox_policy(policy) when is_list(policy),
    do: policy |> Map.new() |> normalize_sandbox_policy()

  def sandbox_policy(policy) when is_atom(policy), do: %{"type" => normalize_policy_type(policy)}

  def sandbox_policy(policy) when is_binary(policy),
    do: %{"type" => normalize_policy_type(policy)}

  def sandbox_policy(_), do: nil

  @spec reasoning_effort(atom() | String.t() | nil) :: String.t() | nil
  def reasoning_effort(nil), do: nil
  def reasoning_effort(value) when is_atom(value), do: Atom.to_string(value)
  def reasoning_effort(value) when is_binary(value), do: value
  def reasoning_effort(_), do: nil

  @spec merge_strategy(atom() | String.t() | nil) :: String.t() | nil
  def merge_strategy(nil), do: nil
  def merge_strategy(:replace), do: "replace"
  def merge_strategy(:upsert), do: "upsert"
  def merge_strategy("replace"), do: "replace"
  def merge_strategy("upsert"), do: "upsert"
  def merge_strategy(value) when is_binary(value), do: value
  def merge_strategy(_), do: nil

  @type user_input :: map()

  @spec user_input(String.t() | [map()]) :: [user_input()]
  def user_input(input) when is_binary(input) do
    [%{"type" => "text", "text" => input}]
  end

  def user_input(inputs) when is_list(inputs) do
    Enum.map(inputs, &user_input_block/1)
  end

  defp user_input_block(%{"type" => "text"} = block) do
    %{"type" => "text", "text" => Map.get(block, "text") || ""}
  end

  defp user_input_block(%{type: :text} = block) do
    %{"type" => "text", "text" => Map.get(block, :text) || ""}
  end

  defp user_input_block(%{"type" => "image"} = block) do
    %{"type" => "image", "url" => Map.get(block, "url") || ""}
  end

  defp user_input_block(%{type: :image} = block) do
    %{"type" => "image", "url" => Map.get(block, :url) || ""}
  end

  defp user_input_block(%{"type" => type} = block) when type in ["localImage", "local_image"] do
    %{"type" => "localImage", "path" => Map.get(block, "path") || ""}
  end

  defp user_input_block(%{type: type} = block) when type in [:local_image, :localImage] do
    %{"type" => "localImage", "path" => Map.get(block, :path) || ""}
  end

  defp user_input_block(text) when is_binary(text) do
    %{"type" => "text", "text" => text}
  end

  defp user_input_block(other) when is_map(other) do
    other
    |> normalize_map()
    |> Map.new()
    |> ensure_type()
  end

  defp ensure_type(%{"type" => _} = block), do: block
  defp ensure_type(block), do: Map.put(block, "type", "text")

  defp normalize_sandbox_policy(%{} = policy) do
    type =
      policy
      |> fetch_any([:type, "type"])
      |> normalize_policy_type()

    %{}
    |> put_optional("type", type)
    |> put_optional(
      "writableRoots",
      fetch_any(policy, [:writable_roots, "writable_roots", :writableRoots, "writableRoots"])
    )
    |> put_optional(
      "networkAccess",
      normalize_network_access(
        type,
        fetch_any(policy, [:network_access, "network_access", :networkAccess, "networkAccess"])
      )
    )
    |> put_optional(
      "excludeTmpdirEnvVar",
      fetch_any(policy, [
        :exclude_tmpdir_env_var,
        "exclude_tmpdir_env_var",
        :excludeTmpdirEnvVar,
        "excludeTmpdirEnvVar"
      ])
    )
    |> put_optional(
      "excludeSlashTmp",
      fetch_any(policy, [
        :exclude_slash_tmp,
        "exclude_slash_tmp",
        :excludeSlashTmp,
        "excludeSlashTmp"
      ])
    )
    |> case do
      %{} = result when map_size(result) == 0 -> nil
      %{} = result -> result
    end
  end

  defp normalize_policy_type(nil), do: nil
  defp normalize_policy_type(:read_only), do: "readOnly"
  defp normalize_policy_type("read-only"), do: "readOnly"
  defp normalize_policy_type("read_only"), do: "readOnly"
  defp normalize_policy_type("readOnly"), do: "readOnly"
  defp normalize_policy_type(:workspace_write), do: "workspaceWrite"
  defp normalize_policy_type("workspace-write"), do: "workspaceWrite"
  defp normalize_policy_type("workspace_write"), do: "workspaceWrite"
  defp normalize_policy_type("workspaceWrite"), do: "workspaceWrite"
  defp normalize_policy_type(:danger_full_access), do: "dangerFullAccess"
  defp normalize_policy_type("danger-full-access"), do: "dangerFullAccess"
  defp normalize_policy_type("danger_full_access"), do: "dangerFullAccess"
  defp normalize_policy_type("dangerFullAccess"), do: "dangerFullAccess"
  defp normalize_policy_type(:external_sandbox), do: "externalSandbox"
  defp normalize_policy_type("external-sandbox"), do: "externalSandbox"
  defp normalize_policy_type("external_sandbox"), do: "externalSandbox"
  defp normalize_policy_type("externalSandbox"), do: "externalSandbox"
  defp normalize_policy_type(value) when is_atom(value), do: value |> Atom.to_string()
  defp normalize_policy_type(value) when is_binary(value), do: value
  defp normalize_policy_type(_), do: nil

  defp normalize_network_access("externalSandbox", value),
    do: normalize_external_network_access(value)

  defp normalize_network_access(_type, value) do
    case value do
      true -> true
      false -> false
      :enabled -> true
      :restricted -> false
      "enabled" -> true
      "restricted" -> false
      _ -> value
    end
  end

  defp normalize_external_network_access(value) do
    case value do
      :enabled -> "enabled"
      :restricted -> "restricted"
      true -> "enabled"
      false -> "restricted"
      "enabled" -> "enabled"
      "restricted" -> "restricted"
      other -> other
    end
  end

  defp fetch_any(map, keys) when is_list(keys) and is_map(map) do
    Enum.reduce_while(keys, nil, fn key, _acc ->
      case Map.fetch(map, key) do
        {:ok, value} -> {:halt, value}
        :error -> {:cont, nil}
      end
    end)
  end

  def put_optional(map, _key, nil), do: map
  def put_optional(map, _key, []), do: map
  def put_optional(map, key, value), do: Map.put(map, key, value)
end

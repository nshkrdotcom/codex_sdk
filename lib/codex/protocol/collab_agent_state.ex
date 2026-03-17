defmodule Codex.Protocol.CollabAgentState do
  @moduledoc """
  Typed representation of a collaboration agent lifecycle state.
  """

  use TypedStruct

  @type status ::
          :pending_init
          | :running
          | :completed
          | :errored
          | :shutdown
          | :not_found
          | String.t()

  typedstruct do
    field(:status, status(), enforce: true)
    field(:message, String.t() | nil)
  end

  @spec from_map(map() | atom() | String.t() | t() | nil) :: t()
  def from_map(%__MODULE__{} = state), do: state
  def from_map(nil), do: %__MODULE__{status: :pending_init}
  def from_map(value) when is_atom(value), do: value |> Atom.to_string() |> from_map()

  def from_map(value) when is_binary(value) do
    %__MODULE__{status: decode_status(value)}
  end

  def from_map(%{} = value) do
    normalized = normalize_keys(value)

    cond do
      Map.has_key?(normalized, "status") ->
        %__MODULE__{
          status: decode_status(Map.get(normalized, "status")),
          message: normalize_message(Map.get(normalized, "message"))
        }

      Map.has_key?(normalized, "completed") ->
        %__MODULE__{
          status: :completed,
          message: normalize_message(Map.get(normalized, "completed"))
        }

      Map.has_key?(normalized, "errored") ->
        %__MODULE__{
          status: :errored,
          message: normalize_message(Map.get(normalized, "errored"))
        }

      true ->
        %__MODULE__{status: :pending_init}
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = state) do
    %{"status" => encode_state_status(state.status)}
    |> maybe_put("message", state.message)
  end

  @spec to_event_value(t()) :: map() | String.t()
  def to_event_value(%__MODULE__{status: :completed, message: nil}), do: "completed"

  def to_event_value(%__MODULE__{status: :completed, message: message}),
    do: %{"completed" => message}

  def to_event_value(%__MODULE__{status: :errored, message: message}),
    do: %{"errored" => message || ""}

  def to_event_value(%__MODULE__{status: status}), do: encode_event_status(status)

  defp decode_status("pendingInit"), do: :pending_init
  defp decode_status("pending_init"), do: :pending_init
  defp decode_status("running"), do: :running
  defp decode_status("completed"), do: :completed
  defp decode_status("errored"), do: :errored
  defp decode_status("shutdown"), do: :shutdown
  defp decode_status("notFound"), do: :not_found
  defp decode_status("not_found"), do: :not_found
  defp decode_status(other) when is_binary(other), do: other
  defp decode_status(other), do: to_string(other)

  defp encode_state_status(:pending_init), do: "pendingInit"
  defp encode_state_status(:running), do: "running"
  defp encode_state_status(:completed), do: "completed"
  defp encode_state_status(:errored), do: "errored"
  defp encode_state_status(:shutdown), do: "shutdown"
  defp encode_state_status(:not_found), do: "notFound"
  defp encode_state_status(status) when is_binary(status), do: status
  defp encode_state_status(status), do: to_string(status)

  defp encode_event_status(:pending_init), do: "pending_init"
  defp encode_event_status(:running), do: "running"
  defp encode_event_status(:completed), do: "completed"
  defp encode_event_status(:errored), do: "errored"
  defp encode_event_status(:shutdown), do: "shutdown"
  defp encode_event_status(:not_found), do: "not_found"
  defp encode_event_status(status) when is_binary(status), do: status
  defp encode_event_status(status), do: to_string(status)

  defp normalize_keys(%{} = map) do
    map
    |> Enum.map(fn {key, value} ->
      {normalize_key(key), value}
    end)
    |> Map.new()
  end

  defp normalize_key(key) when is_atom(key), do: key |> Atom.to_string() |> normalize_key()
  defp normalize_key(key) when is_binary(key), do: key

  defp normalize_message(nil), do: nil
  defp normalize_message(value) when is_binary(value), do: value
  defp normalize_message(value), do: to_string(value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

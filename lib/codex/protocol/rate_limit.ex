defmodule Codex.Protocol.RateLimit do
  @moduledoc """
  Rate limit snapshot types for TokenCount events.
  """

  defmodule Helpers do
    @moduledoc false

    @spec fetch_any(map(), [String.t()]) :: term() | nil
    def fetch_any(%{} = map, keys) when is_list(keys) do
      Enum.reduce_while(keys, nil, fn key, _acc ->
        if Map.has_key?(map, key) do
          {:halt, Map.get(map, key)}
        else
          {:cont, nil}
        end
      end)
    end

    def fetch_any(_map, _keys), do: nil

    @spec normalize_float(term()) :: float() | term()
    def normalize_float(nil), do: raise(ArgumentError, "missing used_percent")
    def normalize_float(value) when is_integer(value), do: value * 1.0
    def normalize_float(value) when is_float(value), do: value
    def normalize_float(value), do: value

    @spec maybe_put(map(), String.t(), term()) :: map()
    def maybe_put(map, _key, nil), do: map
    def maybe_put(map, key, value), do: Map.put(map, key, value)
  end

  defmodule Window do
    @moduledoc "A rate limit window"
    use TypedStruct

    alias Codex.Protocol.RateLimit.Helpers

    typedstruct do
      field(:used_percent, float(), enforce: true)
      field(:window_minutes, integer() | nil)
      field(:resets_at, integer() | nil)
    end

    @spec from_map(map()) :: t()
    def from_map(data) do
      used_percent =
        data
        |> Helpers.fetch_any(["used_percent", "usedPercent"])
        |> Helpers.normalize_float()

      %__MODULE__{
        used_percent: used_percent,
        window_minutes:
          Helpers.fetch_any(data, [
            "window_minutes",
            "windowMinutes",
            "window_duration_mins",
            "windowDurationMins"
          ]),
        resets_at: Helpers.fetch_any(data, ["resets_at", "resetsAt"])
      }
    end

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = window) do
      %{"used_percent" => window.used_percent}
      |> Helpers.maybe_put("window_minutes", window.window_minutes)
      |> Helpers.maybe_put("resets_at", window.resets_at)
    end
  end

  defmodule CreditsSnapshot do
    @moduledoc "Credits balance snapshot"
    use TypedStruct

    alias Codex.Protocol.RateLimit.Helpers

    typedstruct do
      field(:has_credits, boolean(), enforce: true)
      field(:unlimited, boolean(), enforce: true)
      field(:balance, String.t() | nil)
    end

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        has_credits: Helpers.fetch_any(data, ["has_credits", "hasCredits"]),
        unlimited: Helpers.fetch_any(data, ["unlimited", "isUnlimited"]),
        balance: Map.get(data, "balance")
      }
    end

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = snapshot) do
      %{"has_credits" => snapshot.has_credits, "unlimited" => snapshot.unlimited}
      |> Helpers.maybe_put("balance", snapshot.balance)
    end
  end

  defmodule Snapshot do
    @moduledoc "Complete rate limit snapshot"
    use TypedStruct

    alias Codex.Protocol.RateLimit.Helpers

    @type plan_type :: :plus | :pro | :team | :enterprise | :api | nil

    typedstruct do
      field(:primary, Window.t() | nil)
      field(:secondary, Window.t() | nil)
      field(:credits, CreditsSnapshot.t() | nil)
      field(:plan_type, plan_type())
    end

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        primary: data |> Map.get("primary") |> parse_window(),
        secondary: data |> Map.get("secondary") |> parse_window(),
        credits: data |> Map.get("credits") |> parse_credits(),
        plan_type: data |> Helpers.fetch_any(["plan_type", "planType"]) |> parse_plan_type()
      }
    end

    defp parse_window(nil), do: nil
    defp parse_window(data), do: Window.from_map(data)

    defp parse_credits(nil), do: nil
    defp parse_credits(data), do: CreditsSnapshot.from_map(data)

    defp parse_plan_type(nil), do: nil
    defp parse_plan_type("plus"), do: :plus
    defp parse_plan_type("pro"), do: :pro
    defp parse_plan_type("team"), do: :team
    defp parse_plan_type("enterprise"), do: :enterprise
    defp parse_plan_type("api"), do: :api
    defp parse_plan_type(_), do: nil

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = snapshot) do
      %{}
      |> Helpers.maybe_put("primary", snapshot.primary && Window.to_map(snapshot.primary))
      |> Helpers.maybe_put("secondary", snapshot.secondary && Window.to_map(snapshot.secondary))
      |> Helpers.maybe_put(
        "credits",
        snapshot.credits && CreditsSnapshot.to_map(snapshot.credits)
      )
      |> Helpers.maybe_put("plan_type", snapshot.plan_type && Atom.to_string(snapshot.plan_type))
    end
  end
end

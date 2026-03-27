defmodule Codex.Protocol.RateLimit do
  @moduledoc """
  Rate limit snapshot types for TokenCount events.
  """

  defmodule Helpers do
    @moduledoc false

    @spec normalize_float(term(), keyword()) :: {:ok, float()} | {:error, String.t()}
    def normalize_float(nil, _opts), do: {:error, "missing used_percent"}
    def normalize_float(value, _opts) when is_integer(value), do: {:ok, value * 1.0}
    def normalize_float(value, _opts) when is_float(value), do: {:ok, value}
    def normalize_float(_value, _opts), do: {:error, "invalid used_percent"}

    @spec normalize_keys(map(), map()) :: map()
    def normalize_keys(%{} = data, mapping) when is_map(mapping) do
      data
      |> Enum.map(fn {key, value} ->
        {normalize_key(key, mapping), normalize_nested_value(value, mapping)}
      end)
      |> Map.new()
    end

    def normalize_key(key, mapping) when is_atom(key) do
      key
      |> Atom.to_string()
      |> normalize_key(mapping)
    end

    def normalize_key(key, mapping) when is_binary(key), do: Map.get(mapping, key, key)

    def normalize_nested_value(%{} = value, mapping), do: normalize_keys(value, mapping)

    def normalize_nested_value(value, mapping) when is_list(value),
      do: Enum.map(value, &normalize_nested_value(&1, mapping))

    def normalize_nested_value(value, _mapping), do: value

    @spec maybe_put(map(), String.t(), term()) :: map()
    def maybe_put(map, _key, nil), do: map
    def maybe_put(map, key, value), do: Map.put(map, key, value)
  end

  defmodule Window do
    @moduledoc "A rate limit window"
    use TypedStruct

    alias Codex.Protocol.RateLimit.Helpers
    alias Codex.Schema

    @key_mapping %{
      "usedPercent" => "used_percent",
      "windowMinutes" => "window_minutes",
      "windowDurationMins" => "window_minutes",
      "window_duration_mins" => "window_minutes",
      "resetsAt" => "resets_at"
    }
    @known_fields ["used_percent", "window_minutes", "resets_at"]
    @schema Zoi.map(
              %{
                "used_percent" => Zoi.number() |> Zoi.transform({Helpers, :normalize_float, []}),
                "window_minutes" => Zoi.optional(Zoi.nullish(Zoi.integer())),
                "resets_at" => Zoi.optional(Zoi.nullish(Zoi.integer()))
              },
              unrecognized_keys: :preserve
            )

    typedstruct do
      field(:used_percent, float(), enforce: true)
      field(:window_minutes, integer() | nil)
      field(:resets_at, integer() | nil)
      field(:extra, map(), default: %{})
    end

    @spec schema() :: Zoi.schema()
    def schema, do: @schema

    @spec parse(map() | keyword() | t()) ::
            {:ok, t()}
            | {:error, {:invalid_rate_limit_window, CliSubprocessCore.Schema.error_detail()}}
    def parse(%__MODULE__{} = window), do: {:ok, window}
    def parse(data) when is_list(data), do: parse(Enum.into(data, %{}))

    def parse(data) do
      case Schema.parse(@schema, normalize_input(data), :invalid_rate_limit_window) do
        {:ok, parsed} ->
          {known, extra} = Schema.split_extra(parsed, @known_fields)

          {:ok,
           %__MODULE__{
             used_percent: Map.fetch!(known, "used_percent"),
             window_minutes: Map.get(known, "window_minutes"),
             resets_at: Map.get(known, "resets_at"),
             extra: extra
           }}

        {:error, {:invalid_rate_limit_window, details}} ->
          {:error, {:invalid_rate_limit_window, details}}
      end
    end

    @spec parse!(map() | keyword() | t()) :: t()
    def parse!(%__MODULE__{} = window), do: window
    def parse!(data) when is_list(data), do: parse!(Enum.into(data, %{}))

    def parse!(data) do
      parsed = Schema.parse!(@schema, normalize_input(data), :invalid_rate_limit_window)
      {known, extra} = Schema.split_extra(parsed, @known_fields)

      %__MODULE__{
        used_percent: Map.fetch!(known, "used_percent"),
        window_minutes: Map.get(known, "window_minutes"),
        resets_at: Map.get(known, "resets_at"),
        extra: extra
      }
    end

    @spec from_map(map()) :: t()
    def from_map(data), do: parse!(data)

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = window) do
      %{"used_percent" => window.used_percent}
      |> Helpers.maybe_put("window_minutes", window.window_minutes)
      |> Helpers.maybe_put("resets_at", window.resets_at)
      |> Map.merge(window.extra)
    end

    defp normalize_input(%{} = data), do: Helpers.normalize_keys(data, @key_mapping)
    defp normalize_input(other), do: other
  end

  defmodule CreditsSnapshot do
    @moduledoc "Credits balance snapshot"
    use TypedStruct

    alias CliSubprocessCore.Schema.Conventions
    alias Codex.Protocol.RateLimit.Helpers
    alias Codex.Schema

    @key_mapping %{
      "hasCredits" => "has_credits",
      "isUnlimited" => "unlimited"
    }
    @known_fields ["has_credits", "unlimited", "balance"]
    @schema Zoi.map(
              %{
                "has_credits" => Zoi.boolean(),
                "unlimited" => Zoi.boolean(),
                "balance" => Conventions.optional_trimmed_string()
              },
              unrecognized_keys: :preserve
            )

    typedstruct do
      field(:has_credits, boolean(), enforce: true)
      field(:unlimited, boolean(), enforce: true)
      field(:balance, String.t() | nil)
      field(:extra, map(), default: %{})
    end

    @spec schema() :: Zoi.schema()
    def schema, do: @schema

    @spec parse(map() | keyword() | t()) ::
            {:ok, t()}
            | {:error, {:invalid_rate_limit_credits, CliSubprocessCore.Schema.error_detail()}}
    def parse(%__MODULE__{} = credits), do: {:ok, credits}
    def parse(data) when is_list(data), do: parse(Enum.into(data, %{}))

    def parse(data) do
      case Schema.parse(@schema, normalize_input(data), :invalid_rate_limit_credits) do
        {:ok, parsed} ->
          {known, extra} = Schema.split_extra(parsed, @known_fields)

          {:ok,
           %__MODULE__{
             has_credits: Map.fetch!(known, "has_credits"),
             unlimited: Map.fetch!(known, "unlimited"),
             balance: Map.get(known, "balance"),
             extra: extra
           }}

        {:error, {:invalid_rate_limit_credits, details}} ->
          {:error, {:invalid_rate_limit_credits, details}}
      end
    end

    @spec parse!(map() | keyword() | t()) :: t()
    def parse!(%__MODULE__{} = credits), do: credits
    def parse!(data) when is_list(data), do: parse!(Enum.into(data, %{}))

    def parse!(data) do
      parsed = Schema.parse!(@schema, normalize_input(data), :invalid_rate_limit_credits)
      {known, extra} = Schema.split_extra(parsed, @known_fields)

      %__MODULE__{
        has_credits: Map.fetch!(known, "has_credits"),
        unlimited: Map.fetch!(known, "unlimited"),
        balance: Map.get(known, "balance"),
        extra: extra
      }
    end

    @spec from_map(map()) :: t()
    def from_map(data), do: parse!(data)

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = snapshot) do
      %{
        "has_credits" => snapshot.has_credits,
        "unlimited" => snapshot.unlimited
      }
      |> Helpers.maybe_put("balance", snapshot.balance)
      |> Map.merge(snapshot.extra)
    end

    defp normalize_input(%{} = data), do: Helpers.normalize_keys(data, @key_mapping)
    defp normalize_input(other), do: other
  end

  defmodule Snapshot do
    @moduledoc "Complete rate limit snapshot"
    use TypedStruct

    alias CliSubprocessCore.Schema.Conventions
    alias Codex.Protocol.RateLimit.{CreditsSnapshot, Helpers, Window}
    alias Codex.Schema

    @type plan_type :: :plus | :pro | :team | :enterprise | :api | nil

    @key_mapping %{"planType" => "plan_type"}
    @known_fields ["primary", "secondary", "credits", "plan_type"]
    @schema Zoi.map(
              %{
                "primary" => Zoi.optional(Zoi.nullish(Window.schema())),
                "secondary" => Zoi.optional(Zoi.nullish(Window.schema())),
                "credits" => Zoi.optional(Zoi.nullish(CreditsSnapshot.schema())),
                "plan_type" => Conventions.optional_any()
              },
              unrecognized_keys: :preserve
            )

    typedstruct do
      field(:primary, Window.t() | nil)
      field(:secondary, Window.t() | nil)
      field(:credits, CreditsSnapshot.t() | nil)
      field(:plan_type, plan_type())
      field(:extra, map(), default: %{})
    end

    @spec schema() :: Zoi.schema()
    def schema, do: @schema

    @spec parse(map() | keyword() | t()) ::
            {:ok, t()}
            | {:error, {:invalid_rate_limit_snapshot, CliSubprocessCore.Schema.error_detail()}}
    def parse(%__MODULE__{} = snapshot), do: {:ok, snapshot}
    def parse(data) when is_list(data), do: parse(Enum.into(data, %{}))

    def parse(data) do
      case Schema.parse(@schema, normalize_input(data), :invalid_rate_limit_snapshot) do
        {:ok, parsed} ->
          {known, extra} = Schema.split_extra(parsed, @known_fields)

          {:ok,
           %__MODULE__{
             primary: parse_window(Map.get(known, "primary")),
             secondary: parse_window(Map.get(known, "secondary")),
             credits: parse_credits(Map.get(known, "credits")),
             plan_type: Map.get(known, "plan_type") |> parse_plan_type(),
             extra: extra
           }}

        {:error, {:invalid_rate_limit_snapshot, details}} ->
          {:error, {:invalid_rate_limit_snapshot, details}}
      end
    end

    @spec parse!(map() | keyword() | t()) :: t()
    def parse!(%__MODULE__{} = snapshot), do: snapshot
    def parse!(data) when is_list(data), do: parse!(Enum.into(data, %{}))

    def parse!(data) do
      parsed = Schema.parse!(@schema, normalize_input(data), :invalid_rate_limit_snapshot)
      {known, extra} = Schema.split_extra(parsed, @known_fields)

      %__MODULE__{
        primary: parse_window(Map.get(known, "primary")),
        secondary: parse_window(Map.get(known, "secondary")),
        credits: parse_credits(Map.get(known, "credits")),
        plan_type: Map.get(known, "plan_type") |> parse_plan_type(),
        extra: extra
      }
    end

    @spec from_map(map()) :: t()
    def from_map(data), do: parse!(data)

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
      |> Map.merge(snapshot.extra)
    end

    defp normalize_input(%{} = data), do: Helpers.normalize_keys(data, @key_mapping)
    defp normalize_input(other), do: other

    defp parse_window(nil), do: nil
    defp parse_window(data), do: Window.parse!(data)

    defp parse_credits(nil), do: nil
    defp parse_credits(data), do: CreditsSnapshot.parse!(data)

    defp parse_plan_type(nil), do: nil
    defp parse_plan_type("plus"), do: :plus
    defp parse_plan_type("pro"), do: :pro
    defp parse_plan_type("team"), do: :team
    defp parse_plan_type("enterprise"), do: :enterprise
    defp parse_plan_type("api"), do: :api
    defp parse_plan_type(_), do: nil
  end
end

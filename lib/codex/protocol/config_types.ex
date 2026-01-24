defmodule Codex.Protocol.ConfigTypes do
  @moduledoc """
  Protocol configuration type enums and converters.
  """

  @type web_search_mode :: :disabled | :cached | :live
  @type personality :: :friendly | :pragmatic
  @type trust_level :: :trusted | :untrusted
  @type alt_screen_mode :: :auto | :always | :never

  @spec encode_web_search_mode(web_search_mode()) :: String.t()
  def encode_web_search_mode(:disabled), do: "disabled"
  def encode_web_search_mode(:cached), do: "cached"
  def encode_web_search_mode(:live), do: "live"

  @spec decode_web_search_mode(String.t() | nil) :: web_search_mode()
  def decode_web_search_mode(nil), do: :disabled
  def decode_web_search_mode("disabled"), do: :disabled
  def decode_web_search_mode("cached"), do: :cached
  def decode_web_search_mode("live"), do: :live

  @spec encode_personality(personality()) :: String.t()
  def encode_personality(:friendly), do: "friendly"
  def encode_personality(:pragmatic), do: "pragmatic"

  @spec decode_personality(String.t() | nil) :: personality() | nil
  def decode_personality(nil), do: nil
  def decode_personality("friendly"), do: :friendly
  def decode_personality("pragmatic"), do: :pragmatic

  @spec encode_trust_level(trust_level()) :: String.t()
  def encode_trust_level(:trusted), do: "trusted"
  def encode_trust_level(:untrusted), do: "untrusted"

  @spec decode_trust_level(String.t() | nil) :: trust_level() | nil
  def decode_trust_level(nil), do: nil
  def decode_trust_level("trusted"), do: :trusted
  def decode_trust_level("untrusted"), do: :untrusted
end

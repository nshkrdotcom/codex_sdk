defmodule Codex.HTTPClient do
  @moduledoc """
  HTTP client abstraction for making HTTP requests.

  This module provides a behaviour and default implementation for HTTP operations,
  allowing easy mocking in tests while using a real HTTP client in production.

  ## Configuration

  The HTTP client implementation can be configured in `config.exs`:

      config :codex_sdk, :http_client_impl, Codex.HTTPClient.Req

  For testing, use the mock implementation:

      config :codex_sdk, :http_client_impl, Codex.HTTPClient.Mock

  ## Usage

      # GET request
      {:ok, response} = Codex.HTTPClient.get("https://api.example.com/data", [{"Authorization", "Bearer token"}])
      response.status  # => 200
      response.body    # => "{...}"

      # POST request
      {:ok, response} = Codex.HTTPClient.post("https://api.example.com/data", body, [{"Content-Type", "application/json"}])

  """

  @type headers :: [{String.t(), String.t()}]
  @type response :: %{status: integer(), body: binary() | map()}

  @callback get(url :: String.t(), headers :: headers()) ::
              {:ok, response()} | {:error, term()}

  @callback post(url :: String.t(), body :: String.t(), headers :: headers()) ::
              {:ok, response()} | {:error, term()}

  @doc """
  Performs an HTTP GET request.

  ## Parameters

    * `url` - The URL to request
    * `headers` - List of header tuples (optional, defaults to `[]`)

  ## Returns

    * `{:ok, %{status: integer(), body: binary()}}` on success
    * `{:error, reason}` on failure

  """
  @spec get(String.t(), headers()) :: {:ok, response()} | {:error, term()}
  def get(url, headers \\ []) do
    impl().get(url, headers)
  end

  @doc """
  Performs an HTTP POST request.

  ## Parameters

    * `url` - The URL to request
    * `body` - The request body as a string (usually JSON)
    * `headers` - List of header tuples (optional, defaults to `[]`)

  ## Returns

    * `{:ok, %{status: integer(), body: binary()}}` on success
    * `{:error, reason}` on failure

  """
  @spec post(String.t(), String.t(), headers()) :: {:ok, response()} | {:error, term()}
  def post(url, body, headers \\ []) do
    impl().post(url, body, headers)
  end

  defp impl do
    Application.get_env(:codex_sdk, :http_client_impl, Codex.HTTPClient.Req)
  end
end

defmodule Codex.HTTPClient.Req do
  @moduledoc """
  HTTP client implementation using Req.

  This is the default production implementation that uses the Req HTTP client
  library for making actual HTTP requests.
  """

  @behaviour Codex.HTTPClient

  @impl true
  def get(url, headers) do
    case Req.get(url, headers: headers) do
      {:ok, %Req.Response{status: status, body: body}} ->
        {:ok, %{status: status, body: normalize_body(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def post(url, body, headers) do
    case Req.post(url, body: body, headers: headers) do
      {:ok, %Req.Response{status: status, body: body}} ->
        {:ok, %{status: status, body: normalize_body(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Req may return decoded JSON as a map, but we want to keep it consistent
  defp normalize_body(body) when is_map(body), do: Jason.encode!(body)
  defp normalize_body(body) when is_binary(body), do: body
  defp normalize_body(body), do: inspect(body)
end

defmodule Codex.HTTPClient.Mock do
  @moduledoc """
  Mock HTTP client for testing.

  This implementation returns empty successful responses and can be used
  in tests where HTTP behavior is not the focus.

  For more complex mocking scenarios, consider using Mox or configuring
  custom response handlers.

  ## Configuration

  Set this as the HTTP client in test configuration:

      # config/test.exs
      config :codex_sdk, :http_client_impl, Codex.HTTPClient.Mock

  """

  @behaviour Codex.HTTPClient

  @impl true
  def get(_url, _headers) do
    {:ok, %{status: 200, body: "{}"}}
  end

  @impl true
  def post(_url, _body, _headers) do
    {:ok, %{status: 200, body: ~s({"results": []})}}
  end
end

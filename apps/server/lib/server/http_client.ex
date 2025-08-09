defmodule Server.HttpClient do
  @moduledoc """
  Centralized HTTP client with connection pooling and circuit breaker support.

  Provides async and sync HTTP operations with proper connection reuse,
  optimized for Twitch API and other external service calls.
  """

  require Logger

  # Pool configuration
  @pool_name :api_pool
  @pool_size 10
  @pool_max_overflow 5
  @pool_timeout 10_000
  @recv_timeout 10_000

  @doc """
  Starts the HTTP connection pool.

  This should be called from the application supervisor.
  """
  def child_spec(_opts) do
    # Configure hackney pool
    pool_opts = [
      name: @pool_name,
      timeout: @pool_timeout,
      max_connections: @pool_size,
      max_overflow: @pool_max_overflow
    ]

    :hackney_pool.child_spec(@pool_name, pool_opts)
  end

  @doc """
  Makes an async GET request using the connection pool.

  Returns a Task that can be awaited.
  """
  @spec async_get(String.t(), list(), keyword()) :: Task.t()
  def async_get(url, headers \\ [], opts \\ []) do
    Task.async(fn ->
      get(url, headers, opts)
    end)
  end

  @doc """
  Makes an async POST request using the connection pool.

  Returns a Task that can be awaited.
  """
  @spec async_post(String.t(), binary(), list(), keyword()) :: Task.t()
  def async_post(url, body, headers \\ [], opts \\ []) do
    Task.async(fn ->
      post(url, body, headers, opts)
    end)
  end

  @doc """
  Makes an async PATCH request using the connection pool.

  Returns a Task that can be awaited.
  """
  @spec async_patch(String.t(), binary(), list(), keyword()) :: Task.t()
  def async_patch(url, body, headers \\ [], opts \\ []) do
    Task.async(fn ->
      patch(url, body, headers, opts)
    end)
  end

  @doc """
  Makes a synchronous GET request using the connection pool.
  """
  @spec get(String.t(), list(), keyword()) :: {:ok, HTTPoison.Response.t()} | {:error, HTTPoison.Error.t()}
  def get(url, headers \\ [], opts \\ []) do
    opts = merge_pool_opts(opts)
    HTTPoison.get(url, headers, opts)
  end

  @doc """
  Makes a synchronous POST request using the connection pool.
  """
  @spec post(String.t(), binary(), list(), keyword()) :: {:ok, HTTPoison.Response.t()} | {:error, HTTPoison.Error.t()}
  def post(url, body, headers \\ [], opts \\ []) do
    opts = merge_pool_opts(opts)
    HTTPoison.post(url, body, headers, opts)
  end

  @doc """
  Makes a synchronous PATCH request using the connection pool.
  """
  @spec patch(String.t(), binary(), list(), keyword()) :: {:ok, HTTPoison.Response.t()} | {:error, HTTPoison.Error.t()}
  def patch(url, body, headers \\ [], opts \\ []) do
    opts = merge_pool_opts(opts)
    HTTPoison.patch(url, body, headers, opts)
  end

  @doc """
  Makes multiple parallel requests and returns all results.

  Useful for fetching multiple resources concurrently.
  """
  @spec parallel_requests([{:get | :post | :patch, String.t(), binary() | nil, list()}]) :: [term()]
  def parallel_requests(requests) do
    requests
    |> Enum.map(fn
      {:get, url, nil, headers} ->
        async_get(url, headers)

      {:post, url, body, headers} ->
        async_post(url, body, headers)

      {:patch, url, body, headers} ->
        async_patch(url, body, headers)
    end)
    |> Task.await_many(@recv_timeout)
  end

  # Private helpers

  defp merge_pool_opts(opts) do
    default_opts = [
      hackney: [pool: @pool_name],
      timeout: @pool_timeout,
      recv_timeout: @recv_timeout
    ]

    Keyword.merge(default_opts, opts)
  end
end

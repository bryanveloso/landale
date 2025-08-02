defmodule Nurvus.HealthChecker do
  @moduledoc """
  Health check client for monitoring service dependencies.

  Polls configured health endpoints and reports service status.
  Used during startup to verify dependencies are healthy before
  starting dependent services.
  """

  require Logger

  @default_timeout 5_000
  @startup_retry_interval 2_000
  @max_startup_retries 10

  @type health_status :: :healthy | :degraded | :unhealthy | :unknown
  @type health_response :: %{
          status: health_status(),
          service: String.t(),
          timestamp: integer(),
          details: map()
        }

  @doc """
  Checks health of a service by calling its health endpoint.

  Returns a standardized health response or error.
  """
  @spec check_health(String.t(), integer()) :: {:ok, health_response()} | {:error, term()}
  def check_health(url, timeout \\ @default_timeout) do
    Logger.debug("Checking health at #{url}")

    options = [
      receive_timeout: timeout,
      retry: false
    ]

    case Req.get(url, options) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        parse_health_response(body, url)

      {:ok, %Req.Response{status: 503, body: body}} ->
        # Service is responding but unhealthy
        parse_health_response(body, url)

      {:ok, %Req.Response{status: status}} ->
        {:error, {:bad_status, status}}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, {:connection_failed, reason}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @doc """
  Waits for a service to become healthy during startup.

  Polls the health endpoint with retries until the service is healthy
  or max retries are exceeded.
  """
  @spec wait_for_healthy(String.t(), integer(), integer()) ::
          :ok | {:error, :max_retries_exceeded}
  def wait_for_healthy(
        url,
        max_retries \\ @max_startup_retries,
        retry_interval \\ @startup_retry_interval
      ) do
    wait_for_healthy_loop(url, max_retries, retry_interval, 0)
  end

  @doc """
  Checks health of multiple services concurrently.

  Returns a map of service URL to health status.
  """
  @spec check_multiple(list(String.t()), integer()) :: %{
          String.t() => {:ok, health_response()} | {:error, term()}
        }
  def check_multiple(urls, timeout \\ @default_timeout) do
    tasks =
      Enum.map(urls, fn url ->
        Task.async(fn -> {url, check_health(url, timeout)} end)
      end)

    tasks
    |> Task.await_many(timeout + 1_000)
    |> Map.new()
  end

  @doc """
  Extracts health status from a health check result.
  """
  @spec get_status({:ok, health_response()} | {:error, term()}) :: health_status()
  def get_status({:ok, %{status: status}}), do: status
  def get_status({:error, _}), do: :unknown

  # Private functions

  defp wait_for_healthy_loop(_url, max_retries, _retry_interval, attempt)
       when attempt >= max_retries do
    {:error, :max_retries_exceeded}
  end

  defp wait_for_healthy_loop(url, max_retries, retry_interval, attempt) do
    case check_health(url) do
      {:ok, %{status: :healthy}} ->
        Logger.info("Service at #{url} is healthy after #{attempt + 1} attempts")
        :ok

      {:ok, %{status: status}} ->
        Logger.debug(
          "Service at #{url} is #{status}, retrying (#{attempt + 1}/#{max_retries})..."
        )

        Process.sleep(retry_interval)
        wait_for_healthy_loop(url, max_retries, retry_interval, attempt + 1)

      {:error, reason} ->
        Logger.debug(
          "Health check failed for #{url}: #{inspect(reason)}, retrying (#{attempt + 1}/#{max_retries})..."
        )

        Process.sleep(retry_interval)
        wait_for_healthy_loop(url, max_retries, retry_interval, attempt + 1)
    end
  end

  defp parse_health_response(body, url) do
    # Req might already decode JSON for us
    data =
      case body do
        body when is_map(body) ->
          body

        body when is_binary(body) ->
          case Jason.decode(body) do
            {:ok, decoded} ->
              decoded

            {:error, _} ->
              Logger.warning("Invalid JSON response from health check at #{url}")
              nil
          end
      end

    if data do
      status = parse_status_string(data["status"])

      response = %{
        status: status,
        service: data["service"] || "unknown",
        timestamp: data["timestamp"] || System.system_time(:second),
        details: Map.drop(data, ["status", "service", "timestamp"])
      }

      {:ok, response}
    else
      {:error, :invalid_response}
    end
  end

  defp parse_status_string("healthy"), do: :healthy
  defp parse_status_string("degraded"), do: :degraded
  defp parse_status_string("unhealthy"), do: :unhealthy
  defp parse_status_string(_), do: :unknown
end

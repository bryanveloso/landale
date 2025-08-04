defmodule Server.HTTPServiceAdapter do
  @moduledoc """
  Adapter to wrap HTTP health endpoints as ServiceStatus implementations.

  This allows Python services (phononmaser, seed) to participate in
  standardized status reporting without code changes on the Python side.

  Note: This module doesn't implement the ServiceStatus behaviour directly
  since it needs a URL parameter. Instead, it provides a utility function
  that can be used by the telemetry system.
  """

  require Logger

  @doc """
  Get status from an HTTP health endpoint.

  ## Examples

      HTTPServiceAdapter.get_status("http://localhost:8890/health")
      #=> {:ok, %{connected: true, status: "healthy", metadata: %{...}}}
  """
  def get_status(health_url) do
    try do
      case HTTPoison.get(health_url, [], timeout: 2000, recv_timeout: 2000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, data} ->
              {:ok,
               %{
                 connected: true,
                 status: determine_status(data),
                 metadata: data
               }}

            {:error, _decode_error} ->
              {:error, "Invalid JSON response"}
          end

        {:ok, %HTTPoison.Response{status_code: status_code}} ->
          {:error, "HTTP #{status_code}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, reason}
      end
    rescue
      error ->
        Logger.warning("HTTP service adapter error: #{inspect(error)}")
        {:error, "Service unreachable"}
    end
  end

  # Helper to determine status from Python health response
  defp determine_status(data) do
    case data do
      %{"status" => "healthy"} -> "healthy"
      # Python services use "running"
      %{"status" => "running"} -> "healthy"
      %{"websocket" => %{"state" => "connected"}} -> "healthy"
      %{"websocket" => %{"state" => "disconnected"}} -> "degraded"
      _ -> "degraded"
    end
  end
end

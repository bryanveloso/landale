defmodule Server.ServiceStatus do
  @moduledoc """
  Standardized behaviour for service status reporting.

  All services must implement this behaviour to provide consistent
  status information for monitoring and telemetry.
  """

  @doc """
  Returns the current status of the service.

  ## Return values

  - `{:ok, status_map}` - Service is reachable and returns status
  - `{:error, reason}` - Service cannot be reached or has an error

  ## Status map structure

  The status map should contain at minimum:

  - `:connected` - boolean indicating if service is connected
  - `:status` - "healthy" | "degraded" | "unhealthy"
  - `:metadata` - map with service-specific details (optional)

  ## Examples

      {:ok, %{
        connected: true,
        status: "healthy",
        metadata: %{
          uptime_seconds: 3600,
          version: "1.0.0"
        }
      }}
  """
  @callback get_status() :: {:ok, map()} | {:error, term()}
end

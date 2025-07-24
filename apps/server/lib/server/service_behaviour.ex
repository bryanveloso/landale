defmodule Server.ServiceBehaviour do
  @moduledoc """
  Common behaviour that all Landale services must implement.

  This behaviour defines the unified interface for service management,
  enabling consistent health checks, status reporting, and service discovery
  across both simple services (using Server.Service) and complex services
  (with custom architectures).

  ## Architecture Philosophy

  Services in Landale follow one of two patterns:

  1. **Simple Services** (e.g., Rainwave, IronmonTCP)
     - Use the `Server.Service` abstraction
     - Single GenServer process
     - Straightforward lifecycle management

  2. **Complex Services** (e.g., OBS, Twitch)
     - Custom multi-process architectures
     - Specialized state machines (gen_statem)
     - Decomposed into multiple modules

  Both patterns are valid and appropriate for their respective complexity levels.
  This behaviour ensures they all expose a consistent interface.

  ## Implementation

  Services implementing this behaviour must provide:

  ```elixir
  defmodule MyService do
    @behaviour Server.ServiceBehaviour

    @impl true
    def start_link(opts) do
      # Start your service
    end

    @impl true
    def get_status do
      {:ok, %{
        # Service-specific status
      }}
    end

    @impl true
    def get_health do
      {:ok, %{
        status: :healthy,  # or :degraded, :unhealthy
        checks: %{
          # Component-specific health checks
        }
      }}
    end

    @impl true
    def get_info do
      %{
        name: "my-service",
        version: "1.0.0",
        capabilities: [:streaming, :websocket]
      }
    end
  end
  ```
  """

  @type health_status :: :healthy | :degraded | :unhealthy
  @type service_info :: %{
          name: String.t(),
          version: String.t(),
          capabilities: [atom()],
          description: String.t() | nil
        }

  @doc """
  Starts the service.

  This is the standard OTP start_link callback that all services must implement.
  """
  @callback start_link(opts :: keyword()) :: GenServer.on_start()

  @doc """
  Gets the current status of the service.

  Returns service-specific status information. The exact structure depends on
  the service's functionality, but should include relevant operational data.

  ## Examples

  For a streaming service:
  ```elixir
  {:ok, %{
    connected: true,
    streaming: true,
    viewers: 42,
    uptime_seconds: 3600
  }}
  ```

  For a data service:
  ```elixir
  {:ok, %{
    enabled: true,
    last_update: ~U[2024-01-01 12:00:00Z],
    records_processed: 1000
  }}
  ```
  """
  @callback get_status() :: {:ok, map()} | {:error, term()}

  @doc """
  Gets the health status of the service.

  Returns a standardized health check response that can be used by monitoring
  systems, load balancers, and service discovery mechanisms.

  ## Health Status Values

  - `:healthy` - Service is fully operational
  - `:degraded` - Service is operational but with reduced functionality
  - `:unhealthy` - Service is not operational

  ## Response Structure

  ```elixir
  {:ok, %{
    status: :healthy,
    checks: %{
      database: :pass,
      api_connection: :pass,
      queue_depth: :warn  # Optional component checks
    },
    details: %{         # Optional additional details
      queue_size: 150,
      error_rate: 0.02
    }
  }}
  ```
  """
  @callback get_health() :: {:ok, %{status: health_status(), checks: map(), details: map()}} | {:error, term()}

  @doc """
  Gets static information about the service.

  Returns metadata that helps with service discovery and capability negotiation.
  This information should be static and not change during runtime.

  ## Response Structure

  ```elixir
  %{
    name: "obs-service",
    version: "2.1.0",
    capabilities: [:websocket, :streaming, :recording],
    description: "OBS WebSocket integration service"
  }
  ```
  """
  @callback get_info() :: service_info()

  @doc """
  Optional: Gracefully stops the service.

  Services can implement this to perform cleanup before shutdown.
  If not implemented, the default supervisor termination will be used.
  """
  @callback stop(reason :: term()) :: :ok
  @optional_callbacks stop: 1
end

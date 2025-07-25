defmodule Server.Service.StatusReporter do
  @moduledoc """
  Standard status reporting functionality for services.

  Provides a consistent interface for reporting service status,
  including uptime, connection state, and service-specific metrics.

  ## Usage

      defmodule MyService do
        use Server.Service
        use Server.Service.StatusReporter
        
        @impl Server.Service.StatusReporter
        def do_build_status(state) do
          %{
            custom_metric: state.some_value,
            queue_size: length(state.queue)
          }
        end
      end
  """

  @doc """
  Build service-specific status information.
  """
  @callback do_build_status(state :: map()) :: map()

  defmacro __using__(_opts) do
    quote do
      @behaviour Server.Service.StatusReporter

      defp service_healthy?(state) do
        # Default health check - services can override
        case get_in(state, [:connection, :state]) do
          # No connection management
          nil -> true
          :connected -> true
          _ -> false
        end
      end

      # Default implementation - services should override
      @impl Server.Service.StatusReporter
      def do_build_status(_state) do
        %{}
      end

      defoverridable do_build_status: 1,
                     service_healthy?: 1
    end
  end
end

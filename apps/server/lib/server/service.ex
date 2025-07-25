defmodule Server.Service do
  @moduledoc """
  Common behavior and functionality for all Landale services.

  Provides a standardized interface and shared functionality for services including:
  - Standard service lifecycle management
  - Status reporting interface
  - Connection management helpers
  - Logging and correlation setup
  - Error handling patterns

  ## Usage

  To create a service, use this module and implement the required callbacks:

      defmodule MyService do
        use Server.Service, service_name: "my-service"
        
        @impl Server.Service
        def do_init(opts) do
          # Service-specific initialization
          {:ok, %{connected: false}}
        end
        
        @impl Server.Service
        def do_terminate(_reason, _state) do
          # Service-specific cleanup
          :ok
        end
        
        @impl Server.Service
        def get_status do
          GenServer.call(__MODULE__, :get_status)
        end
      end
  """

  @doc "Service-specific initialization"
  @callback do_init(opts :: keyword()) :: {:ok, map()} | {:stop, term()}

  @doc "Service-specific termination cleanup"
  @callback do_terminate(reason :: term(), state :: map()) :: :ok

  @doc "Optional: Handle connection state changes"
  @callback handle_connection_change(old_state :: term(), new_state :: term(), state :: map()) :: map()

  @optional_callbacks handle_connection_change: 3

  defmacro __using__(opts) do
    service_name = Keyword.get(opts, :service_name)
    behaviour_module = Keyword.get(opts, :behaviour)

    quote do
      use GenServer
      require Logger

      @behaviour Server.Service

      if unquote(behaviour_module) do
        @behaviour unquote(behaviour_module)
      end

      alias Server.{CorrelationId, Events, Logging, NetworkConfig, ServiceError}

      @service_name unquote(service_name) || to_string(__MODULE__)

      # Default implementations
      unquote(define_default_functions())

      # GenServer callbacks
      unquote(define_genserver_callbacks())

      # Helper functions
      unquote(define_helper_functions())

      # Allow services to override these
      defoverridable init: 1,
                     terminate: 2,
                     start_link: 1,
                     child_spec: 1
    end
  end

  defp define_default_functions do
    quote do
      def start_link(opts \\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :worker,
          restart: :permanent,
          shutdown: 5000
        }
      end
    end
  end

  defp define_genserver_callbacks do
    quote do
      @impl GenServer
      def init(opts) do
        # Set up service context
        service_atom = service_name_to_atom(@service_name)
        Logging.set_service_context(service_atom, opts)
        correlation_id = Logging.set_correlation_id()

        Logger.info("Service starting",
          service: @service_name,
          correlation_id: correlation_id
        )

        # Call service-specific initialization
        try do
          case do_init(opts) do
            {:ok, state} ->
              {:ok,
               Map.put(state, :__service_meta__, %{
                 name: @service_name,
                 service_atom: service_atom,
                 correlation_id: correlation_id,
                 started_at: DateTime.utc_now()
               })}
          end
        rescue
          error ->
            error_msg = ServiceError.new(service_atom, "init", :startup_error, inspect(error))
            Logging.log_error("Service startup failed", inspect(error_msg))
            {:stop, {:startup_error, error}}
        end
      end

      @impl GenServer
      def terminate(reason, state) do
        Logger.info("Service terminating",
          service: @service_name,
          reason: inspect(reason)
        )

        # Call service-specific cleanup
        do_terminate(reason, state)
      end

      @impl GenServer
      def handle_call(:get_status, _from, state) do
        status = build_status(state)
        {:reply, {:ok, status}, state}
      end
    end
  end

  defp define_helper_functions do
    quote do
      defp service_name_to_atom(name) when is_binary(name) do
        name
        |> String.downcase()
        |> String.replace("-", "_")
        |> String.to_atom()
      end

      defp build_status(state) do
        base_status = %{
          service: @service_name,
          started_at: Map.get(state, :__service_meta__, %{})[:started_at],
          uptime_seconds: calculate_uptime(state)
        }

        # Add health status if service_healthy? is defined
        status_with_health =
          if function_exported?(__MODULE__, :service_healthy?, 1) do
            Map.put(base_status, :healthy, apply(__MODULE__, :service_healthy?, [state]))
          else
            base_status
          end

        # Add connection status if using ConnectionManager
        status_with_connection =
          if function_exported?(__MODULE__, :connected?, 1) do
            connection_state = if Map.has_key?(state, :connection_state), do: state.connection_state, else: nil

            Map.merge(status_with_health, %{
              connected: apply(__MODULE__, :connected?, [state]),
              connection_state: connection_state,
              connection_uptime_seconds: apply(__MODULE__, :connection_uptime, [state])
            })
          else
            status_with_health
          end

        # Merge with service-specific status if the service implements do_build_status
        if function_exported?(__MODULE__, :do_build_status, 1) do
          Map.merge(status_with_connection, apply(__MODULE__, :do_build_status, [state]))
        else
          status_with_connection
        end
      end

      defp calculate_uptime(state) do
        case Map.get(state, :__service_meta__, %{})[:started_at] do
          nil -> 0
          started_at -> DateTime.diff(DateTime.utc_now(), started_at)
        end
      end
    end
  end
end

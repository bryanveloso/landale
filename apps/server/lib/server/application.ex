defmodule Server.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Validate all required configuration is present - fail fast if missing
    if Application.get_env(:server, :env) != :test do
      Server.Config.validate_all!()
    end

    # Set up graceful shutdown handling for Docker (skip in test environment)
    if Application.get_env(:server, :env) != :test do
      setup_signal_handlers()
    end

    # Base children for all environments
    base_children = [
      ServerWeb.Telemetry,
      Server.Repo,
      {DNSCluster, query: Application.get_env(:server, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Server.PubSub},
      # Start to serve requests, typically the last entry
      ServerWeb.Endpoint
    ]

    # Add production services only in non-test environments
    children =
      if Application.get_env(:server, :env) == :test do
        base_children
      else
        base_children ++
          [
            # Task supervision for async operations
            {Task.Supervisor, name: Server.TaskSupervisor},
            # Dynamic supervisor for async database writes with concurrency limit
            {DynamicSupervisor, name: Server.DBTaskSupervisor, strategy: :one_for_one, max_children: 10},
            # Dynamic supervisor for runtime-started services
            {DynamicSupervisor, name: Server.DynamicSupervisor, strategy: :one_for_one},
            # Performance optimizations
            Server.CorrelationIdPool,
            Server.Events.BatchPublisher,
            Server.Cache,
            # Circuit breakers for external service resilience
            Server.CircuitBreakerServer,
            # Service registry for unified service discovery
            Server.ServiceRegistry,
            # Stream coordination
            Server.ContentAggregator,
            Server.StreamProducer,
            # IronMON tracking
            Server.Ironmon.RunTracker,
            # Subscription monitoring
            {Server.SubscriptionStorage, [name: :subscriptions]},
            {Server.SubscriptionMonitor, [storage: :subscriptions]},
            # OAuth service (must start before services that depend on it)
            Server.OAuthService,
            # Services
            Server.Services.OBS,
            Server.Services.Twitch,
            # Twitch API client (requires OAuth to be started first)
            {Server.Services.Twitch.ApiClient,
             [
               user_id: System.get_env("TWITCH_USER_ID") || Application.get_env(:server, :twitch_user_id)
             ]},
            {Server.Services.IronmonTCP, [port: Application.get_env(:server, :ironmon_tcp_port, 8080)]},
            Server.Services.Rainwave
          ]
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Server.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, _pid} = result ->
        Logger.info("Server application started successfully")

        # Register services with the registry in non-test environments
        if Application.get_env(:server, :env) != :test do
          register_services()
        end

        result

      {:error, reason} = error ->
        Logger.error("Failed to start server application", reason: reason)
        error
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @impl true
  def prep_stop(_state) do
    Logger.info("Server application preparing to stop")

    # Gracefully stop services before supervision tree shutdown
    graceful_service_shutdown()

    :ok
  end

  @impl true
  def stop(_state) do
    Logger.info("Server application stopped")
    :ok
  end

  # Private functions for graceful shutdown

  defp setup_signal_handlers do
    # Handle SIGTERM gracefully (Docker sends this for shutdown)
    # Note: Signal names vary by OTP version, using try/catch for compatibility
    :os.set_signal(:sigterm, :handle)
    :os.set_signal(:sigint, :handle)
    # Spawn a process to handle signals
    spawn_link(fn -> signal_handler_loop() end)
  rescue
    ArgumentError ->
      Logger.warning("Signal handling not available on this platform")
  end

  defp signal_handler_loop do
    receive do
      {:signal, :sigterm} ->
        Logger.info("Received SIGTERM, initiating graceful shutdown")
        graceful_shutdown()

      {:signal, :sigint} ->
        Logger.info("Received SIGINT, initiating graceful shutdown")
        graceful_shutdown()

      other ->
        Logger.debug("Signal handler received: #{inspect(other)}")
        signal_handler_loop()
    end
  end

  defp graceful_shutdown do
    Logger.info("Starting graceful shutdown sequence")

    # Stop accepting new connections
    # ServerWeb.Endpoint.stop()

    # Wait a moment for in-flight requests to complete
    Process.sleep(1000)

    # Stop the application
    System.stop(0)
  end

  defp graceful_service_shutdown do
    # Allow services to clean up their resources
    services = [Server.Services.OBS, Server.Services.Twitch, Server.Services.IronmonTCP, Server.Services.Rainwave]

    Enum.each(services, fn service ->
      try do
        if Process.whereis(service) do
          Logger.info("Gracefully stopping service", service: service)
          GenServer.stop(service, :normal, Server.NetworkConfig.connection_timeout_ms())
        end
      rescue
        error ->
          Logger.warning("Error stopping service", service: service, error: inspect(error))
      end
    end)
  end

  defp register_services do
    # List of services to register
    services = [
      Server.Services.OBS,
      Server.Services.Twitch,
      Server.Services.IronmonTCP,
      Server.Services.Rainwave
    ]

    # Wait for each service to be ready and register it
    Enum.each(services, fn service_module ->
      case wait_for_service(service_module, 5000) do
        {:ok, pid} ->
          case Server.ServiceRegistry.register(service_module, pid) do
            :ok ->
              Logger.debug("Service registered with ServiceRegistry", service: service_module)

            {:error, reason} ->
              Logger.error("Failed to register service",
                service: service_module,
                reason: inspect(reason)
              )
          end

        {:error, :timeout} ->
          Logger.warning("Service not available for registration", service: service_module)
      end
    end)
  end

  defp wait_for_service(service_module, timeout) do
    start_time = System.monotonic_time(:millisecond)
    wait_for_service_loop(service_module, start_time, timeout)
  end

  defp wait_for_service_loop(service_module, start_time, timeout) do
    case Process.whereis(service_module) do
      nil ->
        current_time = System.monotonic_time(:millisecond)

        if current_time - start_time >= timeout do
          {:error, :timeout}
        else
          Process.sleep(50)
          wait_for_service_loop(service_module, start_time, timeout)
        end

      pid ->
        # Additional check to ensure the service is actually ready
        try do
          # Try a simple call to verify the service is responsive
          case GenServer.call(pid, :get_status, 1000) do
            {:ok, _status} -> {:ok, pid}
            # Even if status call fails, register the service
            _ -> {:ok, pid}
          end
        catch
          # Fallback - register anyway
          _, _ -> {:ok, pid}
        end
    end
  end
end

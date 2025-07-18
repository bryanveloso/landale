defmodule Server.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
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
            # Dynamic supervisor for runtime-started services
            {DynamicSupervisor, name: Server.DynamicSupervisor, strategy: :one_for_one},
            # Performance optimizations
            Server.CorrelationIdPool,
            Server.Events.BatchPublisher,
            Server.Cache,
            # Circuit breakers for external service resilience
            Server.CircuitBreakerRegistry,
            # Stream coordination
            Server.ContentAggregator,
            Server.StreamProducer,
            # Subscription monitoring
            {Server.SubscriptionStorage, [name: :subscriptions]},
            {Server.SubscriptionMonitor, [storage: :subscriptions]},
            # Services
            Server.Services.OBS,
            Server.Services.Twitch,
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
end

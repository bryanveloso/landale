defmodule Server.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Set up graceful shutdown handling for Docker
    setup_signal_handlers()

    children = [
      ServerWeb.Telemetry,
      Server.Repo,
      {DNSCluster, query: Application.get_env(:server, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Server.PubSub},
      # Services
      Server.Services.OBS,
      Server.Services.Twitch,
      # Start to serve requests, typically the last entry
      ServerWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Server.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} = result ->
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
    :os.set_signal(:sigterm, :handle)
    :os.set_signal(:sigint, :handle)

    # Spawn a process to handle signals
    spawn_link(fn -> signal_handler_loop() end)
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
    ServerWeb.Endpoint.stop()

    # Wait a moment for in-flight requests to complete
    Process.sleep(1000)

    # Stop the application
    System.stop(0)
  end

  defp graceful_service_shutdown do
    # Allow services to clean up their resources
    services = [Server.Services.OBS, Server.Services.Twitch]

    Enum.each(services, fn service ->
      try do
        if Process.whereis(service) do
          Logger.info("Gracefully stopping service", service: service)
          GenServer.stop(service, :normal, 5000)
        end
      rescue
        error ->
          Logger.warning("Error stopping service", service: service, error: inspect(error))
      end
    end)
  end
end

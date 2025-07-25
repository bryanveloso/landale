defmodule Server.OAuthService do
  @moduledoc """
  Centralized OAuth token management service.

  Manages OAuth tokens for multiple services (Twitch, Discord, etc.) in a single
  GenServer, providing automatic refresh, persistent storage, and a clean API.

  ## Features
  - Multi-service token management
  - Automatic token refresh before expiration
  - Persistent storage using DETS
  - Telemetry integration
  - Service isolation (tokens are namespaced by service)

  ## Usage

      # Register a service
      OAuthService.register_service(:twitch, %{
        client_id: "...",
        client_secret: "...",
        auth_url: "https://id.twitch.tv/oauth2/authorize",
        token_url: "https://id.twitch.tv/oauth2/token",
        validate_url: "https://id.twitch.tv/oauth2/validate"
      })
      
      # Store tokens for a service
      OAuthService.store_tokens(:twitch, %{
        access_token: "...",
        refresh_token: "...",
        expires_at: ~U[2024-07-26 12:00:00Z]
      })
      
      # Get valid token (auto-refreshes if needed)
      {:ok, token} = OAuthService.get_valid_token(:twitch)
  """

  use Server.Service,
    service_name: "oauth",
    behaviour: Server.Services.OAuthServiceBehaviour

  use Server.Service.StatusReporter

  require Logger

  alias Server.{OAuthTokenManager, CorrelationId}

  # State structure
  defstruct [
    # Map of service_name => OAuthTokenManager state
    managers: %{},
    # Map of service_name => refresh timer reference
    refresh_timers: %{}
  ]

  # Client API

  @doc """
  Registers a new service for OAuth management.
  """
  @spec register_service(atom(), map()) :: :ok | {:error, term()}
  @impl true
  def register_service(service_name, config) do
    GenServer.call(__MODULE__, {:register_service, service_name, config})
  end

  @doc """
  Gets a valid token for the specified service, refreshing if necessary.
  """
  @spec get_valid_token(atom()) :: {:ok, map()} | {:error, term()}
  @impl true
  def get_valid_token(service_name) do
    GenServer.call(__MODULE__, {:get_valid_token, service_name})
  end

  @doc """
  Stores tokens for a service (e.g., after initial OAuth flow).
  """
  @spec store_tokens(atom(), map()) :: :ok | {:error, term()}
  @impl true
  def store_tokens(service_name, token_info) do
    GenServer.call(__MODULE__, {:store_tokens, service_name, token_info})
  end

  @doc """
  Refreshes tokens for a specific service.
  """
  @spec refresh_token(atom()) :: {:ok, map()} | {:error, term()}
  @impl true
  def refresh_token(service_name) do
    GenServer.call(__MODULE__, {:refresh_token, service_name})
  end

  @doc """
  Gets the current token info for a service without refreshing.
  """
  @spec get_token_info(atom()) :: {:ok, map()} | {:error, :not_found}
  @impl true
  def get_token_info(service_name) do
    GenServer.call(__MODULE__, {:get_token_info, service_name})
  end

  @doc """
  Validates tokens for a specific service.
  """
  @spec validate_token(atom()) :: {:ok, map()} | {:error, term()}
  @impl true
  def validate_token(service_name) do
    GenServer.call(__MODULE__, {:validate_token, service_name})
  end

  # ServiceBehaviour implementation

  @impl true
  def get_health do
    GenServer.call(__MODULE__, :get_health)
  end

  @impl true
  def get_info do
    %{
      name: "oauth",
      version: "1.0.0",
      capabilities: [:multi_service, :auto_refresh, :persistent_storage],
      description: "Centralized OAuth token management for multiple services"
    }
  end

  @impl true
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  # Server.Service callbacks

  @impl Server.Service
  def do_init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl Server.Service
  def do_terminate(_reason, state) do
    # Cancel all refresh timers
    Enum.each(state.refresh_timers, fn {_service, timer_ref} ->
      Process.cancel_timer(timer_ref)
    end)

    # Close all DETS tables
    Enum.each(state.managers, fn {_service, manager} ->
      OAuthTokenManager.close(manager)
    end)

    :ok
  end

  # StatusReporter implementation

  @impl Server.Service.StatusReporter
  def do_build_status(state) do
    services = Map.keys(state.managers)

    service_statuses =
      Enum.map(services, fn service ->
        manager = Map.get(state.managers, service)
        has_tokens = manager.token_info != nil

        token_status =
          if has_tokens do
            if token_needs_refresh?(manager.token_info, manager.refresh_buffer_ms) do
              :expired
            else
              :valid
            end
          else
            :no_tokens
          end

        {service, token_status}
      end)
      |> Map.new()

    %{
      registered_services: services,
      service_count: length(services),
      service_statuses: service_statuses,
      active_refresh_timers: map_size(state.refresh_timers)
    }
  end

  # Override from StatusReporter
  defp service_healthy?(state) do
    # Service is healthy if we have at least one registered service
    map_size(state.managers) > 0
  end

  # GenServer callbacks

  @impl GenServer
  def handle_call({:register_service, service_name, config}, _from, state) do
    correlation_id = CorrelationId.generate()

    CorrelationId.with_context(correlation_id, fn ->
      Logger.info("Registering OAuth service",
        service: service_name,
        has_validate_url: Map.has_key?(config, :validate_url)
      )

      # Create manager configuration
      manager_opts = [
        storage_key: :"#{service_name}_tokens",
        client_id: config.client_id,
        client_secret: config.client_secret,
        auth_url: config.auth_url,
        token_url: config.token_url,
        telemetry_prefix: [:server, service_name, :oauth]
      ]

      # Add optional validate URL
      manager_opts =
        if config[:validate_url] do
          Keyword.put(manager_opts, :validate_url, config.validate_url)
        else
          manager_opts
        end

      case OAuthTokenManager.new(manager_opts) do
        {:ok, manager} ->
          # Load existing tokens
          manager = OAuthTokenManager.load_tokens(manager)

          # Store manager in state
          new_state = %{state | managers: Map.put(state.managers, service_name, manager)}

          # Schedule refresh if we have tokens
          new_state = maybe_schedule_refresh(new_state, service_name)

          {:reply, :ok, new_state}

        {:error, reason} = error ->
          Logger.error("Failed to create OAuth manager",
            service: service_name,
            error: inspect(reason)
          )

          {:reply, error, state}
      end
    end)
  end

  @impl GenServer
  def handle_call({:get_valid_token, service_name}, _from, state) do
    case Map.get(state.managers, service_name) do
      nil ->
        {:reply, {:error, :service_not_registered}, state}

      manager ->
        case OAuthTokenManager.get_valid_token(manager) do
          {:ok, token, updated_manager} ->
            # Update manager in state
            new_managers = Map.put(state.managers, service_name, updated_manager)
            new_state = %{state | managers: new_managers}

            # Reschedule refresh
            new_state = maybe_schedule_refresh(new_state, service_name)

            {:reply, {:ok, token}, new_state}

          {:error, _reason} = error ->
            {:reply, error, state}
        end
    end
  end

  @impl GenServer
  def handle_call({:store_tokens, service_name, token_info}, _from, state) do
    case Map.get(state.managers, service_name) do
      nil ->
        {:reply, {:error, :service_not_registered}, state}

      manager ->
        updated_manager = OAuthTokenManager.set_token(manager, token_info)

        # Update manager in state
        new_managers = Map.put(state.managers, service_name, updated_manager)
        new_state = %{state | managers: new_managers}

        # Schedule refresh for new tokens
        new_state = maybe_schedule_refresh(new_state, service_name)

        {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_call({:refresh_token, service_name}, _from, state) do
    case Map.get(state.managers, service_name) do
      nil ->
        {:reply, {:error, :service_not_registered}, state}

      manager ->
        case OAuthTokenManager.refresh_token(manager) do
          {:ok, updated_manager} ->
            # Update manager in state
            new_managers = Map.put(state.managers, service_name, updated_manager)
            new_state = %{state | managers: new_managers}

            # Reschedule refresh
            new_state = maybe_schedule_refresh(new_state, service_name)

            # Return the refreshed token info
            {:reply, {:ok, updated_manager.token_info}, new_state}

          {:error, _reason} = error ->
            {:reply, error, state}
        end
    end
  end

  @impl GenServer
  def handle_call({:get_token_info, service_name}, _from, state) do
    case Map.get(state.managers, service_name) do
      nil ->
        {:reply, {:error, :service_not_registered}, state}

      manager ->
        if manager.token_info do
          {:reply, {:ok, manager.token_info}, state}
        else
          {:reply, {:error, :no_tokens}, state}
        end
    end
  end

  @impl GenServer
  def handle_call({:validate_token, service_name}, _from, state) do
    case Map.get(state.managers, service_name) do
      nil ->
        {:reply, {:error, :service_not_registered}, state}

      manager ->
        validate_url = manager.oauth2_client.validate_url

        case OAuthTokenManager.validate_token(manager, validate_url) do
          {:ok, token_info, updated_manager} ->
            # Update manager in state
            new_managers = Map.put(state.managers, service_name, updated_manager)
            new_state = %{state | managers: new_managers}

            {:reply, {:ok, token_info}, new_state}

          {:error, _reason} = error ->
            {:reply, error, state}
        end
    end
  end

  @impl GenServer
  def handle_call(:get_health, _from, state) do
    health_status = if service_healthy?(state), do: :healthy, else: :unhealthy

    # Check each service's token status
    service_checks =
      Enum.map(state.managers, fn {service, manager} ->
        status =
          cond do
            manager.token_info == nil -> :fail
            !token_needs_refresh?(manager.token_info, manager.refresh_buffer_ms) -> :pass
            true -> :warn
          end

        {service, status}
      end)
      |> Map.new()

    health_response = %{
      status: health_status,
      checks: service_checks,
      details: %{
        registered_services: Map.keys(state.managers),
        service_count: map_size(state.managers)
      }
    }

    {:reply, {:ok, health_response}, state}
  end

  @impl GenServer
  def handle_info({:refresh_token, service_name}, state) do
    Logger.info("Auto-refreshing OAuth token", service: service_name)

    case Map.get(state.managers, service_name) do
      nil ->
        # Service was unregistered
        {:noreply, state}

      manager ->
        case OAuthTokenManager.refresh_token(manager) do
          {:ok, updated_manager} ->
            # Update manager in state
            new_managers = Map.put(state.managers, service_name, updated_manager)
            new_state = %{state | managers: new_managers}

            # Reschedule refresh
            new_state = maybe_schedule_refresh(new_state, service_name)

            {:noreply, new_state}

          {:error, reason} ->
            Logger.error("OAuth token refresh failed",
              service: service_name,
              error: inspect(reason)
            )

            # Retry in 5 minutes
            timer_ref = Process.send_after(self(), {:refresh_token, service_name}, 300_000)
            new_timers = Map.put(state.refresh_timers, service_name, timer_ref)

            {:noreply, %{state | refresh_timers: new_timers}}
        end
    end
  end

  # Private helpers

  defp maybe_schedule_refresh(state, service_name) do
    # Cancel existing timer if any
    state =
      case Map.get(state.refresh_timers, service_name) do
        nil ->
          state

        timer_ref ->
          Process.cancel_timer(timer_ref)
          %{state | refresh_timers: Map.delete(state.refresh_timers, service_name)}
      end

    # Schedule new refresh if we have tokens
    case Map.get(state.managers, service_name) do
      nil ->
        state

      manager ->
        if manager.token_info && manager.token_info.expires_at do
          # Calculate when to refresh (5 minutes before expiry)
          refresh_time = calculate_refresh_time(manager.token_info.expires_at)

          if refresh_time > 0 do
            timer_ref = Process.send_after(self(), {:refresh_token, service_name}, refresh_time)
            new_timers = Map.put(state.refresh_timers, service_name, timer_ref)

            Logger.debug("Scheduled OAuth refresh",
              service: service_name,
              refresh_in_ms: refresh_time
            )

            %{state | refresh_timers: new_timers}
          else
            # Token already expired, refresh immediately
            send(self(), {:refresh_token, service_name})
            state
          end
        else
          state
        end
    end
  end

  defp calculate_refresh_time(expires_at) do
    # Refresh 5 minutes before expiry
    buffer_ms = 300_000

    expires_ms = DateTime.to_unix(expires_at, :millisecond)
    now_ms = System.system_time(:millisecond)

    max(0, expires_ms - now_ms - buffer_ms)
  end

  defp token_needs_refresh?(nil, _buffer_ms), do: true

  defp token_needs_refresh?(token_info, buffer_ms) do
    case token_info.expires_at do
      nil ->
        false

      expires_at ->
        now = DateTime.utc_now()
        buffer_seconds = div(buffer_ms, 1000)
        DateTime.compare(now, DateTime.add(expires_at, -buffer_seconds, :second)) == :gt
    end
  end
end

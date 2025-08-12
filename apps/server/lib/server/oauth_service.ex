defmodule Server.OAuthService do
  @moduledoc """
  Centralized OAuth token management service.

  Manages OAuth tokens for multiple services (Twitch, Discord, etc.) in a single
  GenServer, providing automatic refresh and persistent storage via PostgreSQL.

  ## Features
  - Multi-service token management
  - Automatic token refresh before expiration
  - Persistent storage using PostgreSQL
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

  alias Server.{CircuitBreakerServer, CorrelationId, OAuthTokenRepository}

  # Configuration constants
  # 5 minutes before expiry
  @default_refresh_buffer_ms 300_000
  # 1 minute initial retry delay
  @retry_base_delay_ms 60_000
  # 1 hour max retry delay
  @retry_max_delay_ms 3_600_000
  # 15 seconds for token requests
  @token_request_timeout_ms 15_000
  # 10 seconds for validation requests
  @validate_request_timeout_ms 10_000

  # State structure
  defstruct [
    # Map of service_name => OAuth config
    configs: %{},
    # Map of service_name => refresh timer reference
    refresh_timers: %{},
    # Map of service_name => retry count for exponential backoff
    retry_counts: %{},
    # Map of service_name => true/false for refresh in progress
    refresh_locks: %{},
    # Map of service_name => list of waiting callers during refresh
    refresh_waiters: %{}
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
  Validates the current token for a service.
  """
  @spec validate_token(atom()) :: {:ok, map()} | {:error, term()}
  @impl true
  def validate_token(service_name) do
    GenServer.call(__MODULE__, {:validate_token, service_name})
  end

  @doc """
  Gets the health status of the OAuth service.
  """
  @spec get_health() :: {:ok, map()} | {:error, term()}
  @impl true
  def get_health do
    GenServer.call(__MODULE__, :get_health)
  end

  @doc """
  Gets general info about the OAuth service.
  """
  @spec get_info() :: {:ok, map()}
  @impl true
  def get_info do
    GenServer.call(__MODULE__, :get_info)
  end

  @doc """
  Gets the current status of the OAuth service.
  """
  @spec get_status() :: {:ok, map()} | {:error, term()}
  @impl true
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  # Server implementation

  @impl Server.Service
  def do_init(_args) do
    Logger.info("OAuthService starting")

    state = %__MODULE__{
      configs: %{},
      refresh_timers: %{},
      retry_counts: %{}
    }

    # Auto-register Twitch service if configured
    final_state =
      case build_twitch_config() do
        nil ->
          Logger.debug("Twitch OAuth config not available, skipping auto-registration")
          state

        config ->
          {:ok, new_state} = register_twitch_service(state, config)
          Logger.info("Twitch OAuth service auto-registered successfully")
          new_state
      end

    {:ok, final_state}
  end

  defp register_twitch_service(state, config) do
    # Store config for the service
    new_configs = Map.put(state.configs, :twitch, config)
    new_state = %{state | configs: new_configs}

    # Load any existing tokens from database
    new_state = load_existing_tokens(new_state, :twitch)

    {:ok, new_state}
  end

  defp load_existing_tokens(state, service_name) do
    case OAuthTokenRepository.get_token(service_name) do
      {:ok, token_info} ->
        # Schedule refresh if needed
        maybe_schedule_refresh(state, service_name, token_info)

      {:error, :not_found} ->
        state
    end
  end

  defp build_twitch_config do
    client_id = System.get_env("TWITCH_CLIENT_ID")
    client_secret = System.get_env("TWITCH_CLIENT_SECRET")

    if client_id && client_secret do
      %{
        client_id: client_id,
        # Don't store client_secret in state - fetch from env when needed
        auth_url: "https://id.twitch.tv/oauth2/authorize",
        token_url: "https://id.twitch.tv/oauth2/token",
        validate_url: "https://id.twitch.tv/oauth2/validate",
        refresh_buffer_ms: @default_refresh_buffer_ms,
        required_scopes: [
          # Stream/channel management
          "channel:read:subscriptions",
          "channel:read:redemptions",
          "channel:read:polls",
          "channel:read:predictions",
          "channel:read:hype_train",
          "channel:read:goals",
          "channel:read:charity",
          "channel:read:vips",
          "channel:read:ads",
          "channel:manage:broadcast",
          "channel:manage:redemptions",
          "channel:manage:videos",
          "channel:manage:ads",
          "channel:edit:commercial",
          "channel:bot",
          # Moderation and chat
          "moderator:read:followers",
          "moderator:read:shoutouts",
          "moderator:read:chat_settings",
          "moderator:read:shield_mode",
          "moderator:read:banned_users",
          "moderator:read:moderators",
          "moderator:manage:announcements",
          "user:read:chat",
          "user:write:chat",
          "user:bot",
          "chat:read",
          "chat:edit",
          # Monetization
          "bits:read",
          # Content
          "clips:edit"
        ]
      }
    else
      nil
    end
  end

  @impl Server.Service
  def do_terminate(_reason, state) do
    # Cancel all refresh timers
    Enum.each(state.refresh_timers, fn {_service, timer_ref} ->
      Process.cancel_timer(timer_ref)
    end)

    :ok
  end

  # StatusReporter implementation

  @impl Server.Service.StatusReporter
  def do_build_status(state) do
    services = Map.keys(state.configs)

    service_statuses =
      Enum.map(services, fn service ->
        token_status =
          case OAuthTokenRepository.get_token(service) do
            {:ok, token_info} ->
              if token_needs_refresh?(token_info) do
                :expired
              else
                :valid
              end

            {:error, :not_found} ->
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
    map_size(state.configs) > 0
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

      # Store config for the service
      new_configs = Map.put(state.configs, service_name, config)
      new_state = %{state | configs: new_configs}

      # Load any existing tokens
      new_state = load_existing_tokens(new_state, service_name)

      {:reply, :ok, new_state}
    end)
  end

  @impl GenServer
  def handle_call({:get_valid_token, service_name}, from, state) do
    with {:ok, _config} <- Map.fetch(state.configs, service_name),
         {:ok, token_info} <- OAuthTokenRepository.get_token(service_name) do
      if token_needs_refresh?(token_info) do
        # Check if refresh is already in progress
        if Map.get(state.refresh_locks, service_name, false) do
          # Add caller to waiters list
          waiters = Map.get(state.refresh_waiters, service_name, [])
          new_waiters = Map.put(state.refresh_waiters, service_name, [from | waiters])

          Logger.debug("Token refresh already in progress, queueing caller",
            service: service_name,
            waiters_count: length(waiters) + 1
          )

          # Don't reply now, will reply when refresh completes
          {:noreply, %{state | refresh_waiters: new_waiters}}
        else
          # Acquire refresh lock
          new_state = %{state | refresh_locks: Map.put(state.refresh_locks, service_name, true)}

          case do_refresh_token(service_name, new_state) do
            {:ok, refreshed_token, final_state} ->
              # Release lock and notify waiters
              final_state = release_refresh_lock(final_state, service_name, {:ok, refreshed_token})
              {:reply, {:ok, refreshed_token}, final_state}

            {:error, reason} ->
              # Release lock and notify waiters of error
              final_state = release_refresh_lock(new_state, service_name, {:error, reason})
              {:reply, {:error, reason}, final_state}
          end
        end
      else
        {:reply, {:ok, token_info}, state}
      end
    else
      :error -> {:reply, {:error, :service_not_registered}, state}
      {:error, :not_found} -> {:reply, {:error, :no_tokens}, state}
    end
  end

  @impl GenServer
  def handle_call({:store_tokens, service_name, token_info}, _from, state) do
    case Map.get(state.configs, service_name) do
      nil ->
        {:reply, {:error, :service_not_registered}, state}

      _config ->
        case OAuthTokenRepository.save_token(service_name, token_info) do
          {:ok, _} ->
            # Schedule refresh for new tokens
            new_state = maybe_schedule_refresh(state, service_name, token_info)
            {:reply, :ok, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl GenServer
  def handle_call({:refresh_token, service_name}, _from, state) do
    case do_refresh_token(service_name, state) do
      {:ok, refreshed_token, new_state} ->
        # Track successful refresh in monitor
        if Process.whereis(Server.OAuthMonitor) do
          Server.OAuthMonitor.record_refresh_success(
            service_name,
            refreshed_token.expires_at
          )
        end

        {:reply, {:ok, refreshed_token}, new_state}

      {:error, reason} ->
        # Track failed refresh in monitor
        if Process.whereis(Server.OAuthMonitor) do
          Server.OAuthMonitor.record_refresh_failure(service_name, reason)
        end

        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_token_info, service_name}, _from, state) do
    case Map.get(state.configs, service_name) do
      nil ->
        {:reply, {:error, :service_not_registered}, state}

      _config ->
        case OAuthTokenRepository.get_token(service_name) do
          {:ok, token_info} ->
            {:reply, {:ok, token_info}, state}

          {:error, :not_found} ->
            {:reply, {:error, :no_tokens}, state}
        end
    end
  end

  @impl GenServer
  def handle_call({:validate_token, service_name}, _from, state) do
    case Map.get(state.configs, service_name) do
      nil ->
        {:reply, {:error, :service_not_registered}, state}

      config ->
        case OAuthTokenRepository.get_token(service_name) do
          {:ok, token_info} ->
            case validate_token_with_api(token_info, config) do
              {:ok, validation_info} ->
                {:reply, {:ok, validation_info}, state}

              {:error, reason} ->
                {:reply, {:error, reason}, state}
            end

          {:error, :not_found} ->
            {:reply, {:error, :no_tokens}, state}
        end
    end
  end

  @impl GenServer
  def handle_call(:get_health, _from, state) do
    health_status = if service_healthy?(state), do: :healthy, else: :unhealthy

    # Check each service's token status
    service_checks =
      Enum.map(state.configs, fn {service, _config} ->
        status =
          case OAuthTokenRepository.get_token(service) do
            {:ok, token_info} ->
              if token_needs_refresh?(token_info) do
                :warn
              else
                :pass
              end

            {:error, :not_found} ->
              :fail
          end

        {service, status}
      end)
      |> Map.new()

    health_response = %{
      status: health_status,
      checks: service_checks,
      details: %{
        registered_services: Map.keys(state.configs),
        service_count: map_size(state.configs)
      }
    }

    {:reply, {:ok, health_response}, state}
  end

  @impl GenServer
  def handle_call(:get_info, _from, state) do
    info = %{
      service: "OAuth Service",
      description: "Manages OAuth tokens for multiple services",
      registered_services: Map.keys(state.configs),
      active_timers: map_size(state.refresh_timers)
    }

    {:reply, {:ok, info}, state}
  end

  @impl GenServer
  def handle_info({:refresh_token, service_name}, state) do
    Logger.info("Auto-refreshing OAuth token", service: service_name)

    case do_refresh_token(service_name, state) do
      {:ok, _refreshed_token, new_state} ->
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("OAuth token refresh failed",
          service: service_name,
          error: inspect(reason)
        )

        # Implement exponential backoff with jitter
        retry_count = Map.get(state.retry_counts, service_name, 0)

        # Calculate exponential backoff with jitter
        delay = min(@retry_base_delay_ms * :math.pow(2, retry_count), @retry_max_delay_ms)
        jitter = :rand.uniform(round(delay * 0.1))
        final_delay = round(delay + jitter)

        # Schedule retry
        timer_ref = Process.send_after(self(), {:refresh_token, service_name}, final_delay)

        # Update state with new timer and retry count
        new_timers = Map.put(state.refresh_timers, service_name, timer_ref)
        new_retry_counts = Map.put(state.retry_counts, service_name, retry_count + 1)

        new_state = %{state | refresh_timers: new_timers, retry_counts: new_retry_counts}

        {:noreply, new_state}
    end
  end

  # Private helpers

  defp release_refresh_lock(state, service_name, result) do
    # Release the lock
    new_locks = Map.delete(state.refresh_locks, service_name)

    # Get and notify all waiters
    waiters = Map.get(state.refresh_waiters, service_name, [])
    new_waiters = Map.delete(state.refresh_waiters, service_name)

    # Reply to all waiting callers
    Enum.each(waiters, fn from ->
      GenServer.reply(from, result)
    end)

    if length(waiters) > 0 do
      Logger.debug("Notified waiting callers after token refresh",
        service: service_name,
        waiters_count: length(waiters),
        result: elem(result, 0)
      )
    end

    %{state | refresh_locks: new_locks, refresh_waiters: new_waiters}
  end

  defp do_refresh_token(service_name, state) do
    with {:ok, config} <- Map.fetch(state.configs, service_name),
         {:ok, current_token} <- OAuthTokenRepository.get_token(service_name),
         {:ok, new_token_data} <- refresh_token_via_api(current_token, config),
         {:ok, _} <- OAuthTokenRepository.save_token(service_name, new_token_data) do
      # Reschedule refresh
      new_state = maybe_schedule_refresh(state, service_name, new_token_data)

      # Reset retry count on successful refresh
      new_retry_counts = Map.delete(state.retry_counts, service_name)
      new_state = %{new_state | retry_counts: new_retry_counts}

      {:ok, new_token_data, new_state}
    else
      :error ->
        {:error, :service_not_registered}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp refresh_token_via_api(current_token, config) do
    # Fetch client secret from environment at runtime for security
    client_secret = System.get_env("TWITCH_CLIENT_SECRET")

    params = %{
      "client_id" => config.client_id,
      "client_secret" => client_secret,
      "grant_type" => "refresh_token",
      "refresh_token" => current_token.refresh_token
    }

    case CircuitBreakerServer.call("oauth_refresh", fn ->
           make_token_request(config.token_url, params)
         end) do
      {:ok, response} ->
        # Calculate new expiry
        expires_at = DateTime.add(DateTime.utc_now(), response["expires_in"], :second)

        {:ok,
         %{
           access_token: response["access_token"],
           refresh_token: response["refresh_token"] || current_token.refresh_token,
           expires_at: expires_at,
           scopes: parse_scopes(response["scope"])
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_token_with_api(token_info, config) do
    headers = [
      {"authorization", "Bearer #{token_info.access_token}"},
      {"accept", "application/json"}
    ]

    case CircuitBreakerServer.call("oauth_validate", fn ->
           make_get_request(config.validate_url, headers)
         end) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp make_token_request(url, params) do
    headers = [
      {"content-type", "application/x-www-form-urlencoded"},
      {"accept", "application/json"}
    ]

    body = URI.encode_query(params)
    uri = URI.parse(url)

    with {:ok, conn} <- open_gun_connection(uri),
         {:ok, response} <- post_and_await_response(conn, uri.path || "/", headers, body) do
      {:ok, response}
    end
  end

  defp open_gun_connection(uri) do
    host = uri.host |> String.to_charlist()
    port = uri.port || 443
    :gun.open(host, port, %{protocols: [:http2], transport: :tls})
  end

  defp post_and_await_response(conn, path, headers, body) do
    stream_ref = :gun.post(conn, String.to_charlist(path), headers, body)

    case :gun.await(conn, stream_ref, @token_request_timeout_ms) do
      {:response, :fin, status, _headers} ->
        :gun.close(conn)
        {:error, {:http_error, status, "No response body"}}

      {:response, :nofin, status, _headers} ->
        handle_response_body(conn, stream_ref, status)

      {:error, reason} ->
        :gun.close(conn)
        {:error, {:network_error, reason}}
    end
  end

  defp handle_response_body(conn, stream_ref, status) do
    case :gun.await_body(conn, stream_ref, @token_request_timeout_ms) do
      {:ok, response_body} ->
        :gun.close(conn)
        decode_and_handle_json(response_body, status)

      {:error, reason} ->
        :gun.close(conn)
        {:error, {:network_error, reason}}
    end
  end

  defp decode_and_handle_json(response_body, status) do
    case JSON.decode(response_body) do
      {:ok, json} when status >= 200 and status < 300 ->
        {:ok, json}

      {:ok, json} ->
        {:error, {:http_error, status, json}}

      {:error, _} ->
        {:error, {:http_error, status, response_body}}
    end
  end

  defp make_get_request(url, headers) do
    uri = URI.parse(url)

    with {:ok, conn} <- open_gun_connection(uri),
         {:ok, response} <- get_and_await_response(conn, uri.path || "/", headers) do
      response
    end
  end

  defp get_and_await_response(conn, path, headers) do
    stream_ref = :gun.get(conn, String.to_charlist(path), headers)

    case :gun.await(conn, stream_ref, @validate_request_timeout_ms) do
      {:response, :fin, status, _headers} ->
        :gun.close(conn)
        {:error, {:http_error, status, "No response body"}}

      {:response, :nofin, status, _headers} ->
        handle_get_response_body(conn, stream_ref, status)

      {:error, reason} ->
        :gun.close(conn)
        {:error, {:network_error, reason}}
    end
  end

  defp handle_get_response_body(conn, stream_ref, status) do
    case :gun.await_body(conn, stream_ref, @validate_request_timeout_ms) do
      {:ok, response_body} ->
        :gun.close(conn)
        decode_and_handle_json(response_body, status)

      {:error, reason} ->
        :gun.close(conn)
        {:error, {:network_error, reason}}
    end
  end

  defp token_needs_refresh?(token_info, buffer_ms \\ @default_refresh_buffer_ms) do
    case token_info.expires_at do
      nil ->
        # Token without expiry doesn't need refresh
        false

      expires_at ->
        now = DateTime.utc_now()
        buffer = div(buffer_ms, 1000)
        threshold = DateTime.add(now, buffer, :second)

        DateTime.compare(expires_at, threshold) == :lt
    end
  end

  defp maybe_schedule_refresh(state, service_name, token_info) do
    # Cancel existing timer if any
    state =
      case Map.get(state.refresh_timers, service_name) do
        nil ->
          state

        timer_ref ->
          Process.cancel_timer(timer_ref)
          %{state | refresh_timers: Map.delete(state.refresh_timers, service_name)}
      end

    # Skip scheduling if token has no expiry date
    case token_info.expires_at do
      nil ->
        Logger.debug("Token has no expiry date, skipping refresh scheduling", service: service_name)
        state

      expires_at ->
        # Calculate when to refresh before expiry
        config = Map.get(state.configs, service_name)
        buffer_ms = Map.get(config || %{}, :refresh_buffer_ms, @default_refresh_buffer_ms)

        now = DateTime.utc_now()

        case DateTime.diff(expires_at, now, :millisecond) do
          diff when diff > buffer_ms ->
            # Schedule refresh
            refresh_in = diff - buffer_ms
            timer_ref = Process.send_after(self(), {:refresh_token, service_name}, refresh_in)

            new_timers = Map.put(state.refresh_timers, service_name, timer_ref)
            %{state | refresh_timers: new_timers}

          _ ->
            # Token already needs refresh, schedule immediately
            Process.send_after(self(), {:refresh_token, service_name}, 0)
            state
        end
    end
  end

  defp parse_scopes(nil), do: []
  defp parse_scopes(scope_string) when is_binary(scope_string), do: String.split(scope_string, " ")
  defp parse_scopes(scopes) when is_list(scopes), do: scopes
  defp parse_scopes(_), do: []
end

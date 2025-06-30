defmodule Server.Services.Twitch do
  @moduledoc """
  Twitch EventSub integration service using Gun WebSocket client and OAuth2 library.

  Provides comprehensive Twitch EventSub WebSocket functionality:
  - OAuth2 token management with DETS persistence and auto-refresh
  - WebSocket session and subscription management  
  - Event processing and normalization
  - Phoenix PubSub integration for real-time distribution
  - Follows Twitch EventSub WebSocket protocol
  """

  use GenServer
  require Logger

  # Twitch EventSub constants
  @eventsub_websocket_url "wss://eventsub.wss.twitch.tv/ws"
  # 5 seconds
  @reconnect_interval 5_000
  # 5 minutes before expiry
  @token_refresh_buffer 300_000

  defstruct [
    :conn_pid,
    :stream_ref,
    :session_id,
    :reconnect_timer,
    :token_refresh_timer,
    :token_table,
    :oauth_client,
    :pending_subscriptions,
    :user_id,
    :scopes,
    subscriptions: %{},
    state: %{
      connection: %{
        connected: false,
        connection_state: "disconnected",
        last_error: nil,
        last_connected: nil,
        session_id: nil
      },
      subscription_total_cost: 0,
      # Twitch limit per connection
      subscription_max_cost: 10,
      subscription_count: 0,
      # Twitch limit per WebSocket connection
      subscription_max_count: 300
    }
  ]

  # Client API

  @doc """
  Starts the Twitch EventSub service GenServer.

  ## Parameters
  - `opts` - Keyword list of options (optional)
    - `:client_id` - Twitch application client ID
    - `:client_secret` - Twitch application client secret

  ## Returns
  - `{:ok, pid}` on success
  - `{:error, reason}` on failure
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current internal state of the Twitch service.

  ## Returns
  - Map containing connection, subscriptions, and EventSub state
  """
  @spec get_state() :: map()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Gets the current status of the Twitch service.

  ## Returns
  - `{:ok, status}` where status contains connection and subscription information
  - `{:error, reason}` if service is unavailable
  """
  @spec get_status() :: {:ok, map()} | {:error, binary()}
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Creates a new Twitch EventSub subscription.

  ## Parameters
  - `event_type` - The EventSub event type (e.g. "channel.update")
  - `condition` - Map of conditions for the subscription
  - `opts` - Additional options (optional)

  ## Returns
  - `{:ok, subscription}` on success
  - `{:error, reason}` if creation fails or limits exceeded
  """
  @spec create_subscription(binary(), map(), keyword()) :: {:ok, map()} | {:error, binary()}
  def create_subscription(event_type, condition, opts \\ []) do
    GenServer.call(__MODULE__, {:create_subscription, event_type, condition, opts})
  end

  @doc """
  Deletes an existing Twitch EventSub subscription.

  ## Parameters
  - `subscription_id` - The ID of the subscription to delete

  ## Returns
  - `:ok` on success
  - `{:error, reason}` if deletion fails
  """
  @spec delete_subscription(binary()) :: :ok | {:error, binary()}
  def delete_subscription(subscription_id) do
    GenServer.call(__MODULE__, {:delete_subscription, subscription_id})
  end

  @doc """
  Lists all active Twitch EventSub subscriptions.

  ## Returns
  - `{:ok, subscriptions}` where subscriptions is a list of subscription maps
  - `{:error, reason}` if service is unavailable
  """
  @spec list_subscriptions() :: {:ok, list(map())} | {:error, binary()}
  def list_subscriptions do
    GenServer.call(__MODULE__, :list_subscriptions)
  end

  # GenServer callbacks
  @impl GenServer
  def init(opts) do
    client_id = Keyword.get(opts, :client_id) || get_client_id()
    client_secret = Keyword.get(opts, :client_secret) || get_client_secret()

    # Ensure we have required credentials
    if !client_id || !client_secret do
      Logger.error("Twitch service missing required credentials",
        has_client_id: client_id != nil,
        has_client_secret: client_secret != nil
      )
    end

    # Open DETS table for token persistence
    table_path = get_token_storage_path()
    {:ok, token_table} = :dets.open_file(:twitch_tokens, file: String.to_charlist(table_path))

    # Create OAuth2 client
    oauth_client =
      OAuth2.Client.new(
        strategy: OAuth2.Strategy.Refresh,
        client_id: client_id,
        client_secret: client_secret,
        site: "https://id.twitch.tv",
        authorize_url: "https://id.twitch.tv/oauth2/authorize",
        token_url: "https://id.twitch.tv/oauth2/token"
      )

    state = %__MODULE__{
      token_table: token_table,
      oauth_client: oauth_client,
      pending_subscriptions: MapSet.new(),
      subscriptions: %{}
    }

    Logger.info("Twitch service starting", client_id: client_id)

    # Load existing tokens and initialize
    send(self(), :load_tokens)

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state.state, state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = %{
      connected: state.state.connection.connected,
      connection_state: state.state.connection.connection_state,
      session_id: state.state.connection.session_id,
      subscription_count: map_size(state.subscriptions),
      subscription_cost: state.state.subscription_total_cost
    }

    {:reply, {:ok, status}, state}
  end

  @impl GenServer
  def handle_call({:create_subscription, event_type, condition, opts}, _from, state) do
    if state.state.connection.connected && state.session_id do
      # Check subscription limits before creating
      if state.state.subscription_count >= state.state.subscription_max_count do
        {:reply, {:error, "Subscription count limit exceeded (#{state.state.subscription_max_count})"}, state}
      else
        # Check for duplicate subscription
        existing_key = generate_subscription_key(event_type, condition)

        existing_subscription =
          Enum.find(state.subscriptions, fn {_id, sub} ->
            generate_subscription_key(sub["type"], sub["condition"]) == existing_key
          end)

        if existing_subscription do
          {id, subscription} = existing_subscription

          Logger.warning("Duplicate subscription attempt",
            event_type: event_type,
            existing_id: id,
            condition: condition
          )

          {:reply, {:ok, subscription}, state}
        else
          case create_eventsub_subscription(state, event_type, condition, opts) do
            {:ok, subscription} ->
              # Store the subscription and update counters
              new_subscriptions = Map.put(state.subscriptions, subscription["id"], subscription)
              cost = subscription["cost"] || 1

              new_state = %{
                state
                | subscriptions: new_subscriptions,
                  state: %{
                    state.state
                    | subscription_total_cost: state.state.subscription_total_cost + cost,
                      subscription_count: state.state.subscription_count + 1
                  }
              }

              {:reply, {:ok, subscription}, new_state}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        end
      end
    else
      {:reply, {:error, "WebSocket not connected"}, state}
    end
  end

  @impl GenServer
  def handle_call({:delete_subscription, subscription_id}, _from, state) do
    case delete_eventsub_subscription(state, subscription_id) do
      :ok ->
        # Remove from local state and update counters
        deleted_subscription = Map.get(state.subscriptions, subscription_id)
        cost = if deleted_subscription, do: deleted_subscription["cost"] || 1, else: 0

        new_subscriptions = Map.delete(state.subscriptions, subscription_id)

        new_state = %{
          state
          | subscriptions: new_subscriptions,
            state: %{
              state.state
              | subscription_total_cost: max(0, state.state.subscription_total_cost - cost),
                subscription_count: max(0, state.state.subscription_count - 1)
            }
        }

        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:list_subscriptions, _from, state) do
    {:reply, {:ok, state.subscriptions}, state}
  end

  @impl GenServer
  def handle_info(:load_tokens, state) do
    case load_tokens_from_storage(state.token_table) do
      {:ok, token_data} ->
        Logger.info("Twitch OAuth tokens loaded from storage")

        # Create OAuth2 client with loaded tokens
        token =
          OAuth2.AccessToken.new(%{
            "access_token" => token_data.access_token,
            "refresh_token" => token_data.refresh_token,
            "expires_at" => token_data.expires_at
          })

        oauth_client =
          OAuth2.Client.new(
            strategy: OAuth2.Strategy.Refresh,
            client_id: state.oauth_client.client_id,
            client_secret: state.oauth_client.client_secret,
            site: "https://id.twitch.tv",
            authorize_url: "https://id.twitch.tv/oauth2/authorize",
            token_url: "https://id.twitch.tv/oauth2/token",
            token: token
          )

        Logger.debug("Twitch OAuth client created",
          has_token: oauth_client.token != nil,
          token_present: oauth_client.token.access_token != nil
        )

        state =
          %{state | oauth_client: oauth_client}
          |> schedule_token_refresh()

        # Validate token before attempting connection
        send(self(), :validate_token)

        {:noreply, state}

      {:error, "No tokens stored"} ->
        Logger.info("No stored tokens found, attempting migration from old file")

        case migrate_old_tokens() do
          {:ok, token_data} ->
            Logger.info("Successfully migrated tokens from old file")
            save_tokens_to_storage(state.token_table, token_data)

            # Create OAuth2 client with migrated tokens
            token =
              OAuth2.AccessToken.new(%{
                "access_token" => token_data.access_token,
                "refresh_token" => token_data.refresh_token,
                "expires_at" => token_data.expires_at
              })

            oauth_client =
              OAuth2.Client.new(
                strategy: OAuth2.Strategy.Refresh,
                client_id: state.oauth_client.client_id,
                client_secret: state.oauth_client.client_secret,
                site: "https://id.twitch.tv",
                authorize_url: "https://id.twitch.tv/oauth2/authorize",
                token_url: "https://id.twitch.tv/oauth2/token",
                token: token
              )

            Logger.debug("Twitch OAuth client created from migration",
              has_token: oauth_client.token != nil,
              token_present: oauth_client.token.access_token != nil
            )

            state =
              %{state | oauth_client: oauth_client}
              |> schedule_token_refresh()

            # Validate token before attempting connection
            send(self(), :validate_token)

            {:noreply, state}

          {:error, reason} ->
            Logger.warning("Twitch OAuth tokens not available", reason: reason)
            # Schedule retry
            timer = Process.send_after(self(), :load_tokens, @reconnect_interval)
            state = %{state | reconnect_timer: timer}
            {:noreply, state}
        end

      {:error, reason} ->
        Logger.error("Failed to load Twitch OAuth tokens", error: reason)
        # Schedule retry
        timer = Process.send_after(self(), :load_tokens, @reconnect_interval)
        state = %{state | reconnect_timer: timer}
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:connect, state) do
    case connect_websocket(state) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, new_state} ->
        # Schedule reconnect
        timer = Process.send_after(self(), :connect, @reconnect_interval)
        new_state = %{new_state | reconnect_timer: timer}
        {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_info(:validate_token, state) do
    case validate_twitch_token(state.oauth_client.token.access_token) do
      {:ok, token_info} ->
        Logger.info("Twitch token validation successful",
          user_id: token_info["user_id"],
          client_id: token_info["client_id"],
          scopes: length(token_info["scopes"] || [])
        )

        # Store user ID and scopes in state
        state = %{
          state
          | user_id: token_info["user_id"],
            scopes: MapSet.new(token_info["scopes"] || [])
        }

        send(self(), :connect)
        {:noreply, state}

      {:error, :invalid_token} ->
        Logger.info("Twitch token invalid, attempting refresh")
        send(self(), :refresh_token)
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Twitch token validation failed",
          error: reason,
          token_length:
            if(state.oauth_client.token,
              do: String.length(state.oauth_client.token.access_token),
              else: 0
            )
        )

        # Schedule retry
        timer = Process.send_after(self(), :validate_token, @reconnect_interval)
        state = %{state | reconnect_timer: timer}
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:refresh_token, state) do
    case refresh_oauth_tokens(state) do
      {:ok, new_state} ->
        Logger.info("Twitch OAuth tokens refreshed")
        new_state = schedule_token_refresh(new_state)
        # Validate new token after successful refresh
        send(self(), :validate_token)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Twitch OAuth token refresh failed", error: reason)
        # Try again in a shorter interval
        timer = Process.send_after(self(), :refresh_token, @reconnect_interval)
        state = %{state | token_refresh_timer: timer}
        {:noreply, state}
    end
  end

  # Gun WebSocket messages
  @impl GenServer
  def handle_info({:gun_upgrade, _conn_pid, stream_ref, ["websocket"], _headers}, state) do
    if stream_ref == state.stream_ref do
      Logger.info("Twitch WebSocket connection established")

      # Update connection state - wait for Welcome message before marking as connected
      state =
        update_connection_state(state, %{
          connection_state: "connecting"
        })

      # Publish connection event
      Server.Events.publish_twitch_event("connection_established", %{})

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:gun_ws, _conn_pid, stream_ref, {:text, message}}, state) do
    if stream_ref == state.stream_ref do
      state = handle_eventsub_message(state, message)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:gun_ws, _conn_pid, stream_ref, frame}, state) do
    if stream_ref == state.stream_ref do
      Logger.debug("Twitch WebSocket frame unhandled", frame: frame)
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:gun_down, conn_pid, _protocol, reason, _killed_streams}, state) do
    if conn_pid == state.conn_pid do
      Logger.warning("Twitch connection lost", reason: reason)

      # Update connection state
      state =
        update_connection_state(state, %{
          connected: false,
          connection_state: "disconnected",
          session_id: nil
        })
        |> cleanup_connection()

      # Publish disconnection event
      Server.Events.publish_twitch_event("connection_lost", %{})

      # Schedule reconnect
      timer = Process.send_after(self(), :connect, @reconnect_interval)
      state = %{state | reconnect_timer: timer}

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:gun_error, conn_pid, stream_ref, reason}, state) do
    if conn_pid == state.conn_pid && stream_ref == state.stream_ref do
      Logger.error("Twitch WebSocket stream error",
        conn_pid: inspect(conn_pid),
        stream_ref: inspect(stream_ref),
        reason: inspect(reason, pretty: true),
        error_type: elem(reason, 0)
      )

      state =
        update_connection_state(state, %{
          connected: false,
          connection_state: "error",
          last_error: inspect(reason)
        })
        |> cleanup_connection()

      # Schedule reconnect
      timer = Process.send_after(self(), :connect, @reconnect_interval)
      state = %{state | reconnect_timer: timer}

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:gun_error, conn_pid, reason}, state) do
    if conn_pid == state.conn_pid do
      Logger.error("Twitch connection error",
        conn_pid: inspect(conn_pid),
        reason: inspect(reason, pretty: true)
      )

      state =
        update_connection_state(state, %{
          connected: false,
          connection_state: "error",
          last_error: inspect(reason)
        })
        |> cleanup_connection()

      # Schedule reconnect
      timer = Process.send_after(self(), :connect, @reconnect_interval)
      state = %{state | reconnect_timer: timer}

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    if pid == state.conn_pid do
      Logger.info("Twitch connection process terminated", reason: reason)

      # Update connection state and schedule reconnect
      state =
        update_connection_state(state, %{
          connected: false,
          connection_state: "disconnected",
          session_id: nil
        })
        |> cleanup_connection()

      # Publish disconnection event
      Server.Events.publish_twitch_event("connection_lost", %{})

      # Schedule reconnect
      timer = Process.send_after(self(), :connect, @reconnect_interval)
      state = %{state | reconnect_timer: timer}

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:create_default_subscriptions, state) do
    if !state.user_id do
      Logger.error("Cannot create subscriptions: user_id not available")
      {:noreply, state}
    else
      # Create common Twitch EventSub subscriptions with scope validation
      default_subscriptions = [
        {"stream.online", %{"broadcaster_user_id" => state.user_id}, []},
        {"stream.offline", %{"broadcaster_user_id" => state.user_id}, []},
        {"channel.follow", %{"broadcaster_user_id" => state.user_id, "moderator_user_id" => state.user_id},
         ["moderator:read:followers"]},
        {"channel.subscribe", %{"broadcaster_user_id" => state.user_id}, ["channel:read:subscriptions"]},
        {"channel.subscription.gift", %{"broadcaster_user_id" => state.user_id}, ["channel:read:subscriptions"]},
        {"channel.cheer", %{"broadcaster_user_id" => state.user_id}, ["bits:read"]}
      ]

      {successful_count, failed_count} =
        Enum.reduce(default_subscriptions, {0, 0}, fn {event_type, condition, required_scopes}, {success, failed} ->
          if validate_scopes_for_subscription(state.scopes, required_scopes) do
            case create_eventsub_subscription(state, event_type, condition) do
              {:ok, subscription} ->
                Logger.info("Created default EventSub subscription",
                  event_type: event_type,
                  subscription_id: subscription["id"],
                  status: subscription["status"],
                  cost: subscription["cost"] || 1
                )

                {success + 1, failed}

              {:error, reason} ->
                Logger.warning("Failed to create default EventSub subscription",
                  event_type: event_type,
                  reason: reason
                )

                # For specific known issues, provide detailed guidance
                case event_type do
                  "channel.follow" ->
                    cond do
                      String.contains?(to_string(reason), "Forbidden") ->
                        Logger.info("Channel follow subscription failed",
                          reason: "Forbidden - broadcaster may need explicit moderator verification",
                          note: "This is common when using broadcaster token for moderator-required subscriptions",
                          workaround: "Consider obtaining separate moderator authorization or treating as optional"
                        )

                      String.contains?(to_string(reason), "unauthorized") ->
                        Logger.info("Channel follow subscription failed",
                          reason: "Unauthorized - token may need additional verification",
                          scope_present:
                            MapSet.member?(
                              state.scopes || MapSet.new(),
                              "moderator:read:followers"
                            )
                        )

                      true ->
                        Logger.info("Channel follow subscription failed",
                          reason: reason,
                          condition: inspect(condition),
                          user_id: state.user_id,
                          note: "Follow subscriptions require special broadcaster/moderator relationship"
                        )
                    end

                  _ ->
                    Logger.debug("Subscription failed for #{event_type}", reason: reason)
                end

                {success, failed + 1}
            end
          else
            Logger.warning("Skipping EventSub subscription due to missing scopes",
              event_type: event_type,
              required_scopes: required_scopes,
              available_scopes: MapSet.to_list(state.scopes || MapSet.new())
            )

            {success, failed + 1}
          end
        end)

      Logger.info("Default EventSub subscriptions complete",
        successful: successful_count,
        failed: failed_count,
        total_cost: state.state.subscription_total_cost,
        total_count: state.state.subscription_count
      )

      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:gun_response, conn_pid, stream_ref, _is_fin, status, headers}, state) do
    if conn_pid == state.conn_pid && stream_ref == state.stream_ref do
      if status != 101 do
        Logger.error("Twitch WebSocket upgrade failed",
          status: status,
          expected: 101,
          headers: inspect(headers)
        )

        # Store the error details in state
        state =
          update_connection_state(state, %{
            connected: false,
            connection_state: "upgrade_failed",
            last_error: "HTTP #{status} during WebSocket upgrade"
          })

        {:noreply, state}
      else
        Logger.debug("Twitch WebSocket upgrade successful", status: status)
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:gun_data, conn_pid, stream_ref, _is_fin, data}, state) do
    if conn_pid == state.conn_pid && stream_ref == state.stream_ref do
      data_str = if is_binary(data), do: data, else: List.to_string(data)

      # Only log if it's an error response (should be empty for successful WebSocket upgrade)
      if byte_size(data_str) > 0 do
        Logger.warning("Twitch unexpected HTTP response data",
          data_length: byte_size(data_str),
          data_preview: String.slice(data_str, 0, 100)
        )
      end
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(info, state) do
    Logger.warning("Gun message unhandled", message: inspect(info, pretty: true))
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    Logger.info("Twitch service terminating")

    # Cancel timers
    if state.reconnect_timer do
      Process.cancel_timer(state.reconnect_timer)
    end

    if state.token_refresh_timer do
      Process.cancel_timer(state.token_refresh_timer)
    end

    # Close DETS table on shutdown
    if state.token_table do
      :dets.close(state.token_table)
    end

    # Close WebSocket connection
    if state.conn_pid do
      :gun.close(state.conn_pid)
    end

    :ok
  end

  # WebSocket connection handling using Gun
  defp connect_websocket(state) do
    # Ensure we have a valid token before connecting
    if !state.oauth_client.token || !state.oauth_client.token.access_token do
      Logger.error("Twitch connection failed: no valid OAuth token")

      state =
        update_connection_state(state, %{
          connected: false,
          connection_state: "error",
          last_error: "No valid OAuth token"
        })

      {:error, state}
    else
      do_connect_websocket(state)
    end
  end

  defp do_connect_websocket(state) do
    uri = URI.parse(@eventsub_websocket_url)
    host = to_charlist(uri.host)
    port = uri.port || 443
    path = uri.path || "/ws"

    # Configure Gun with better TLS options for CloudFront compatibility
    gun_opts = %{
      transport: :tls,
      tls_opts: [
        # Ensure TLS 1.2+ compatibility
        {:versions, [:"tlsv1.2", :"tlsv1.3"]},
        # Verify peer certificate
        {:verify, :verify_peer},
        # Use system CA certificates
        {:cacerts, :public_key.cacerts_get()},
        # Set proper hostname for verification
        {:server_name_indication, to_charlist(uri.host)},
        {:customize_hostname_check,
         [
           {:match_fun, :public_key.pkix_verify_hostname_match_fun(:https)}
         ]}
      ],
      # Force HTTP/1.1 to avoid HTTP/2 issues with WebSocket
      protocols: [:http]
    }

    Logger.debug("Twitch Gun connection", host: uri.host, port: port, tls: true)

    case :gun.open(host, port, gun_opts) do
      {:ok, conn_pid} ->
        # Monitor the connection
        Process.monitor(conn_pid)

        case :gun.await_up(conn_pid, 10_000) do
          {:ok, _protocol} ->
            # Let Gun handle WebSocket headers automatically
            # Only add custom headers that don't interfere with WebSocket protocol
            headers = [
              {"user-agent", "Landale/1.0.0"}
            ]

            Logger.debug("Twitch WebSocket upgrade request",
              url: @eventsub_websocket_url,
              path: path
            )

            # Let Gun handle the WebSocket upgrade protocol correctly
            stream_ref = :gun.ws_upgrade(conn_pid, path, headers)

            Logger.debug("Twitch WebSocket upgrade initiated",
              conn_pid: inspect(conn_pid),
              stream_ref: inspect(stream_ref),
              path: path,
              has_token: state.oauth_client.token != nil,
              token_length: String.length(state.oauth_client.token.access_token || ""),
              client_id: state.oauth_client.client_id
            )

            new_state =
              %{state | conn_pid: conn_pid, stream_ref: stream_ref}
              |> update_connection_state(%{
                connection_state: "connecting"
              })

            {:ok, new_state}

          {:error, reason} ->
            Logger.error("Twitch connection failed during await_up", error: reason)
            :gun.close(conn_pid)

            state =
              update_connection_state(state, %{
                connected: false,
                connection_state: "error",
                last_error: inspect(reason)
              })

            {:error, state}
        end

      {:error, reason} ->
        Logger.error("Twitch connection failed during open", error: reason)

        state =
          update_connection_state(state, %{
            connected: false,
            connection_state: "error",
            last_error: inspect(reason)
          })

        {:error, state}
    end
  end

  # Configuration helpers
  defp get_client_id do
    app_config = Application.get_env(:server, :twitch_client_id)
    env_var = System.get_env("TWITCH_CLIENT_ID")
    result = app_config || env_var

    Logger.debug("Twitch client ID lookup",
      app_config: app_config != nil,
      env_var: env_var != nil,
      result: result != nil
    )

    result
  end

  defp get_client_secret do
    app_config = Application.get_env(:server, :twitch_client_secret)
    env_var = System.get_env("TWITCH_CLIENT_SECRET")
    result = app_config || env_var

    Logger.debug("Twitch client secret lookup",
      app_config: app_config != nil,
      env_var: env_var != nil,
      result: result != nil
    )

    result
  end

  # DETS token storage management
  defp load_tokens_from_storage(table) do
    case :dets.lookup(table, :oauth_tokens) do
      [{:oauth_tokens, tokens}] -> {:ok, tokens}
      [] -> {:error, "No tokens stored"}
    end
  end

  defp save_tokens_to_storage(table, tokens) do
    :dets.insert(table, {:oauth_tokens, tokens})
    # Ensure data is written to disk
    :dets.sync(table)
  end

  # Migrate tokens from old Twurple format
  defp migrate_old_tokens do
    old_file =
      "/Users/Avalonstar/Code/bryanveloso/landale/apps/server-old/src/services/twitch/twitch-token.json"

    case File.read(old_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok,
           %{
             "accessToken" => access,
             "refreshToken" => refresh,
             "expiresIn" => expires_in,
             "obtainmentTimestamp" => timestamp
           }} ->
            # Calculate expiry time
            obtained_at = DateTime.from_unix!(div(timestamp, 1000))
            expires_at = DateTime.add(obtained_at, expires_in, :second)

            token_data = %{
              access_token: access,
              refresh_token: refresh,
              expires_at: expires_at
            }

            {:ok, token_data}

          {:ok, %{"accessToken" => access, "refreshToken" => refresh}} ->
            # No expiry info, assume needs refresh soon
            token_data = %{
              access_token: access,
              refresh_token: refresh,
              expires_at: DateTime.utc_now() |> DateTime.add(3600, :second)
            }

            {:ok, token_data}

          {:error, reason} ->
            {:error, "Failed to parse old token file: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to read old token file: #{inspect(reason)}"}
    end
  end

  # OAuth2 token refresh using library
  defp refresh_oauth_tokens(state) do
    Logger.debug("Attempting OAuth2 token refresh",
      has_refresh_token: state.oauth_client.token.refresh_token != nil,
      client_id_present: state.oauth_client.client_id != nil,
      client_secret_present: state.oauth_client.client_secret != nil,
      refresh_token_length:
        if(state.oauth_client.token.refresh_token,
          do: String.length(state.oauth_client.token.refresh_token),
          else: 0
        )
    )

    # Try manual refresh to get better error details
    case manual_refresh_token(state) do
      {:ok, new_token_data} ->
        Logger.info("Manual OAuth2 token refresh successful")

        # Create new OAuth client with refreshed token
        token =
          OAuth2.AccessToken.new(%{
            "access_token" => new_token_data.access_token,
            "refresh_token" => new_token_data.refresh_token,
            "expires_at" => new_token_data.expires_at
          })

        oauth_client =
          OAuth2.Client.new(
            strategy: OAuth2.Strategy.Refresh,
            client_id: state.oauth_client.client_id,
            client_secret: state.oauth_client.client_secret,
            site: "https://id.twitch.tv",
            authorize_url: "https://id.twitch.tv/oauth2/authorize",
            token_url: "https://id.twitch.tv/oauth2/token",
            token: token
          )

        # Save updated tokens to DETS
        save_tokens_to_storage(state.token_table, new_token_data)

        # Update state with new OAuth client
        new_state = %{state | oauth_client: oauth_client}
        {:ok, new_state}

      {:error, reason} ->
        Logger.error("Manual OAuth2 token refresh failed", error: reason)
        {:error, "OAuth2 token refresh failed: #{reason}"}
    end
  end

  # Manual token refresh for better error handling
  defp manual_refresh_token(state) do
    url = "https://id.twitch.tv/oauth2/token"

    headers = [
      {~c"content-type", ~c"application/x-www-form-urlencoded"}
    ]

    body =
      URI.encode_query(%{
        "grant_type" => "refresh_token",
        "refresh_token" => state.oauth_client.token.refresh_token,
        "client_id" => state.oauth_client.client_id,
        "client_secret" => state.oauth_client.client_secret
      })

    Logger.debug("Manual refresh request",
      url: url,
      body_length: String.length(body),
      has_refresh_token: state.oauth_client.token.refresh_token != nil
    )

    case :httpc.request(
           :post,
           {~c"https://id.twitch.tv/oauth2/token", headers, ~c"application/x-www-form-urlencoded",
            String.to_charlist(body)},
           [],
           []
         ) do
      {:ok, {{_version, 200, _reason_phrase}, _headers, response_body}} ->
        case Jason.decode(List.to_string(response_body)) do
          {:ok,
           %{
             "access_token" => access_token,
             "refresh_token" => refresh_token,
             "expires_in" => expires_in
           }} ->
            expires_at = DateTime.utc_now() |> DateTime.add(expires_in, :second)

            token_data = %{
              access_token: access_token,
              refresh_token: refresh_token,
              expires_at: expires_at
            }

            {:ok, token_data}

          {:ok, response} ->
            {:error, "Unexpected response format: #{inspect(response)}"}

          {:error, reason} ->
            {:error, "JSON decode failed: #{inspect(reason)}"}
        end

      {:ok, {{_version, status, _reason_phrase}, _headers, response_body}} ->
        body_str = List.to_string(response_body)

        Logger.error("Twitch OAuth refresh HTTP error",
          status: status,
          response: body_str
        )

        {:error, "HTTP #{status}: #{body_str}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp schedule_token_refresh(state) do
    # Cancel existing timer
    if state.token_refresh_timer do
      Process.cancel_timer(state.token_refresh_timer)
    end

    # Calculate time until refresh needed (5 minutes before expiry)
    time_until_refresh =
      case state.oauth_client.token do
        nil ->
          @token_refresh_buffer

        token ->
          case token.expires_at do
            nil ->
              @token_refresh_buffer

            expires_at ->
              time_to_expiry = DateTime.diff(expires_at, DateTime.utc_now(), :millisecond)
              max(0, time_to_expiry - @token_refresh_buffer)
          end
      end

    timer = Process.send_after(self(), :refresh_token, time_until_refresh)
    %{state | token_refresh_timer: timer}
  end

  # Placeholder for EventSub message handling
  defp handle_eventsub_message(state, message_json) do
    case Jason.decode(message_json) do
      {:ok, message} ->
        handle_eventsub_protocol_message(state, message)

      {:error, reason} ->
        Logger.error("Twitch message decode failed", error: reason, message: message_json)
        state
    end
  end

  defp handle_eventsub_protocol_message(
         state,
         %{"metadata" => %{"message_type" => "session_welcome"}} = message
       ) do
    session_data = message["payload"]["session"]
    session_id = session_data["id"]

    Logger.info("Twitch session welcome received", session_id: session_id)

    state =
      update_connection_state(state, %{
        connected: true,
        connection_state: "connected",
        session_id: session_id,
        last_connected: DateTime.utc_now()
      })
      |> Map.put(:session_id, session_id)

    # Create default subscriptions
    send(self(), :create_default_subscriptions)
    Logger.info("Twitch session ready for subscriptions")

    state
  end

  defp handle_eventsub_protocol_message(state, %{
         "metadata" => %{"message_type" => "session_keepalive"}
       }) do
    Logger.debug("Twitch keepalive received")
    state
  end

  defp handle_eventsub_protocol_message(
         state,
         %{"metadata" => %{"message_type" => "notification"}} = message
       ) do
    event_type = get_in(message, ["metadata", "subscription_type"])
    event_data = message["payload"]["event"]
    subscription_id = get_in(message, ["metadata", "subscription_id"])

    Logger.info("Twitch event received",
      event_type: event_type,
      subscription_id: subscription_id
    )

    # Process the event and publish to PubSub
    handle_twitch_event(event_type, event_data, subscription_id)

    state
  end

  defp handle_eventsub_protocol_message(
         state,
         %{"metadata" => %{"message_type" => "session_reconnect"}} = message
       ) do
    reconnect_url = get_in(message, ["payload", "session", "reconnect_url"])
    Logger.info("Twitch session reconnect requested", reconnect_url: reconnect_url)

    # TODO: Handle reconnection to new URL
    state
  end

  defp handle_eventsub_protocol_message(state, message) do
    Logger.debug("Twitch message unhandled", message: message)
    state
  end

  # State update helpers
  defp update_connection_state(state, updates) do
    connection = Map.merge(state.state.connection, updates)
    new_state = put_in(state.state.connection, connection)

    # Publish connection state changes
    Server.Events.publish_twitch_event("connection_changed", connection)

    new_state
  end

  defp cleanup_connection(state) do
    if state.conn_pid do
      :gun.close(state.conn_pid)
    end

    %{state | conn_pid: nil, stream_ref: nil, session_id: nil}
  end

  defp validate_twitch_token(access_token) do
    headers = [
      {~c"authorization", ~c"Bearer #{access_token}"}
    ]

    Logger.debug("Validating Twitch token", token_length: String.length(access_token))

    case :httpc.request(:get, {~c"https://id.twitch.tv/oauth2/validate", headers}, [], []) do
      {:ok, {{_version, 200, _reason_phrase}, _headers, body}} ->
        case Jason.decode(body) do
          {:ok, token_info} ->
            Logger.debug("Twitch token validation response",
              user_id: token_info["user_id"],
              client_id: token_info["client_id"],
              expires_in: token_info["expires_in"]
            )

            {:ok, token_info}

          {:error, reason} ->
            {:error, "Failed to parse validation response: #{inspect(reason)}"}
        end

      {:ok, {{_version, 401, _reason_phrase}, _headers, _body}} ->
        {:error, :invalid_token}

      {:ok, {{_version, status, _reason_phrase}, _headers, body}} ->
        {:error, "HTTP #{status}: #{body}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  # EventSub subscription management via HTTP API
  defp create_eventsub_subscription(state, event_type, condition, _opts \\ []) do
    url = "https://api.twitch.tv/helix/eventsub/subscriptions"

    headers = [
      {"authorization", "Bearer #{state.oauth_client.token.access_token}"},
      {"client-id", state.oauth_client.client_id},
      {"content-type", "application/json"}
    ]

    transport = %{
      "method" => "websocket",
      "session_id" => state.session_id
    }

    # Use version 2 for channel.follow, version 1 for others
    version = if event_type == "channel.follow", do: "2", else: "1"

    body = %{
      "type" => event_type,
      "version" => version,
      "condition" => condition,
      "transport" => transport
    }

    json_body = Jason.encode!(body)

    Logger.debug("Creating EventSub subscription",
      event_type: event_type,
      condition: condition,
      session_id: state.session_id,
      request_body: inspect(body, limit: :infinity),
      headers: inspect(headers, limit: :infinity)
    )

    case :httpc.request(
           :post,
           {url, Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end), ~c"application/json",
            to_charlist(json_body)},
           [],
           []
         ) do
      {:ok, {{_version, 202, _reason_phrase}, _headers, response_body}} ->
        case Jason.decode(List.to_string(response_body)) do
          {:ok, %{"data" => [subscription]}} ->
            Logger.info("EventSub subscription created successfully",
              event_type: event_type,
              subscription_id: subscription["id"],
              status: subscription["status"],
              cost: subscription["cost"]
            )

            {:ok, subscription}

          {:ok, response} ->
            Logger.error("EventSub subscription unexpected response format",
              event_type: event_type,
              response: inspect(response, limit: :infinity)
            )

            {:error, "Unexpected response format: #{inspect(response)}"}

          {:error, reason} ->
            body_str = List.to_string(response_body)

            Logger.error("EventSub subscription JSON decode failed",
              event_type: event_type,
              decode_error: inspect(reason),
              raw_body: body_str
            )

            {:error, "JSON decode failed: #{inspect(reason)}"}
        end

      {:ok, {{_version, status, _reason_phrase}, _response_headers, response_body}} ->
        body_str = List.to_string(response_body)

        # Parse error details if available
        error_details =
          case Jason.decode(body_str) do
            {:ok, %{"error" => error, "message" => message}} ->
              %{error: error, message: message}

            {:ok, parsed} ->
              parsed

            {:error, _} ->
              %{raw_body: body_str}
          end

        # Handle specific HTTP error codes
        error_message =
          case status do
            400 ->
              Logger.error("EventSub subscription bad request",
                event_type: event_type,
                error_details: inspect(error_details, limit: :infinity),
                condition: inspect(condition)
              )

              "Bad request - check subscription parameters"

            401 ->
              Logger.error("EventSub subscription unauthorized",
                event_type: event_type,
                error_details: inspect(error_details, limit: :infinity)
              )

              "Unauthorized - check access token"

            403 ->
              Logger.error("EventSub subscription forbidden",
                event_type: event_type,
                error_details: inspect(error_details, limit: :infinity),
                user_id: state.user_id
              )

              "Forbidden - insufficient permissions or invalid user"

            409 ->
              Logger.warning("EventSub subscription conflict",
                event_type: event_type,
                error_details: inspect(error_details, limit: :infinity)
              )

              "Conflict - subscription may already exist"

            429 ->
              Logger.warning("EventSub subscription rate limited",
                event_type: event_type,
                error_details: inspect(error_details, limit: :infinity)
              )

              "Rate limited - retry after delay"

            _ ->
              Logger.error("EventSub subscription failed",
                event_type: event_type,
                http_status: status,
                error_details: inspect(error_details, limit: :infinity),
                condition: inspect(condition),
                session_id: state.session_id,
                user_id: state.user_id
              )

              "HTTP #{status}: #{inspect(error_details)}"
          end

        {:error, error_message}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp delete_eventsub_subscription(state, subscription_id) do
    url = "https://api.twitch.tv/helix/eventsub/subscriptions?id=#{subscription_id}"

    headers = [
      {"authorization", "Bearer #{state.oauth_client.token.access_token}"},
      {"client-id", state.oauth_client.client_id}
    ]

    Logger.debug("Deleting EventSub subscription", subscription_id: subscription_id)

    case :httpc.request(
           :delete,
           {url, Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end)},
           [],
           []
         ) do
      {:ok, {{_version, 204, _reason_phrase}, _headers, _response_body}} ->
        Logger.info("EventSub subscription deleted successfully",
          subscription_id: subscription_id
        )

        :ok

      {:ok, {{_version, status, _reason_phrase}, _headers, response_body}} ->
        body_str = List.to_string(response_body)

        Logger.error("EventSub subscription deletion failed",
          status: status,
          response: body_str,
          subscription_id: subscription_id
        )

        {:error, "HTTP #{status}: #{body_str}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  # Scope validation for EventSub subscriptions
  defp validate_scopes_for_subscription(user_scopes, required_scopes)
       when is_list(required_scopes) do
    if length(required_scopes) == 0 do
      # No scopes required
      true
    else
      user_scopes = user_scopes || MapSet.new()
      required_set = MapSet.new(required_scopes)
      MapSet.subset?(required_set, user_scopes)
    end
  end

  # Generate unique key for subscription deduplication
  defp generate_subscription_key(event_type, condition) when is_map(condition) do
    # Sort condition keys for consistent key generation
    sorted_condition =
      condition
      |> Enum.sort()
      |> Enum.into(%{})

    "#{event_type}:#{:erlang.phash2(sorted_condition)}"
  end

  # Specific event handlers
  defp handle_twitch_event("stream.online", event_data, _subscription_id) do
    Logger.info("Stream went online",
      title: event_data["title"],
      category: event_data["category_name"],
      started_at: event_data["started_at"]
    )

    Server.Events.publish_twitch_event("stream_online", %{
      title: event_data["title"],
      category: event_data["category_name"],
      started_at: event_data["started_at"],
      broadcaster_user_name: event_data["broadcaster_user_name"]
    })
  end

  defp handle_twitch_event("stream.offline", event_data, _subscription_id) do
    Logger.info("Stream went offline", broadcaster: event_data["broadcaster_user_name"])

    Server.Events.publish_twitch_event("stream_offline", %{
      broadcaster_user_name: event_data["broadcaster_user_name"]
    })
  end

  defp handle_twitch_event("channel.follow", event_data, _subscription_id) do
    Logger.info("New follower",
      user: event_data["user_name"],
      followed_at: event_data["followed_at"]
    )

    Server.Events.publish_twitch_event("new_follower", %{
      user_id: event_data["user_id"],
      user_name: event_data["user_name"],
      user_login: event_data["user_login"],
      followed_at: event_data["followed_at"]
    })
  end

  defp handle_twitch_event("channel.subscribe", event_data, _subscription_id) do
    Logger.info("New subscriber",
      user: event_data["user_name"],
      tier: event_data["tier"],
      is_gift: event_data["is_gift"]
    )

    Server.Events.publish_twitch_event("new_subscriber", %{
      user_id: event_data["user_id"],
      user_name: event_data["user_name"],
      user_login: event_data["user_login"],
      tier: event_data["tier"],
      is_gift: event_data["is_gift"]
    })
  end

  defp handle_twitch_event("channel.subscription.gift", event_data, _subscription_id) do
    Logger.info("Gift subscription",
      gifter: event_data["user_name"],
      tier: event_data["tier"],
      total: event_data["total"],
      cumulative_total: event_data["cumulative_total"]
    )

    Server.Events.publish_twitch_event("gift_subscription", %{
      user_id: event_data["user_id"],
      user_name: event_data["user_name"],
      user_login: event_data["user_login"],
      tier: event_data["tier"],
      total: event_data["total"],
      cumulative_total: event_data["cumulative_total"],
      is_anonymous: event_data["is_anonymous"]
    })
  end

  defp handle_twitch_event("channel.cheer", event_data, _subscription_id) do
    Logger.info("Bits cheered",
      user: event_data["user_name"],
      bits: event_data["bits"],
      message: event_data["message"]
    )

    Server.Events.publish_twitch_event("cheer", %{
      user_id: event_data["user_id"],
      user_name: event_data["user_name"],
      user_login: event_data["user_login"],
      bits: event_data["bits"],
      message: event_data["message"],
      is_anonymous: event_data["is_anonymous"]
    })
  end

  defp handle_twitch_event(event_type, event_data, subscription_id) do
    Logger.debug("Unhandled Twitch event",
      event_type: event_type,
      subscription_id: subscription_id,
      event_data: inspect(event_data, limit: :infinity)
    )

    # Publish generic event for unhandled types
    Server.Events.publish_twitch_event("unknown_event", %{
      event_type: event_type,
      event_data: event_data,
      subscription_id: subscription_id
    })
  end

  # Helper functions
  defp get_token_storage_path do
    case Mix.env() do
      :prod ->
        # Docker production environment
        "/app/data/twitch_tokens.dets"

      _ ->
        # Development environment - use project data directory
        data_dir = "./data"
        File.mkdir_p!(data_dir)
        Path.join(data_dir, "twitch_tokens.dets")
    end
  end
end

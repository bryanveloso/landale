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
  @reconnect_interval 5_000      # 5 seconds
  @token_refresh_buffer 300_000  # 5 minutes before expiry

  defstruct [
    :conn_pid,
    :stream_ref,
    :session_id,
    :reconnect_timer,
    :token_refresh_timer,
    :token_table,
    :oauth_client,
    :pending_subscriptions,
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
      subscription_max_cost: 10000  # Twitch default
    }
  ]

  # Client API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
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
    table_path = Path.join([System.tmp_dir!(), "twitch_tokens.dets"])
    {:ok, token_table} = :dets.open_file(:twitch_tokens, [file: String.to_charlist(table_path)])
    
    # Create OAuth2 client
    oauth_client = OAuth2.Client.new([
      strategy: OAuth2.Strategy.Refresh,
      client_id: client_id,
      client_secret: client_secret,
      site: "https://id.twitch.tv",
      authorize_url: "https://id.twitch.tv/oauth2/authorize",
      token_url: "https://id.twitch.tv/oauth2/token"
    ])
    
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
  def handle_info(:load_tokens, state) do
    case load_tokens_from_storage(state.token_table) do
      {:ok, token_data} ->
        Logger.info("Twitch OAuth tokens loaded from storage")
        
        # Create OAuth2 client with loaded tokens
        token = OAuth2.AccessToken.new(%{
          "access_token" => token_data.access_token,
          "refresh_token" => token_data.refresh_token,
          "expires_at" => token_data.expires_at
        })
        
        oauth_client = OAuth2.Client.new([
          strategy: OAuth2.Strategy.Refresh,
          client_id: state.oauth_client.client_id,
          client_secret: state.oauth_client.client_secret,
          site: "https://id.twitch.tv",
          authorize_url: "https://id.twitch.tv/oauth2/authorize",
          token_url: "https://id.twitch.tv/oauth2/token",
          token: token
        ])
        
        Logger.debug("Twitch OAuth client created", 
          has_token: oauth_client.token != nil,
          token_present: oauth_client.token.access_token != nil
        )
        
        state = %{state | oauth_client: oauth_client}
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
            token = OAuth2.AccessToken.new(%{
              "access_token" => token_data.access_token,
              "refresh_token" => token_data.refresh_token,
              "expires_at" => token_data.expires_at
            })
            
            oauth_client = OAuth2.Client.new([
              strategy: OAuth2.Strategy.Refresh,
              client_id: state.oauth_client.client_id,
              client_secret: state.oauth_client.client_secret,
              site: "https://id.twitch.tv",
              authorize_url: "https://id.twitch.tv/oauth2/authorize",
              token_url: "https://id.twitch.tv/oauth2/token",
              token: token
            ])
            
            Logger.debug("Twitch OAuth client created from migration", 
              has_token: oauth_client.token != nil,
              token_present: oauth_client.token.access_token != nil
            )
            
            state = %{state | oauth_client: oauth_client}
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
      {:ok, _token_info} ->
        Logger.info("Twitch token validation successful")
        send(self(), :connect)
        {:noreply, state}
        
      {:error, :invalid_token} ->
        Logger.info("Twitch token invalid, attempting refresh")
        send(self(), :refresh_token)
        {:noreply, state}
        
      {:error, reason} ->
        Logger.error("Twitch token validation failed", 
          error: reason,
          token_length: if(state.oauth_client.token, do: String.length(state.oauth_client.token.access_token), else: 0)
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
      state = update_connection_state(state, %{
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
      state = update_connection_state(state, %{
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
      
      state = update_connection_state(state, %{
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
      
      state = update_connection_state(state, %{
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
      state = update_connection_state(state, %{
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
  def handle_info({:gun_response, conn_pid, stream_ref, is_fin, status, headers}, state) do
    if conn_pid == state.conn_pid && stream_ref == state.stream_ref do
      Logger.info("TWITCH DEBUG: HTTP response during upgrade", 
        status: status, 
        is_fin: is_fin, 
        headers: inspect(headers, pretty: true, limit: :infinity)
      )
      
      # Log detailed info about non-successful responses
      if status != 101 do
        Logger.error("TWITCH DEBUG: WebSocket upgrade failed", 
          status: status,
          expected: 101,
          headers: inspect(headers, pretty: true, limit: :infinity)
        )
      end
    end
    {:noreply, state}
  end

  @impl GenServer  
  def handle_info({:gun_data, conn_pid, stream_ref, is_fin, data}, state) do
    if conn_pid == state.conn_pid && stream_ref == state.stream_ref do
      data_str = if is_binary(data), do: data, else: List.to_string(data)
      
      Logger.info("TWITCH DEBUG: HTTP data during upgrade", 
        is_fin: is_fin, 
        data_length: byte_size(data_str),
        data_preview: String.slice(data_str, 0, 500),
        full_data: data_str
      )
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
      state = update_connection_state(state, %{
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
    
    case :gun.open(host, port, %{transport: :tls}) do
      {:ok, conn_pid} ->
        # Monitor the connection
        Process.monitor(conn_pid)
        
        case :gun.await_up(conn_pid, 10_000) do
          {:ok, _protocol} ->
            # Twitch EventSub WebSocket does NOT require auth headers during upgrade
            # Authentication happens during subscription creation via HTTP API
            headers = [
              {"user-agent", "Landale/1.0.0"}
            ]
            
            # Upgrade to WebSocket without auth headers (per Twitch EventSub spec)
            stream_ref = :gun.ws_upgrade(conn_pid, path, headers)
            
            Logger.debug("Twitch WebSocket upgrade initiated", 
              conn_pid: inspect(conn_pid), 
              stream_ref: inspect(stream_ref), 
              path: path,
              has_token: state.oauth_client.token != nil,
              token_length: String.length(state.oauth_client.token.access_token || ""),
              client_id: state.oauth_client.client_id
            )
            
            new_state = %{state | conn_pid: conn_pid, stream_ref: stream_ref}
            |> update_connection_state(%{
              connection_state: "connecting"
            })
            
            {:ok, new_state}
            
          {:error, reason} ->
            Logger.error("Twitch connection failed during await_up", error: reason)
            :gun.close(conn_pid)
            
            state = update_connection_state(state, %{
              connected: false,
              connection_state: "error",
              last_error: inspect(reason)
            })
            {:error, state}
        end
        
      {:error, reason} ->
        Logger.error("Twitch connection failed during open", error: reason)
        state = update_connection_state(state, %{
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
    :dets.sync(table)  # Ensure data is written to disk
  end

  # Migrate tokens from old Twurple format
  defp migrate_old_tokens do
    old_file = "/Users/Avalonstar/Code/bryanveloso/landale/apps/server-old/src/services/twitch/twitch-token.json"
    
    case File.read(old_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"accessToken" => access, "refreshToken" => refresh, "expiresIn" => expires_in, "obtainmentTimestamp" => timestamp}} ->
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
      refresh_token_length: if(state.oauth_client.token.refresh_token, do: String.length(state.oauth_client.token.refresh_token), else: 0)
    )
    
    # Try manual refresh to get better error details
    case manual_refresh_token(state) do
      {:ok, new_token_data} ->
        Logger.info("Manual OAuth2 token refresh successful")
        
        # Create new OAuth client with refreshed token
        token = OAuth2.AccessToken.new(%{
          "access_token" => new_token_data.access_token,
          "refresh_token" => new_token_data.refresh_token,
          "expires_at" => new_token_data.expires_at
        })
        
        oauth_client = OAuth2.Client.new([
          strategy: OAuth2.Strategy.Refresh,
          client_id: state.oauth_client.client_id,
          client_secret: state.oauth_client.client_secret,
          site: "https://id.twitch.tv",
          authorize_url: "https://id.twitch.tv/oauth2/authorize",
          token_url: "https://id.twitch.tv/oauth2/token",
          token: token
        ])
        
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
    
    body = URI.encode_query(%{
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
    
    case :httpc.request(:post, {~c"https://id.twitch.tv/oauth2/token", headers, ~c"application/x-www-form-urlencoded", String.to_charlist(body)}, [], []) do
      {:ok, {{_version, 200, _reason_phrase}, _headers, response_body}} ->
        case Jason.decode(List.to_string(response_body)) do
          {:ok, %{"access_token" => access_token, "refresh_token" => refresh_token, "expires_in" => expires_in}} ->
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
  
  # Keep the old function as backup
  defp refresh_oauth_tokens_old(state) do
    case OAuth2.Client.refresh_token(state.oauth_client) do
      {:ok, client} ->
        Logger.info("OAuth2 token refresh successful")
        
        # Extract token data for DETS storage
        token_data = %{
          access_token: client.token.access_token,
          refresh_token: client.token.refresh_token,
          expires_at: client.token.expires_at
        }
        
        # Save updated tokens to DETS
        save_tokens_to_storage(state.token_table, token_data)
        
        # Update state with new OAuth client
        new_state = %{state | oauth_client: client}
        {:ok, new_state}
        
      {:error, error} ->
        Logger.error("OAuth2 token refresh detailed error", 
          error: inspect(error, pretty: true, limit: :infinity),
          error_type: if(is_tuple(error), do: elem(error, 0), else: "unknown"),
          refresh_token_present: state.oauth_client.token.refresh_token != nil,
          token_url: state.oauth_client.token_url
        )
        {:error, "OAuth2 token refresh failed: #{inspect(error)}"}
    end
  end

  defp schedule_token_refresh(state) do
    # Cancel existing timer
    if state.token_refresh_timer do
      Process.cancel_timer(state.token_refresh_timer)
    end
    
    # Calculate time until refresh needed (5 minutes before expiry)
    time_until_refresh = case state.oauth_client.token do
      nil -> @token_refresh_buffer
      token ->
        case token.expires_at do
          nil -> @token_refresh_buffer
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

  defp handle_eventsub_protocol_message(state, %{"metadata" => %{"message_type" => "session_welcome"}} = message) do
    session_data = message["payload"]["session"]
    session_id = session_data["id"]
    
    Logger.info("Twitch session welcome received", session_id: session_id)
    
    state = update_connection_state(state, %{
      connected: true,
      connection_state: "connected",
      session_id: session_id,
      last_connected: DateTime.utc_now()
    })

    # TODO: Create EventSub subscriptions here
    Logger.info("Twitch session ready for subscriptions")
    
    state
  end

  defp handle_eventsub_protocol_message(state, %{"metadata" => %{"message_type" => "session_keepalive"}}) do
    Logger.debug("Twitch keepalive received")
    state
  end

  defp handle_eventsub_protocol_message(state, %{"metadata" => %{"message_type" => "notification"}} = message) do
    # TODO: Handle actual event notifications
    event_type = get_in(message, ["metadata", "subscription_type"])
    _event_data = message["payload"]["event"]
    
    Logger.debug("Twitch event received", event_type: event_type)
    
    # For now, just log - we'll implement specific handlers later
    state
  end

  defp handle_eventsub_protocol_message(state, %{"metadata" => %{"message_type" => "session_reconnect"}} = message) do
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

  defp token_expired?(token) do
    case token do
      nil -> true
      %{expires_at: nil} -> false  # No expiry info means don't assume expired
      %{expires_at: expires_at} ->
        DateTime.compare(DateTime.utc_now(), expires_at) == :gt
    end
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
end
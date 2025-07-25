defmodule Server.Services.OBS.Connection do
  @moduledoc """
  OBS WebSocket connection manager using gen_statem.

  Manages the connection lifecycle with distinct states:
  - :disconnected - Initial state, no connection
  - :connecting - Attempting to establish WebSocket connection
  - :authenticating - WebSocket connected, performing OBS authentication
  - :ready - Authenticated and ready to process requests
  - :reconnecting - Connection lost, attempting to reconnect

  This module is responsible for:
  - WebSocket connection management using Gun
  - OBS authentication flow
  - Message queuing during authentication
  - Broadcasting received events via PubSub
  - Forwarding requests to OBS
  """
  @behaviour :gen_statem
  require Logger

  alias Server.CorrelationId
  alias Server.Services.OBS.Protocol

  # Timeouts
  @connect_timeout 5_000
  @reconnect_delay 5_000
  @auth_timeout 10_000

  defstruct [
    :session_id,
    :uri,
    :conn_pid,
    :stream_ref,
    :reconnect_timer,
    :auth_timer,
    :connection_manager,
    :rpc_version,
    authentication_required: false,
    pending_messages: []
  ]

  # Client API

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def start_link(opts) do
    :gen_statem.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Returns a specification to start this module under a supervisor.
  """
  def child_spec(opts) do
    %{
      id: opts[:id] || __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @doc """
  Send a request to OBS. Will queue if not ready.
  """
  def send_request(conn, request_type, request_data \\ %{}) do
    :gen_statem.call(conn, {:send_request, request_type, request_data})
  end

  @doc """
  Get current connection state.
  """
  def get_state(conn) do
    :gen_statem.call(conn, :get_state)
  end

  # gen_statem callbacks

  @impl true
  def callback_mode, do: :state_functions

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    uri = Keyword.fetch!(opts, :uri)

    # Subscribe to connection manager events
    connection_manager = Server.ConnectionManager

    data = %__MODULE__{
      session_id: session_id,
      uri: uri,
      connection_manager: connection_manager
    }

    # Start connection immediately
    actions = [{:next_event, :internal, :connect}]

    {:ok, :disconnected, data, actions}
  end

  # State: disconnected

  def disconnected(:internal, :connect, data) do
    correlation_id = CorrelationId.generate()

    Logger.info("[#{correlation_id}] Connecting to OBS WebSocket at #{data.uri}",
      service: "obs",
      session_id: data.session_id
    )

    # Request connection from ConnectionManager
    # For now, connect directly with gun
    # TODO: Refactor to use Server.WebSocketConnection for consistency and shared features
    # This would provide exponential backoff, CloudFront retries, and unified connection management
    case connect_websocket(data.uri) do
      {:ok, conn_pid} ->
        actions = [{:state_timeout, @connect_timeout, :connection_timeout}]
        {:next_state, :connecting, %{data | conn_pid: conn_pid}, actions}

      {:error, reason} ->
        Logger.error("Failed to start connection: #{inspect(reason)}",
          service: "obs",
          session_id: data.session_id
        )

        actions = [{:state_timeout, @reconnect_delay, :retry_connect}]
        {:keep_state_and_data, actions}
    end
  end

  def disconnected(:state_timeout, :retry_connect, _data) do
    actions = [{:next_event, :internal, :connect}]
    {:keep_state_and_data, actions}
  end

  def disconnected({:call, from}, {:send_request, _type, _data}, _) do
    {:keep_state_and_data, [{:reply, from, {:error, :disconnected}}]}
  end

  def disconnected({:call, from}, :get_state, _) do
    {:keep_state_and_data, [{:reply, from, :disconnected}]}
  end

  # State: connecting

  def connecting(:info, {:gun_up, conn_pid, _protocol}, data) when conn_pid == data.conn_pid do
    # Gun connection established, WebSocket upgrade is in progress
    {:keep_state_and_data, []}
  end

  def connecting(:info, {:gun_upgrade, conn_pid, stream_ref, ["websocket"], _headers}, data)
      when conn_pid == data.conn_pid do
    Logger.info("WebSocket connection established",
      service: "obs",
      session_id: data.session_id
    )

    # Move to authenticating state
    data = %{data | stream_ref: stream_ref}
    actions = [{:next_event, :internal, :start_auth}]

    {:next_state, :authenticating, data, actions}
  end

  def connecting(:state_timeout, :connection_timeout, data) do
    Logger.error("Connection timeout",
      service: "obs",
      session_id: data.session_id
    )

    data = cleanup_connection(data)
    actions = [{:next_event, :internal, :connect}]
    {:next_state, :disconnected, data, actions}
  end

  def connecting({:call, from}, {:send_request, type, request_data}, data) do
    # Queue the request
    data = %{data | pending_messages: data.pending_messages ++ [{:request, type, request_data, from}]}
    {:keep_state, data}
  end

  def connecting({:call, from}, :get_state, _) do
    {:keep_state_and_data, [{:reply, from, :connecting}]}
  end

  def connecting(:info, {:gun_ws, conn_pid, stream_ref, {:close, code, reason}}, data)
      when conn_pid == data.conn_pid and stream_ref == data.stream_ref do
    Logger.warning("WebSocket closed during connection: #{code} - #{reason}",
      service: "obs",
      session_id: data.session_id
    )

    data = cleanup_connection(data)
    actions = [{:next_event, :internal, :connect}]
    {:next_state, :disconnected, data, actions}
  end

  def connecting(:info, {:gun_down, conn_pid, _protocol, _reason, _}, data)
      when conn_pid == data.conn_pid do
    # Connection failed before WebSocket upgrade
    data = cleanup_connection(data)
    actions = [{:state_timeout, @reconnect_delay, :retry_connect}]
    {:next_state, :disconnected, data, actions}
  end

  # State: authenticating

  def authenticating(:internal, :start_auth, data) do
    # Wait for Hello message from OBS - don't send anything yet
    actions = [{:state_timeout, @auth_timeout, :auth_timeout}]
    {:keep_state, data, actions}
  end

  def authenticating(:info, {:gun_ws, conn_pid, stream_ref, {:text, frame}}, data)
      when conn_pid == data.conn_pid and stream_ref == data.stream_ref do
    case Protocol.decode_message(frame) do
      {:ok, %{op: 0, d: %{rpcVersion: version} = hello_data}} ->
        # Hello response received
        data = %{data | rpc_version: version}

        if hello_data[:authentication] do
          handle_authentication_required(hello_data.authentication, data)
        else
          # No auth required, but still need to send Identify
          identify_msg =
            Protocol.encode_identify(%{
              rpcVersion: version,
              eventSubscriptions: Protocol.event_subscription_all()
            })

          Logger.debug("Sending Identify message (no auth): #{identify_msg}",
            service: "obs",
            session_id: data.session_id
          )

          :ok = :gun.ws_send(data.conn_pid, data.stream_ref, {:text, identify_msg})

          # Stay in authenticating state, waiting for Identified response
          {:keep_state_and_data, []}
        end

      {:ok, %{op: 2, d: identified_data}} ->
        # Identified response - authentication successful
        Logger.info("OBS authentication successful",
          service: "obs",
          session_id: data.session_id
        )

        data = %{data | rpc_version: identified_data.negotiatedRpcVersion}
        complete_authentication(data)

      {:error, reason} ->
        Logger.error("Failed to decode message during auth: #{inspect(reason)}",
          service: "obs",
          session_id: data.session_id
        )

        {:keep_state_and_data, []}
    end
  end

  def authenticating(:state_timeout, :auth_timeout, data) do
    Logger.error("Authentication timeout",
      service: "obs",
      session_id: data.session_id
    )

    data = cleanup_connection(data)
    actions = [{:next_event, :internal, :connect}]
    {:next_state, :disconnected, data, actions}
  end

  def authenticating({:call, from}, {:send_request, type, request_data}, data) do
    # Queue the request
    data = %{data | pending_messages: data.pending_messages ++ [{:request, type, request_data, from}]}
    {:keep_state, data}
  end

  def authenticating({:call, from}, :get_state, _) do
    {:keep_state_and_data, [{:reply, from, :authenticating}]}
  end

  def authenticating(:info, {:gun_ws, conn_pid, stream_ref, {:close, code, reason}}, data)
      when conn_pid == data.conn_pid and stream_ref == data.stream_ref do
    Logger.warning("WebSocket closed during authentication: #{code} - #{reason}",
      service: "obs",
      session_id: data.session_id
    )

    data = cleanup_connection(data)
    actions = [{:next_event, :internal, :connect}]
    {:next_state, :disconnected, data, actions}
  end

  # State: ready

  def ready(:enter, _old_state, data) do
    # Process any queued messages
    actions = process_pending_messages(data.pending_messages)
    data = %{data | pending_messages: []}

    # Broadcast connection established
    broadcast_event(data, :connection_established, %{
      session_id: data.session_id,
      rpc_version: data.rpc_version
    })

    {:keep_state, data, actions}
  end

  def ready(:info, {:gun_ws, conn_pid, stream_ref, {:text, frame}}, data)
      when conn_pid == data.conn_pid and stream_ref == data.stream_ref do
    case Protocol.decode_message(frame) do
      {:ok, %{op: 5} = event} ->
        # Event from OBS - broadcast it
        broadcast_obs_event(data, event.d)

      {:ok, %{op: 7} = response} ->
        # Request response - forward to RequestTracker
        forward_response(data, response.d)

      {:ok, msg} ->
        Logger.debug("Received OBS message: #{inspect(msg)}",
          service: "obs",
          session_id: data.session_id
        )

      {:error, reason} ->
        Logger.error("Failed to decode OBS message: #{inspect(reason)}",
          service: "obs",
          session_id: data.session_id
        )
    end

    {:keep_state_and_data, []}
  end

  def ready({:call, from}, {:send_request, request_type, request_data}, data) do
    # Forward to RequestTracker for tracking and sending
    case get_request_tracker(data.session_id) do
      {:ok, tracker} ->
        # Let RequestTracker handle the request lifecycle
        result = GenServer.call(tracker, {:track_and_send, request_type, request_data, data.conn_pid, data.stream_ref})
        {:keep_state_and_data, [{:reply, from, result}]}

      {:error, reason} ->
        {:keep_state_and_data, [{:reply, from, {:error, reason}}]}
    end
  end

  def ready({:call, from}, :get_state, _) do
    {:keep_state_and_data, [{:reply, from, :ready}]}
  end

  def ready(:info, {:gun_ws, conn_pid, stream_ref, {:close, code, reason}}, data)
      when conn_pid == data.conn_pid and stream_ref == data.stream_ref do
    Logger.warning("WebSocket closed by server: #{code} - #{reason}",
      service: "obs",
      session_id: data.session_id
    )

    broadcast_event(data, :connection_lost, %{code: code, reason: reason})

    # Move to reconnecting
    actions = [{:next_event, :internal, :start_reconnect}]
    {:next_state, :reconnecting, data, actions}
  end

  def ready(:info, {:gun_down, conn_pid, _protocol, reason, _}, data)
      when conn_pid == data.conn_pid do
    Logger.warning("Connection lost: #{inspect(reason)}",
      service: "obs",
      session_id: data.session_id
    )

    broadcast_event(data, :connection_lost, %{reason: reason})

    # Move to reconnecting
    actions = [{:next_event, :internal, :start_reconnect}]
    {:next_state, :reconnecting, data, actions}
  end

  # State: reconnecting

  def reconnecting(:internal, :start_reconnect, data) do
    data = cleanup_connection(data)

    actions = [{:state_timeout, @reconnect_delay, :reconnect}]
    {:keep_state, data, actions}
  end

  def reconnecting(:state_timeout, :reconnect, data) do
    actions = [{:next_event, :internal, :connect}]
    {:next_state, :disconnected, data, actions}
  end

  def reconnecting({:call, from}, {:send_request, type, request_data}, data) do
    # Queue the request
    data = %{data | pending_messages: data.pending_messages ++ [{:request, type, request_data, from}]}
    {:keep_state, data}
  end

  def reconnecting({:call, from}, :get_state, _) do
    {:keep_state_and_data, [{:reply, from, :reconnecting}]}
  end

  # Helper functions

  defp handle_authentication_required(auth_data, data) do
    Logger.info("OBS requires authentication",
      service: "obs",
      session_id: data.session_id,
      challenge: auth_data.challenge,
      salt: auth_data.salt
    )

    # Get password from environment or configuration
    password = System.get_env("OBS_WEBSOCKET_PASSWORD", "")

    if password == "" do
      Logger.error("OBS requires authentication but OBS_WEBSOCKET_PASSWORD not set",
        service: "obs",
        session_id: data.session_id
      )

      data = cleanup_connection(data)
      {:next_state, :disconnected, data}
    else
      # Generate authentication string
      # OBS uses: base64(sha256(password + salt) + challenge)
      import Base, only: [encode64: 1]

      secret = :crypto.hash(:sha256, password <> auth_data.salt)
      auth_string = encode64(:crypto.hash(:sha256, secret <> auth_data.challenge))

      # Send Identify message
      identify_msg =
        Protocol.encode_identify(%{
          rpcVersion: data.rpc_version,
          authentication: auth_string,
          eventSubscriptions: Protocol.event_subscription_all()
        })

      :ok = :gun.ws_send(data.conn_pid, data.stream_ref, {:text, identify_msg})

      # Stay in authenticating state, waiting for Identified response
      {:keep_state_and_data, []}
    end
  end

  defp complete_authentication(data) do
    Logger.info("OBS connection ready",
      service: "obs",
      session_id: data.session_id
    )

    {:next_state, :ready, data}
  end

  defp cleanup_connection(data) do
    if data.conn_pid do
      :gun.close(data.conn_pid)
    end

    %{data | conn_pid: nil, stream_ref: nil}
  end

  defp process_pending_messages(messages) do
    Enum.map(messages, fn
      {:request, _type, _data, from} ->
        # Reply with error - connection was reestablished but request is stale
        {:reply, from, {:error, :request_expired}}
    end)
  end

  defp broadcast_event(data, event_type, event_data) do
    Phoenix.PubSub.broadcast(
      Server.PubSub,
      "obs:events",
      {event_type, Map.put(event_data, :session_id, data.session_id)}
    )
  end

  defp broadcast_obs_event(data, event) do
    Phoenix.PubSub.broadcast(
      Server.PubSub,
      "obs_events:#{data.session_id}",
      {:obs_event, event}
    )
  end

  defp forward_response(data, response) do
    case get_request_tracker(data.session_id) do
      {:ok, tracker} ->
        GenServer.cast(tracker, {:handle_response, response})

      {:error, _} ->
        Logger.warning("No request tracker found for response",
          service: "obs",
          session_id: data.session_id
        )
    end
  end

  defp get_request_tracker(session_id) do
    Server.Services.OBS.Supervisor.get_process(session_id, :request_tracker)
  end

  defp connect_websocket(uri) do
    # Parse the URI
    uri_map = URI.parse(uri)
    host = uri_map.host || "localhost"
    port = uri_map.port || 4455
    path = uri_map.path || "/"

    # Start gun connection
    case :gun.open(String.to_charlist(host), port, %{protocols: [:http]}) do
      {:ok, conn_pid} ->
        # Upgrade to WebSocket
        _stream_ref = :gun.ws_upgrade(conn_pid, path)
        {:ok, conn_pid}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

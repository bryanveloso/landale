defmodule Server.Services.OBS.ConnectionRefactored do
  @moduledoc """
  OBS WebSocket connection manager using WebSocketConnection for transport.

  This refactored version delegates transport concerns to WebSocketConnection
  while focusing solely on OBS protocol handling and state management.

  States:
  - :disconnected - No active connection
  - :authenticating - Connected, performing OBS authentication
  - :ready - Authenticated and ready to process requests
  """
  use GenServer
  require Logger

  alias Server.Services.OBS.Protocol
  alias Server.WebSocketConnection

  # Timeouts
  @auth_timeout 10_000

  defstruct [
    :session_id,
    :ws_conn,
    :state,
    :rpc_version,
    :auth_timer,
    pending_messages: [],
    authentication_required: false
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
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
    GenServer.call(conn, {:send_request, request_type, request_data})
  end

  @doc """
  Get current connection state.
  """
  def get_state(conn) do
    GenServer.call(conn, :get_state)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    uri = Keyword.fetch!(opts, :uri)

    # Start WebSocket connection
    {:ok, ws_conn} =
      WebSocketConnection.start_link(
        uri: uri,
        owner: self(),
        auto_connect: true,
        reconnect_base_delay: 5_000,
        reconnect_max_delay: 60_000
      )

    state = %__MODULE__{
      session_id: session_id,
      ws_conn: ws_conn,
      state: :disconnected
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:send_request, request_type, request_data}, from, state) do
    case state.state do
      :ready ->
        # Forward to RequestTracker for tracking and sending
        send_obs_request(state, request_type, request_data, from)

      _ ->
        # Queue the request
        state = queue_request(state, {:request, request_type, request_data, from})
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.state, state}
  end

  # WebSocketConnection events

  @impl true
  def handle_info({WebSocketConnection, _pid, {:websocket_connecting, %{uri: uri}}}, state) do
    Logger.info("Connecting to OBS WebSocket",
      uri: uri,
      service: "obs",
      session_id: state.session_id
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({WebSocketConnection, _pid, {:websocket_connected, _}}, state) do
    Logger.info("WebSocket connection established, starting OBS authentication",
      service: "obs",
      session_id: state.session_id
    )

    # Start authentication flow
    state = start_authentication(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({WebSocketConnection, _pid, {:websocket_frame, {:text, frame}}}, state) do
    case state.state do
      :authenticating ->
        handle_auth_message(frame, state)

      :ready ->
        handle_obs_message(frame, state)

      _ ->
        Logger.debug("Received message in unexpected state",
          state: state.state,
          service: "obs",
          session_id: state.session_id
        )

        {:noreply, state}
    end
  end

  @impl true
  def handle_info({WebSocketConnection, _pid, {:websocket_disconnected, %{reason: reason}}}, state) do
    Logger.warning("WebSocket connection lost",
      reason: inspect(reason),
      service: "obs",
      session_id: state.session_id
    )

    broadcast_event(state, :connection_lost, %{reason: reason})

    # Clean up and reset state
    state = cleanup_state(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({WebSocketConnection, _pid, {:websocket_error, %{reason: reason}}}, state) do
    Logger.error("WebSocket error",
      error: reason,
      service: "obs",
      session_id: state.session_id
    )

    {:noreply, state}
  end

  @impl true
  def handle_info(:auth_timeout, state) do
    if state.state == :authenticating do
      Logger.error("Authentication timeout",
        service: "obs",
        session_id: state.session_id
      )

      # Disconnect and let WebSocketConnection handle reconnection
      WebSocketConnection.disconnect(state.ws_conn)
      state = cleanup_state(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  # Private functions

  defp start_authentication(state) do
    # Send Hello message (OpCode 0)
    hello_msg =
      Protocol.encode_hello(%{
        rpcVersion: 1,
        eventSubscriptions: Protocol.event_subscription_all()
      })

    WebSocketConnection.send_data(state.ws_conn, hello_msg)

    # Set authentication timeout
    auth_timer = Process.send_after(self(), :auth_timeout, @auth_timeout)

    %{state | state: :authenticating, auth_timer: auth_timer}
  end

  defp handle_auth_message(frame, state) do
    case Protocol.decode_message(frame) do
      {:ok, %{op: 0, d: %{rpcVersion: version} = hello_data}} ->
        # Hello response received
        state = %{state | rpc_version: version}

        if hello_data[:authentication] do
          handle_authentication_required(hello_data.authentication, state)
        else
          # No auth required, move to ready
          complete_authentication(state)
        end

      {:ok, %{op: 2, d: identified_data}} ->
        # Identified response - authentication successful
        Logger.info("OBS authentication successful",
          service: "obs",
          session_id: state.session_id
        )

        state = %{state | rpc_version: identified_data.negotiatedRpcVersion}
        complete_authentication(state)

      {:error, reason} ->
        Logger.error("Failed to decode message during auth",
          reason: inspect(reason),
          service: "obs",
          session_id: state.session_id
        )

        {:noreply, state}
    end
  end

  defp handle_authentication_required(auth_data, state) do
    Logger.info("OBS requires authentication",
      challenge: auth_data.challenge,
      salt: auth_data.salt,
      service: "obs",
      session_id: state.session_id
    )

    # Get password from environment or configuration
    password = System.get_env("OBS_WEBSOCKET_PASSWORD", "")

    if password == "" do
      Logger.error("OBS requires authentication but OBS_WEBSOCKET_PASSWORD not set",
        service: "obs",
        session_id: state.session_id
      )

      WebSocketConnection.disconnect(state.ws_conn)
      state = cleanup_state(state)
      {:noreply, state}
    else
      # Generate authentication string
      # OBS uses: base64(sha256(password + salt) + challenge)
      import Base, only: [encode64: 1]

      secret = :crypto.hash(:sha256, password <> auth_data.salt)
      auth_string = encode64(:crypto.hash(:sha256, secret <> auth_data.challenge))

      # Send Identify message
      identify_msg =
        Protocol.encode_identify(%{
          rpcVersion: state.rpc_version,
          authentication: auth_string,
          eventSubscriptions: Protocol.event_subscription_all()
        })

      case WebSocketConnection.send_data(state.ws_conn, identify_msg) do
        :ok ->
          # Stay in authenticating state, waiting for Identified response
          {:noreply, state}

        {:error, reason} ->
          Logger.error("Failed to send Identify message: #{inspect(reason)}",
            service: "obs",
            session_id: state.session_id
          )

          WebSocketConnection.disconnect(state.ws_conn)
          state = cleanup_state(state)
          {:noreply, state}
      end
    end
  end

  defp complete_authentication(state) do
    # Cancel auth timer
    if state.auth_timer do
      Process.cancel_timer(state.auth_timer)
    end

    state = %{state | state: :ready, auth_timer: nil}

    # Broadcast connection established
    broadcast_event(state, :connection_established, %{
      session_id: state.session_id,
      rpc_version: state.rpc_version
    })

    # Process any queued messages
    state = process_pending_messages(state)

    {:noreply, state}
  end

  defp handle_obs_message(frame, state) do
    case Protocol.decode_message(frame) do
      {:ok, %{op: 5} = event} ->
        # Event from OBS - broadcast it
        broadcast_obs_event(state, event.d)

      {:ok, %{op: 7} = response} ->
        # Request response - forward to RequestTracker
        forward_response(state, response.d)

      {:ok, msg} ->
        Logger.debug("Received OBS message",
          message: inspect(msg),
          service: "obs",
          session_id: state.session_id
        )

      {:error, reason} ->
        Logger.error("Failed to decode OBS message",
          reason: inspect(reason),
          service: "obs",
          session_id: state.session_id
        )
    end

    {:noreply, state}
  end

  defp send_obs_request(state, request_type, request_data, _from) do
    case get_request_tracker(state.session_id) do
      {:ok, _tracker} ->
        # Get connection state to verify we're connected
        ws_state = WebSocketConnection.get_state(state.ws_conn)

        if ws_state.connected do
          # Since RequestTracker expects Gun directly, we'll handle it inline
          # Generate request ID here
          request_id = generate_request_id()

          # Create request message
          request_msg = Protocol.encode_request(request_id, request_type, request_data)

          # Send through WebSocketConnection
          case WebSocketConnection.send_data(state.ws_conn, request_msg) do
            :ok ->
              # Return success with the request_id for tracking
              {:reply, {:ok, request_id}, state}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        else
          {:reply, {:error, :not_connected}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp generate_request_id do
    # Generate a unique request ID
    System.unique_integer([:positive])
    |> Integer.to_string()
  end

  defp queue_request(state, request) do
    %{state | pending_messages: state.pending_messages ++ [request]}
  end

  defp process_pending_messages(state) do
    Enum.each(state.pending_messages, fn
      {:request, type, data, from} ->
        # Process the queued request
        case get_request_tracker(state.session_id) do
          {:ok, tracker} ->
            ws_state = WebSocketConnection.get_state(state.ws_conn)

            if ws_state.connected do
              result = GenServer.call(tracker, {:track_and_send, type, data, state.ws_conn})
              GenServer.reply(from, result)
            else
              GenServer.reply(from, {:error, :not_connected})
            end

          {:error, reason} ->
            GenServer.reply(from, {:error, reason})
        end
    end)

    %{state | pending_messages: []}
  end

  defp cleanup_state(state) do
    # Cancel auth timer if active
    if state.auth_timer do
      Process.cancel_timer(state.auth_timer)
    end

    %{state | state: :disconnected, auth_timer: nil, rpc_version: nil, authentication_required: false}
  end

  defp broadcast_event(state, event_type, data) do
    Phoenix.PubSub.broadcast(
      Server.PubSub,
      "obs:#{state.session_id}",
      {event_type, data}
    )
  end

  defp broadcast_obs_event(state, event_data) do
    event_type = event_data.eventType

    Phoenix.PubSub.broadcast(
      Server.PubSub,
      "obs:#{state.session_id}:events",
      {:obs_event, event_type, event_data}
    )

    # Also broadcast to session-specific event channel
    Phoenix.PubSub.broadcast(
      Server.PubSub,
      "obs:#{state.session_id}:#{event_type}",
      {:obs_event, event_data}
    )
  end

  defp forward_response(state, response_data) do
    case get_request_tracker(state.session_id) do
      {:ok, tracker} ->
        GenServer.cast(tracker, {:response_received, response_data})

      {:error, reason} ->
        Logger.error("Failed to forward response to RequestTracker",
          reason: reason,
          service: "obs",
          session_id: state.session_id
        )
    end
  end

  defp get_request_tracker(session_id) do
    # In test environment, we use a simpler approach
    tracker_name = :"obs_request_tracker_#{session_id}"

    case Process.whereis(tracker_name) do
      nil -> {:error, :tracker_not_found}
      pid -> {:ok, pid}
    end
  end
end

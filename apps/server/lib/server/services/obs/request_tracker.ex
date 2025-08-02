defmodule Server.Services.OBS.RequestTracker do
  @moduledoc """
  Tracks OBS requests and responses (refactored for WebSocketConnection).

  Maintains a registry of pending requests and matches responses
  by request ID. Handles timeouts for requests that don't receive
  responses. Works with WebSocketConnection instead of direct Gun calls.
  """
  use GenServer
  require Logger

  alias Server.Services.OBS.Protocol
  alias Server.WebSocketConnection

  # 30 seconds
  @request_timeout 30_000

  defstruct [
    :session_id,
    requests: %{},
    next_id: 1
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)

    {:ok, %__MODULE__{session_id: session_id}}
  end

  @impl true
  def handle_call({:send_request, request_type, request_data, original_from, ws_conn}, from, state) do
    # Generate request ID
    request_id = to_string(state.next_id)

    Logger.info("RequestTracker sending request",
      service: "obs",
      session_id: state.session_id,
      request_type: request_type,
      request_id: request_id,
      request_data: request_data
    )

    # Create request message
    request_msg = Protocol.encode_request(request_id, request_type, request_data)

    # Log the actual message content
    Logger.info("RequestTracker encoded message: #{request_msg}",
      service: "obs",
      session_id: state.session_id,
      request_id: request_id,
      message_length: String.length(request_msg)
    )

    # Send through WebSocketConnection
    case WebSocketConnection.send_data(ws_conn, request_msg) do
      :ok ->
        Logger.info("RequestTracker successfully sent to WebSocket",
          service: "obs",
          session_id: state.session_id,
          request_id: request_id
        )

        # Track the request
        timer_ref = Process.send_after(self(), {:request_timeout, request_id}, @request_timeout)

        request_info = %{
          from: from,
          original_from: original_from,
          type: request_type,
          data: request_data,
          timer: timer_ref,
          sent_at: System.monotonic_time(:millisecond)
        }

        state = %{state | requests: Map.put(state.requests, request_id, request_info), next_id: state.next_id + 1}

        # Don't reply yet - will reply when response arrives
        {:noreply, state}

      {:error, reason} ->
        Logger.error("RequestTracker failed to send to WebSocket",
          service: "obs",
          session_id: state.session_id,
          request_id: request_id,
          reason: reason
        )

        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:response_received, response_data}, state) do
    request_id = response_data[:requestId]

    Logger.info("RequestTracker received response",
      service: "obs",
      session_id: state.session_id,
      request_id: request_id,
      response_type: response_data[:requestType],
      response_status: response_data[:requestStatus]
    )

    case Map.get(state.requests, request_id) do
      nil ->
        # Log more details about the unknown response
        Logger.warning("Received response for unknown request ID: #{request_id}",
          service: "obs",
          session_id: state.session_id,
          response_type: response_data[:requestType],
          response_status: response_data[:requestStatus],
          tracked_ids: Map.keys(state.requests) |> Enum.sort() |> Enum.take(10)
        )

        {:noreply, state}

      request_info ->
        # Cancel timeout
        Process.cancel_timer(request_info.timer)

        # Calculate latency
        latency = System.monotonic_time(:millisecond) - request_info.sent_at

        Logger.debug("OBS request completed",
          service: "obs",
          session_id: state.session_id,
          request_type: request_info.type,
          request_id: request_id,
          latency_ms: latency
        )

        # Reply to caller
        result =
          if response_data[:requestStatus][:result] do
            {:ok, response_data[:responseData]}
          else
            {:error, response_data[:requestStatus]}
          end

        GenServer.reply(request_info.from, result)

        # Remove from tracking
        state = %{state | requests: Map.delete(state.requests, request_id)}
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:request_timeout, request_id}, state) do
    case Map.get(state.requests, request_id) do
      nil ->
        # Already handled
        {:noreply, state}

      request_info ->
        Logger.error("OBS request timeout",
          service: "obs",
          session_id: state.session_id,
          request_type: request_info.type,
          request_id: request_id
        )

        GenServer.reply(request_info.from, {:error, :timeout})

        state = %{state | requests: Map.delete(state.requests, request_id)}
        {:noreply, state}
    end
  end
end

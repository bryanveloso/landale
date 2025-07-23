defmodule Server.Services.OBS.RequestTracker do
  @moduledoc """
  Tracks OBS requests and responses.

  Maintains a registry of pending requests and matches responses
  by request ID. Handles timeouts for requests that don't receive
  responses.
  """
  use GenServer
  require Logger

  alias Server.Services.OBS.Protocol

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
  def handle_call({:track_and_send, request_type, request_data, conn_pid, stream_ref}, from, state) do
    # Generate request ID
    request_id = to_string(state.next_id)

    # Create request message
    request_msg = Protocol.encode_request(request_id, request_type, request_data)

    # Send to OBS
    case :gun.ws_send(conn_pid, stream_ref, {:text, request_msg}) do
      :ok ->
        # Track the request
        timer_ref = Process.send_after(self(), {:request_timeout, request_id}, @request_timeout)

        request_info = %{
          from: from,
          type: request_type,
          data: request_data,
          timer: timer_ref,
          sent_at: System.monotonic_time(:millisecond)
        }

        state = %{state | requests: Map.put(state.requests, request_id, request_info), next_id: state.next_id + 1}

        # Don't reply yet - will reply when response arrives
        {:noreply, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:handle_response, response}, state) do
    request_id = response[:requestId]

    case Map.get(state.requests, request_id) do
      nil ->
        Logger.warning("Received response for unknown request ID: #{request_id}",
          service: "obs",
          session_id: state.session_id
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
          if response[:requestStatus][:result] do
            {:ok, response[:responseData]}
          else
            {:error, response[:requestStatus]}
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

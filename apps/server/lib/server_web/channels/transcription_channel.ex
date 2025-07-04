defmodule ServerWeb.TranscriptionChannel do
  @moduledoc """
  Phoenix channel for real-time transcription broadcasting to obs-entei plugin.

  This channel provides live transcription data for OBS caption overlays and
  real-time streaming applications. The channel is optimized for low-latency
  delivery of transcription events from the AI analysis pipeline.

  ## Supported Topics

  - `transcription:live` - Real-time transcription events as they arrive
  - `transcription:session:{session_id}` - Session-specific transcription events

  ## Events Sent

  - `new_transcription` - New transcription with text, timestamp, and metadata
  - `session_started` - New transcription session begun
  - `session_ended` - Transcription session concluded

  ## Usage Example (obs-entei plugin)

      // Connect to WebSocket
      const socket = new Phoenix.Socket("/socket")
      socket.connect()

      // Join live transcription channel
      const channel = socket.channel("transcription:live")
      channel.join()

      // Listen for new transcriptions
      channel.on("new_transcription", (data) => {
        console.log("New transcription:", data.text)
        updateCaptions(data.text, data.confidence)
      })

      // Join session-specific channel
      const sessionChannel = socket.channel("transcription:session:stream_2024_01_15")
      sessionChannel.join()
  """

  use ServerWeb, :channel
  require Logger
  alias Server.CorrelationId

  # Channel metadata for self-documentation
  @topic_pattern "transcription:*"
  @channel_examples [
    %{
      topic: "transcription:live",
      description: "Subscribe to all live transcription events"
    },
    %{
      topic: "transcription:session:stream_2024_01_15",
      description: "Subscribe to transcriptions for a specific stream session"
    }
  ]

  # Accessor functions for module attributes
  @doc false
  def __topic_pattern__, do: @topic_pattern
  @doc false
  def __channel_examples__, do: @channel_examples

  @impl true
  def join("transcription:live", _payload, socket) do
    # Generate correlation ID for this transcription connection
    correlation_id = CorrelationId.from_context(assigns: socket.assigns)
    CorrelationId.put_logger_metadata(correlation_id)

    Logger.info("Transcription live channel joined", correlation_id: correlation_id)

    socket = assign(socket, :correlation_id, correlation_id)

    # Subscribe to live transcription events
    Phoenix.PubSub.subscribe(Server.PubSub, "transcription:live")

    # Send initial connection confirmation
    push(socket, "connection_established", %{
      type: "transcription:live",
      timestamp: DateTime.utc_now(),
      status: "connected"
    })

    {:ok, socket}
  end

  @impl true
  def join("transcription:session:" <> session_id, _payload, socket) do
    # Generate correlation ID for this session connection
    correlation_id = CorrelationId.from_context(assigns: socket.assigns)
    CorrelationId.put_logger_metadata(correlation_id)

    Logger.info("Transcription session channel joined",
      session_id: session_id,
      correlation_id: correlation_id
    )

    socket =
      socket
      |> assign(:correlation_id, correlation_id)
      |> assign(:session_id, session_id)

    # Subscribe to session-specific transcription events
    Phoenix.PubSub.subscribe(Server.PubSub, "transcription:session:#{session_id}")

    # Send initial connection confirmation with session info
    push(socket, "connection_established", %{
      type: "transcription:session",
      session_id: session_id,
      timestamp: DateTime.utc_now(),
      status: "connected"
    })

    {:ok, socket}
  end

  @impl true
  def join("transcription:" <> _invalid, _payload, _socket) do
    Logger.warning("Invalid transcription channel topic attempted")

    {:error,
     %{reason: "Invalid transcription channel. Use 'transcription:live' or 'transcription:session:{session_id}'"}}
  end

  # Handle ping for connection health
  @impl true
  def handle_in("ping", payload, socket) do
    response =
      Map.merge(payload, %{
        pong: true,
        timestamp: DateTime.utc_now(),
        channel_type: get_channel_type(socket)
      })

    {:reply, {:ok, response}, socket}
  end

  # Get recent transcriptions
  @impl true
  def handle_in("get_recent", payload, socket) do
    with_correlation_context(socket, fn ->
      minutes = Map.get(payload, "minutes", 5)

      case Server.Transcription.get_recent_transcriptions(minutes) do
        transcriptions when is_list(transcriptions) ->
          {:reply, {:ok, %{transcriptions: transcriptions, count: length(transcriptions)}}, socket}

        error ->
          Logger.error("Failed to get recent transcriptions", error: error)
          {:reply, {:error, %{message: "Failed to retrieve recent transcriptions"}}, socket}
      end
    end)
  end

  # Get session transcriptions (only for session channels)
  @impl true
  def handle_in("get_session_transcriptions", payload, socket) do
    with_correlation_context(socket, fn ->
      case socket.assigns[:session_id] do
        nil ->
          {:reply, {:error, %{message: "Session transcriptions only available on session channels"}}, socket}

        session_id ->
          limit = Map.get(payload, "limit", 100)

          case Server.Transcription.get_session_transcriptions(session_id, limit: limit) do
            transcriptions when is_list(transcriptions) ->
              {:reply,
               {:ok,
                %{
                  session_id: session_id,
                  transcriptions: transcriptions,
                  count: length(transcriptions)
                }}, socket}

            error ->
              Logger.error("Failed to get session transcriptions", error: error, session_id: session_id)
              {:reply, {:error, %{message: "Failed to retrieve session transcriptions"}}, socket}
          end
      end
    end)
  end

  # Catch-all for unhandled messages
  @impl true
  def handle_in(event, payload, socket) do
    Logger.warning("Unhandled transcription channel message",
      event: event,
      payload: payload,
      correlation_id: socket.assigns.correlation_id
    )

    {:reply, {:error, %{message: "Unknown command: #{event}"}}, socket}
  end

  # Event Handlers - Receive and forward transcription events

  @impl true
  def handle_info({:new_transcription, transcription_data}, socket) do
    # Forward transcription event to connected clients
    push(socket, "new_transcription", transcription_data)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:session_started, session_data}, socket) do
    push(socket, "session_started", session_data)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:session_ended, session_data}, socket) do
    push(socket, "session_ended", session_data)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:transcription_stats, stats_data}, socket) do
    push(socket, "transcription_stats", stats_data)
    {:noreply, socket}
  end

  # Catch-all for other PubSub messages
  @impl true
  def handle_info(message, socket) do
    Logger.debug("Unhandled transcription channel info message",
      message: inspect(message),
      correlation_id: socket.assigns.correlation_id
    )

    {:noreply, socket}
  end

  # Private helper functions

  defp get_channel_type(socket) do
    case socket.assigns[:session_id] do
      nil -> "live"
      session_id -> "session:#{session_id}"
    end
  end

  defp with_correlation_context(socket, fun) do
    correlation_id = socket.assigns.correlation_id
    CorrelationId.with_context(correlation_id, fun)
  end
end

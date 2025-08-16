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

  use ServerWeb.ChannelBase

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
    socket = setup_correlation_id(socket)

    Logger.info("Transcription live channel joined",
      correlation_id: socket.assigns.correlation_id
    )

    # Subscribe to live transcription events
    Phoenix.PubSub.subscribe(Server.PubSub, "transcription:live")

    # Send initial connection confirmation after join completes
    send_after_join(socket, :after_join_live)

    {:ok, socket}
  end

  @impl true
  def join("transcription:session:" <> session_id, _payload, socket) do
    socket =
      socket
      |> setup_correlation_id()
      |> assign(:session_id, session_id)

    Logger.info("Transcription session channel joined",
      session_id: session_id,
      correlation_id: socket.assigns.correlation_id
    )

    # Subscribe to session-specific transcription events
    Phoenix.PubSub.subscribe(Server.PubSub, "transcription:session:#{session_id}")

    # Send initial connection confirmation after join completes
    send_after_join(socket, :after_join_session)

    {:ok, socket}
  end

  @impl true
  def join("transcription:" <> _invalid, _payload, _socket) do
    Logger.warning("Invalid transcription channel topic attempted")

    {:error,
     %{
       reason: "Invalid transcription channel. Use 'transcription:live' or 'transcription:session:{session_id}'"
     }}
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
              Logger.error("Failed to get session transcriptions",
                error: error,
                session_id: session_id
              )

              {:reply, {:error, %{message: "Failed to retrieve session transcriptions"}}, socket}
          end
      end
    end)
  end

  # Submit transcription via WebSocket
  @impl true
  def handle_in("submit_transcription", payload, socket) do
    with_correlation_context(socket, fn ->
      # Track submission timing
      start_time = System.monotonic_time(:millisecond)

      case Server.Transcription.Validation.validate(payload) do
        {:ok, validated_attrs} ->
          case Server.Transcription.create_transcription(validated_attrs) do
            {:ok, transcription} ->
              # Calculate submission latency
              duration_ms = System.monotonic_time(:millisecond) - start_time

              # Broadcast to live transcription subscribers
              broadcast_transcription(transcription)

              Logger.info("Transcription submitted via WebSocket",
                transcription_id: transcription.id,
                source_id: transcription.source_id,
                text_preview: String.slice(transcription.text || "", 0, 50),
                correlation_id: socket.assigns.correlation_id,
                duration_ms: duration_ms
              )

              {:reply, {:ok, %{transcription_id: transcription.id}}, socket}

            {:error, changeset} ->
              handle_database_error(changeset, socket)
          end

        {:error, validation_errors} ->
          formatted_errors = Server.Transcription.Validation.format_errors(validation_errors)

          Logger.warning("Transcription payload validation failed",
            errors: formatted_errors,
            correlation_id: socket.assigns.correlation_id
          )

          {:reply, {:error, %{errors: formatted_errors}}, socket}
      end
    end)
  end

  # Catch-all for unhandled messages
  @impl true
  def handle_in(event, payload, socket) do
    log_unhandled_message(event, payload, socket)
    {:reply, {:error, %{message: "Unknown command: #{event}"}}, socket}
  end

  # Event Handlers - Receive and forward transcription events

  @impl true
  def handle_info(:after_join_live, socket) do
    # Send initial connection confirmation for live channel
    push(socket, "connection_established", %{
      type: "transcription:live",
      timestamp: DateTime.utc_now(),
      status: "connected"
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info(:after_join_session, socket) do
    # Send initial connection confirmation for session channel
    push(socket, "connection_established", %{
      type: "transcription:session",
      session_id: socket.assigns.session_id,
      timestamp: DateTime.utc_now(),
      status: "connected"
    })

    {:noreply, socket}
  end

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

  defp handle_database_error(changeset, socket) do
    formatted_errors =
      Server.Transcription.Validation.format_errors(traverse_changeset_errors(changeset))

    Logger.warning("Transcription validation failed via WebSocket",
      errors: formatted_errors,
      correlation_id: socket.assigns.correlation_id
    )

    {:reply, {:error, %{errors: formatted_errors}}, socket}
  end

  defp traverse_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp broadcast_transcription(transcription) do
    Server.Transcription.Broadcaster.broadcast_transcription(transcription)
  end
end

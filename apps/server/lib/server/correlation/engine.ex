defmodule Server.Correlation.Engine do
  @moduledoc """
  Correlation engine that matches viewer chat messages to streamer speech.

  Maintains sliding time windows of transcription and chat events to detect
  patterns and correlations between what the streamer says and how chat responds.

  ## Design Principles

  - Event-driven processing with Phoenix PubSub subscriptions
  - Efficient time-based buffers with chunked storage
  - 3-7 second lag compensation for chat reaction time
  - Confidence-based correlation scoring
  - Memory-bounded with automatic pruning
  """

  use GenServer
  require Logger

  # Use SlidingBuffer for better performance with our specific use case
  alias Server.Correlation.Monitor
  alias Server.Correlation.SlidingBuffer, as: Buffer

  # Time windows and delays
  # 30 seconds
  @transcription_window 30_000
  # 30 seconds
  @chat_window 30_000
  # 3 seconds minimum lag
  @correlation_delay_min 3_000
  # 7 seconds maximum lag
  @correlation_delay_max 7_000

  # Buffer limits for memory protection
  @max_transcription_buffer 100
  @max_chat_buffer 100
  @max_active_correlations 50

  # Pattern confidence scores
  @pattern_scores %{
    # Chat quotes transcription verbatim
    direct_quote: 0.9,
    # Shared significant keywords
    keyword_echo: 0.7,
    # Common reactions (lol, poggers, true)
    emote_reaction: 0.6,
    # Chat asks about what was said
    question_response: 0.5,
    # Just timing correlation
    temporal_only: 0.3
  }

  # Pruning interval
  # Prune old events every second
  @prune_interval 1_000

  # Fingerprint retention window (5 minutes)
  @fingerprint_retention_ms 300_000

  defstruct [
    :transcription_buffer,
    :chat_buffer,
    :active_correlations,
    :stream_active,
    :session_id,
    # Map of fingerprint => timestamp
    :processed_fingerprints
  ]

  # Client API

  @doc """
  Starts the correlation engine and links it to the current process.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current buffer states for debugging/monitoring.
  """
  def get_buffer_state do
    GenServer.call(__MODULE__, :get_buffer_state)
  end

  @doc """
  Gets recent correlations with confidence scores.
  """
  def get_recent_correlations(limit \\ 10) do
    GenServer.call(__MODULE__, {:get_correlations, limit})
  end

  @doc """
  Gets correlation engine monitoring metrics.
  """
  def get_monitoring_metrics do
    try do
      Monitor.get_metrics()
    catch
      :exit, _ ->
        # Monitor not available, return minimal metrics
        %{
          correlation_metrics: %{total_count: 0, patterns: %{}},
          buffer_health: %{
            transcription_size: 0,
            chat_size: 0,
            correlation_count: 0,
            last_prune_time: nil,
            prune_rate: 0.0
          },
          database_metrics: %{
            operations_total: 0,
            operations_success: 0,
            operations_error: 0,
            success_rate: 1.0,
            avg_latency_ms: 0.0,
            circuit_breaker_status: :closed
          },
          performance_metrics: %{
            avg_processing_time_ms: 0.0,
            max_processing_time_ms: 0.0,
            min_processing_time_ms: 0.0,
            processing_times: []
          },
          rate_metrics: %{
            correlations_per_minute: 0.0,
            trend: :stable,
            peak_rate: 0.0
          },
          pattern_distribution: %{},
          uptime_seconds: 0
        }
    end
  end

  @doc """
  Marks the stream as started/stopped to manage buffers.
  """
  def stream_started do
    GenServer.cast(__MODULE__, :stream_started)
  end

  def stream_stopped do
    GenServer.cast(__MODULE__, :stream_stopped)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting Correlation Engine")

    # Subscribe to event streams
    Phoenix.PubSub.subscribe(Server.PubSub, "transcription:live")
    Phoenix.PubSub.subscribe(Server.PubSub, "events")

    # Schedule periodic pruning
    Process.send_after(self(), :prune_buffers, @prune_interval)

    state = %__MODULE__{
      transcription_buffer:
        Buffer.new(
          window_ms: @transcription_window,
          max_size: @max_transcription_buffer
        ),
      chat_buffer:
        Buffer.new(
          window_ms: @chat_window,
          max_size: @max_chat_buffer
        ),
      active_correlations: [],
      stream_active: false,
      session_id: nil,
      processed_fingerprints: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_buffer_state, _from, state) do
    reply = %{
      transcription_count: Buffer.size(state.transcription_buffer),
      chat_count: Buffer.size(state.chat_buffer),
      correlation_count: length(state.active_correlations),
      stream_active: state.stream_active,
      fingerprint_count: map_size(state.processed_fingerprints)
    }

    # Update monitor with current engine status
    Monitor.record_engine_status(reply)

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:get_correlations, limit}, _from, state) do
    correlations =
      state.active_correlations
      |> Enum.take(limit)
      |> Enum.map(&format_correlation/1)

    {:reply, correlations, state}
  end

  @impl true
  def handle_cast(:stream_started, state) do
    Logger.info("Stream started - clearing buffers and starting session")

    # Start a new stream session in the database
    case Server.Correlation.Repository.start_stream_session() do
      {:ok, session_id} ->
        Logger.info("Started correlation session: #{session_id}")

        state = %{
          state
          | transcription_buffer:
              Buffer.new(
                window_ms: @transcription_window,
                max_size: @max_transcription_buffer
              ),
            chat_buffer:
              Buffer.new(
                window_ms: @chat_window,
                max_size: @max_chat_buffer
              ),
            active_correlations: [],
            stream_active: true,
            session_id: session_id,
            processed_fingerprints: %{}
        }

        {:noreply, state}

      {:error, reason} ->
        Logger.error("Failed to start correlation session: #{inspect(reason)}")

        state = %{
          state
          | transcription_buffer:
              Buffer.new(
                window_ms: @transcription_window,
                max_size: @max_transcription_buffer
              ),
            chat_buffer:
              Buffer.new(
                window_ms: @chat_window,
                max_size: @max_chat_buffer
              ),
            active_correlations: [],
            stream_active: true,
            session_id: nil,
            processed_fingerprints: %{}
        }

        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:stream_stopped, state) do
    Logger.info("Stream stopped - preserving final correlations")

    # End the stream session in the database if we have one
    if state.session_id do
      case Server.Correlation.Repository.end_stream_session(state.session_id) do
        {:ok, session_id} ->
          Logger.info("Ended correlation session: #{session_id}")

        {:error, reason} ->
          Logger.error("Failed to end correlation session: #{inspect(reason)}")
      end
    end

    # Could trigger final analysis here
    state = %{state | stream_active: false, session_id: nil}

    {:noreply, state}
  end

  @impl true
  def handle_info({:new_transcription, transcription}, state) do
    # Handle transcription events from Phononmaser
    state = add_transcription(state, transcription)
    {:noreply, state}
  end

  @impl true
  def handle_info({:event, %{type: "channel.chat.message"} = event}, state) do
    # Handle Twitch chat messages
    state = process_chat_message(state, event)
    {:noreply, state}
  end

  @impl true
  def handle_info({:event, _other_event}, state) do
    # Ignore non-chat events
    {:noreply, state}
  end

  @impl true
  def handle_info(:prune_buffers, state) do
    # Prune old events from buffers
    state = prune_old_events(state)

    # Schedule next pruning
    Process.send_after(self(), :prune_buffers, @prune_interval)

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Correlation Engine received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp add_transcription(state, transcription) do
    if state.stream_active do
      # Add timestamp if not present
      transcription = Map.put_new(transcription, :timestamp, System.system_time(:millisecond))

      # Add to buffer (Buffer handles size limits automatically)
      buffer = Buffer.add(state.transcription_buffer, transcription)

      %{state | transcription_buffer: buffer}
    else
      state
    end
  end

  defp process_chat_message(state, chat_event) do
    if state.stream_active do
      # Extract chat message data
      chat_message = %{
        id: chat_event.data["message_id"] || Ecto.UUID.generate(),
        user: chat_event.data["chatter_user_name"] || "unknown",
        message: chat_event.data["message"]["text"] || "",
        timestamp: System.system_time(:millisecond),
        emotes: chat_event.data["message"]["emotes"] || []
      }

      # Add to chat buffer (Buffer handles size limits automatically)
      buffer = Buffer.add(state.chat_buffer, chat_message)

      state = %{state | chat_buffer: buffer}

      # Attempt correlation with recent transcriptions
      correlate_with_transcriptions(state, chat_message)
    else
      state
    end
  end

  defp correlate_with_transcriptions(state, chat_message) do
    current_time = chat_message.timestamp

    # Get transcriptions within the correlation window (3-7 seconds ago)
    # Using Buffer.get_range is more efficient than converting to list
    min_time = current_time - @correlation_delay_max
    max_time = current_time - @correlation_delay_min

    relevant_transcriptions =
      Buffer.get_range(
        state.transcription_buffer,
        min_time,
        max_time
      )

    # Find the best correlation if any
    case find_best_correlation(chat_message, relevant_transcriptions) do
      nil ->
        state

      correlation ->
        processing_start = System.system_time(:millisecond)

        # Generate fingerprint for duplicate detection
        fingerprint = generate_fingerprint(correlation)

        # Check if we've already processed this correlation
        if Map.has_key?(state.processed_fingerprints, fingerprint) do
          Logger.debug("Skipping duplicate correlation: #{fingerprint}")
          state
        else
          # Add fingerprint to map with timestamp for pruning
          fingerprints = Map.put(state.processed_fingerprints, fingerprint, current_time)

          # Add to active correlations
          correlations = [correlation | state.active_correlations]

          # Limit correlation buffer size
          correlations =
            if length(correlations) > @max_active_correlations do
              Enum.take(correlations, @max_active_correlations)
            else
              correlations
            end

          # Calculate processing time for monitoring
          processing_time = System.system_time(:millisecond) - processing_start

          # Record correlation detection in monitor
          Monitor.record_correlation_detected(correlation, processing_time)

          # Broadcast correlation insight
          broadcast_correlation(correlation)

          # Store in database (async with supervision) - pass session_id from state
          Task.Supervisor.start_child(
            Server.TaskSupervisor,
            fn -> store_correlation(correlation, state.session_id) end
          )

          %{state | active_correlations: correlations, processed_fingerprints: fingerprints}
        end
    end
  end

  defp find_best_correlation(chat_message, transcriptions) do
    correlations =
      Enum.map(transcriptions, fn trans ->
        score_correlation(chat_message, trans)
      end)
      # Min confidence threshold
      |> Enum.filter(fn corr -> corr.confidence > 0.4 end)
      |> Enum.sort_by(& &1.confidence, :desc)

    List.first(correlations)
  end

  defp score_correlation(chat_message, transcription) do
    chat_text = String.downcase(chat_message.message)
    trans_text = String.downcase(transcription.text || "")

    # Calculate pattern scores
    {pattern_type, confidence} =
      cond do
        # Direct quote - chat repeats transcription
        String.contains?(chat_text, trans_text) && String.length(trans_text) > 5 ->
          {:direct_quote, @pattern_scores.direct_quote}

        # Keyword echo - significant word overlap
        keyword_overlap?(chat_text, trans_text) ->
          {:keyword_echo, @pattern_scores.keyword_echo}

        # Emote reaction - typical short responses
        emote_reaction?(chat_message) ->
          {:emote_reaction, @pattern_scores.emote_reaction}

        # Question about what was said
        question_response?(chat_text, trans_text) ->
          {:question_response, @pattern_scores.question_response}

        # Default to temporal correlation only
        true ->
          {:temporal_only, @pattern_scores.temporal_only}
      end

    # Adjust confidence based on time proximity
    time_diff = chat_message.timestamp - transcription.timestamp

    time_factor =
      1.0 -
        (time_diff - @correlation_delay_min) /
          (@correlation_delay_max - @correlation_delay_min) * 0.2

    %{
      id: Ecto.UUID.generate(),
      transcription_id: transcription.id,
      transcription_text: transcription.text,
      chat_message_id: chat_message.id,
      chat_user: chat_message.user,
      chat_text: chat_message.message,
      pattern_type: pattern_type,
      confidence: confidence * time_factor,
      time_offset_ms: time_diff,
      timestamp: System.system_time(:millisecond)
    }
  end

  defp keyword_overlap?(chat_text, trans_text) do
    # Extract significant words (3+ chars, not common words)
    common_words = ~w(the and but for with are was were been have has had)

    chat_words =
      chat_text
      |> String.split()
      |> Enum.filter(fn w -> String.length(w) > 2 && w not in common_words end)
      |> MapSet.new()

    trans_words =
      trans_text
      |> String.split()
      |> Enum.filter(fn w -> String.length(w) > 2 && w not in common_words end)
      |> MapSet.new()

    overlap = MapSet.intersection(chat_words, trans_words) |> MapSet.size()

    # Need at least 2 word overlap or 50% of smaller set
    min_size = min(MapSet.size(chat_words), MapSet.size(trans_words))
    overlap >= 2 || (min_size > 0 && overlap / min_size >= 0.5)
  end

  defp emote_reaction?(chat_message) do
    # Check for common reaction patterns
    reaction_patterns = ~w(lol lmao rofl haha kek true facts based poggers pog
                          kappa omegalul pepega monkas wut wat bruh no yes yep)

    chat_lower = String.downcase(chat_message.message)

    # Check if message is primarily emotes or reactions
    length(chat_message.emotes) > 0 ||
      Enum.any?(reaction_patterns, &String.contains?(chat_lower, &1))
  end

  defp question_response?(chat_text, trans_text) do
    # Check if chat is asking about something mentioned
    String.contains?(chat_text, "?") &&
      (String.contains?(chat_text, "what") ||
         String.contains?(chat_text, "why") ||
         String.contains?(chat_text, "how")) &&
      keyword_overlap?(chat_text, trans_text)
  end

  defp prune_old_events(state) do
    current_time = System.system_time(:millisecond)

    # Track buffer sizes before pruning for monitoring
    trans_size_before = Buffer.size(state.transcription_buffer)
    chat_size_before = Buffer.size(state.chat_buffer)

    # Buffer handles its own pruning efficiently
    trans_buffer = Buffer.prune(state.transcription_buffer)
    chat_buffer = Buffer.prune(state.chat_buffer)

    # Track items pruned for monitoring
    trans_size_after = Buffer.size(trans_buffer)
    chat_size_after = Buffer.size(chat_buffer)

    trans_pruned = trans_size_before - trans_size_after
    chat_pruned = chat_size_before - chat_size_after

    # Record buffer pruning events
    if trans_pruned > 0 do
      Monitor.record_buffer_pruned(:transcription, trans_pruned, trans_size_after)
    end

    if chat_pruned > 0 do
      Monitor.record_buffer_pruned(:chat, chat_pruned, chat_size_after)
    end

    # Prune old fingerprints
    fingerprints =
      state.processed_fingerprints
      |> Enum.filter(fn {_fingerprint, timestamp} ->
        current_time - timestamp < @fingerprint_retention_ms
      end)
      |> Map.new()

    %{state | transcription_buffer: trans_buffer, chat_buffer: chat_buffer, processed_fingerprints: fingerprints}
  end

  defp generate_fingerprint(correlation) do
    # Create a unique fingerprint from the correlation components
    # Using transcription_id + chat_message_id + pattern_type ensures uniqueness
    # This prevents storing the same correlation multiple times
    "#{correlation.transcription_id}:#{correlation.chat_message_id}:#{correlation.pattern_type}"
  end

  defp broadcast_correlation(correlation) do
    # Broadcast to dashboard via Phoenix PubSub
    Phoenix.PubSub.broadcast(
      Server.PubSub,
      "correlation:insights",
      {:new_correlation, format_correlation(correlation)}
    )
  end

  defp store_correlation(correlation, session_id) do
    # Add session_id to correlation data
    correlation_with_session = Map.put(correlation, :session_id, session_id)

    # Store in database using Repository with proper error handling
    try do
      case Server.Correlation.Repository.store_correlation(correlation_with_session) do
        {:ok, _stored} ->
          Logger.debug("Stored correlation: #{correlation.pattern_type} with confidence #{correlation.confidence}")

        {:error, reason} ->
          Logger.error("Failed to store correlation: #{inspect(reason)}",
            pattern_type: correlation.pattern_type,
            confidence: correlation.confidence,
            session_id: session_id
          )
      end
    rescue
      error ->
        Logger.error("Exception storing correlation: #{inspect(error)}",
          pattern_type: correlation.pattern_type,
          confidence: correlation.confidence,
          session_id: session_id,
          stacktrace: __STACKTRACE__
        )
    end
  end

  defp format_correlation(correlation) do
    %{
      id: correlation.id,
      pattern: correlation.pattern_type,
      confidence: Float.round(correlation.confidence, 2),
      transcription: correlation.transcription_text,
      chat_user: correlation.chat_user,
      chat_message: correlation.chat_text,
      time_offset_ms: correlation.time_offset_ms
    }
  end
end

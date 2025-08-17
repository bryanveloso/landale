defmodule Server.Correlation.TemporalEngine do
  @moduledoc """
  Enhanced correlation engine with temporal analysis and dynamic delay compensation.

  Extends the basic correlation engine to use detected stream delay for more
  accurate correlation windows. Implements temporal pattern analysis across
  different time scales and response timing characteristics.
  """

  use GenServer
  require Logger

  alias Server.Correlation.{SlidingBuffer, TemporalAnalyzer}

  # Enhanced pattern recognition
  @temporal_patterns %{
    # Immediate reactions (within detected delay + 1s)
    immediate_reaction: %{confidence_multiplier: 1.0, reaction_type: :immediate},
    # Quick responses (delay + 1-3s)
    quick_response: %{confidence_multiplier: 0.9, reaction_type: :quick},
    # Delayed reactions (delay + 3-8s)
    delayed_reaction: %{confidence_multiplier: 0.7, reaction_type: :delayed},
    # Discussion spawned (delay + 8-15s)
    discussion_spawn: %{confidence_multiplier: 0.5, reaction_type: :discussion}
  }

  # Buffer configuration
  @transcription_buffer_size 150
  @chat_buffer_size 300

  defstruct [
    # Buffers for temporal analysis
    transcription_buffer: nil,
    chat_buffer: nil,

    # Session tracking
    current_session_id: nil,

    # Temporal metrics
    correlation_count: 0,
    temporal_patterns_detected: %{},
    last_analysis_time: nil,

    # Configuration
    min_confidence_threshold: 0.4,
    enable_discussion_tracking: true
  ]

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Add transcription event for temporal correlation analysis.
  """
  def add_transcription(transcription) do
    GenServer.cast(__MODULE__, {:transcription, transcription})
  end

  @doc """
  Add chat message for temporal correlation analysis.
  """
  def add_chat_message(chat_message) do
    GenServer.cast(__MODULE__, {:chat_message, chat_message})
  end

  @doc """
  Get temporal correlation metrics and patterns.
  """
  def get_temporal_metrics do
    GenServer.call(__MODULE__, :get_temporal_metrics)
  end

  @doc """
  Analyze temporal patterns for a specific transcription event.
  Returns correlations found in different temporal windows.
  """
  def analyze_temporal_patterns(transcription_id) do
    GenServer.call(__MODULE__, {:analyze_patterns, transcription_id})
  end

  ## Server Callbacks

  @impl GenServer
  def init(_opts) do
    Logger.info("Starting temporal correlation engine")

    # Subscribe to transcription and chat events
    Phoenix.PubSub.subscribe(Server.PubSub, "transcription:new")
    Phoenix.PubSub.subscribe(Server.PubSub, "chat:message")

    # Initialize buffers
    transcription_buffer = SlidingBuffer.new(max_size: @transcription_buffer_size)
    chat_buffer = SlidingBuffer.new(max_size: @chat_buffer_size)

    state = %__MODULE__{
      transcription_buffer: transcription_buffer,
      chat_buffer: chat_buffer,
      last_analysis_time: System.system_time(:millisecond)
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:transcription, transcription}, state) do
    # Add to temporal analyzer for signal generation
    word_count = count_words(transcription.text)
    TemporalAnalyzer.add_transcription_event(transcription.timestamp, word_count)

    # Add to buffer for correlation analysis
    new_buffer = SlidingBuffer.add(state.transcription_buffer, transcription)

    # Trigger temporal correlation analysis for this transcription
    correlations = analyze_transcription_correlations(transcription, state.chat_buffer)

    new_state = %{
      state
      | transcription_buffer: new_buffer,
        correlation_count: state.correlation_count + length(correlations)
    }

    # Store and broadcast correlations
    Enum.each(correlations, &handle_temporal_correlation/1)

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast({:chat_message, chat_message}, state) do
    # Add to temporal analyzer for signal generation
    TemporalAnalyzer.add_chat_event(chat_message.timestamp)

    # Add to buffer for correlation analysis
    new_buffer = SlidingBuffer.add(state.chat_buffer, chat_message)

    {:noreply, %{state | chat_buffer: new_buffer}}
  end

  @impl GenServer
  def handle_call(:get_temporal_metrics, _from, state) do
    # Get delay estimation metrics from temporal analyzer
    delay_info = TemporalAnalyzer.get_delay_estimate()
    analyzer_metrics = TemporalAnalyzer.get_metrics()

    metrics = %{
      correlation_count: state.correlation_count,
      temporal_patterns: state.temporal_patterns_detected,
      delay_estimation: delay_info,
      analyzer_health: analyzer_metrics,
      buffer_sizes: %{
        transcription: SlidingBuffer.size(state.transcription_buffer),
        chat: SlidingBuffer.size(state.chat_buffer)
      },
      last_analysis: state.last_analysis_time
    }

    {:reply, metrics, state}
  end

  @impl GenServer
  def handle_call({:analyze_patterns, transcription_id}, _from, state) do
    # Find transcription and analyze its temporal patterns
    transcription =
      SlidingBuffer.find(state.transcription_buffer, fn t ->
        t.id == transcription_id
      end)

    patterns =
      case transcription do
        nil -> []
        t -> analyze_transcription_correlations(t, state.chat_buffer)
      end

    {:reply, patterns, state}
  end

  @impl GenServer
  def handle_info({:transcription_new, transcription}, state) do
    handle_cast({:transcription, transcription}, state)
  end

  @impl GenServer
  def handle_info({:chat_message, chat_message}, state) do
    handle_cast({:chat_message, chat_message}, state)
  end

  ## Private Functions - Temporal Correlation Analysis

  defp analyze_transcription_correlations(transcription, chat_buffer) do
    # Get optimal correlation window from temporal analyzer
    {correlation_start, correlation_end} = TemporalAnalyzer.get_correlation_window(transcription.timestamp)

    # Find chat messages in the correlation window
    relevant_chats =
      SlidingBuffer.filter(chat_buffer, fn chat ->
        chat.timestamp >= correlation_start and chat.timestamp <= correlation_end
      end)

    # Analyze each chat message for temporal patterns
    relevant_chats
    |> Enum.map(&analyze_temporal_correlation(transcription, &1))
    # Filter by minimum confidence
    |> Enum.filter(&(&1.confidence >= 0.4))
    # Sort by confidence descending
    |> Enum.sort_by(&(-&1.confidence))
  end

  defp analyze_temporal_correlation(transcription, chat_message) do
    # Calculate base correlation using existing patterns
    base_correlation = calculate_base_correlation(transcription, chat_message)

    # Determine temporal pattern based on timing
    time_offset = chat_message.timestamp - transcription.timestamp
    delay_info = TemporalAnalyzer.get_delay_estimate()
    expected_delay = delay_info.estimated_delay_ms

    # Calculate how far off the timing is from expected delay
    timing_offset = time_offset - expected_delay
    temporal_pattern = classify_temporal_pattern(timing_offset)

    # Adjust confidence based on temporal pattern and delay confidence
    temporal_multiplier = @temporal_patterns[temporal_pattern.pattern_type].confidence_multiplier
    delay_confidence_factor = delay_info.confidence

    adjusted_confidence =
      base_correlation.confidence *
        temporal_multiplier *
        delay_confidence_factor

    # Create enhanced correlation with temporal information
    %{
      id: generate_correlation_id(),
      transcription_id: transcription.id,
      chat_message_id: chat_message.id,
      transcription_text: transcription.text,
      chat_user: chat_message.user,
      chat_text: chat_message.message,
      pattern_type: base_correlation.pattern_type,
      temporal_pattern: temporal_pattern,
      confidence: adjusted_confidence,
      time_offset_ms: time_offset,
      expected_delay_ms: expected_delay,
      timing_deviation_ms: timing_offset,
      delay_confidence: delay_confidence_factor,
      timestamp: System.system_time(:millisecond)
    }
  end

  defp calculate_base_correlation(transcription, chat_message) do
    # Use existing correlation logic from the basic engine
    trans_text = String.downcase(transcription.text || "")
    chat_text = String.downcase(chat_message.message || "")

    # Calculate pattern scores (same as original engine)
    {pattern_type, confidence} =
      cond do
        # Direct quote - chat repeats transcription
        String.contains?(chat_text, trans_text) && String.length(trans_text) > 5 ->
          {:direct_quote, 0.9}

        # Keyword echo - significant word overlap
        keyword_overlap?(chat_text, trans_text) ->
          {:keyword_echo, 0.7}

        # Emote reaction - typical short responses
        emote_reaction?(chat_message) ->
          {:emote_reaction, 0.6}

        # Question about what was said
        question_response?(chat_text, trans_text) ->
          {:question_response, 0.5}

        # Default to temporal correlation only
        true ->
          {:temporal_only, 0.3}
      end

    %{pattern_type: pattern_type, confidence: confidence}
  end

  defp classify_temporal_pattern(timing_offset_ms) do
    cond do
      timing_offset_ms <= 1_000 ->
        %{pattern_type: :immediate_reaction, description: "Immediate reaction within 1s of expected delay"}

      timing_offset_ms <= 3_000 ->
        %{pattern_type: :quick_response, description: "Quick response within 3s of expected delay"}

      timing_offset_ms <= 8_000 ->
        %{pattern_type: :delayed_reaction, description: "Delayed reaction within 8s of expected delay"}

      timing_offset_ms <= 15_000 ->
        %{pattern_type: :discussion_spawn, description: "Discussion spawn within 15s of expected delay"}

      true ->
        %{pattern_type: :outlier, description: "Response timing outside normal patterns"}
    end
  end

  # Pattern recognition helpers (from original engine)
  defp keyword_overlap?(chat_text, trans_text) do
    chat_words = extract_significant_words(chat_text)
    trans_words = extract_significant_words(trans_text)

    common_words = MapSet.intersection(MapSet.new(chat_words), MapSet.new(trans_words))
    overlap_ratio = MapSet.size(common_words) / max(length(chat_words), 1)

    overlap_ratio >= 0.3 && MapSet.size(common_words) >= 2
  end

  defp emote_reaction?(chat_message) do
    reaction_patterns = ~w(lol lmao rofl haha kek true facts based poggers pog
                          kappa omegalul pepega monkas wut wat bruh no yes yep)

    chat_lower = String.downcase(chat_message.message)

    length(chat_message.emotes || []) > 0 ||
      Enum.any?(reaction_patterns, &String.contains?(chat_lower, &1))
  end

  defp question_response?(chat_text, trans_text) do
    String.contains?(chat_text, "?") &&
      (String.contains?(chat_text, "what") || String.contains?(chat_text, "why") ||
         String.contains?(chat_text, "how") || String.contains?(chat_text, "when"))
  end

  defp extract_significant_words(text) do
    # Remove common stop words and extract meaningful terms
    stop_words = ~w(the and or but is are was were a an to for of in on at by)

    text
    |> String.split(~r/\W+/)
    |> Enum.map(&String.downcase/1)
    |> Enum.filter(&(String.length(&1) > 2))
    |> Enum.reject(&(&1 in stop_words))
  end

  defp count_words(text) do
    text
    |> String.split(~r/\s+/)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> length()
  end

  defp generate_correlation_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end

  defp handle_temporal_correlation(correlation) do
    # Store correlation in database
    session_id = get_current_session_id()

    correlation_with_session = Map.put(correlation, :session_id, session_id)

    try do
      case Server.Correlation.Repository.store_correlation(correlation_with_session) do
        {:ok, _stored} ->
          Logger.debug("Stored temporal correlation",
            pattern: correlation.pattern_type,
            temporal_pattern: correlation.temporal_pattern.pattern_type,
            confidence: Float.round(correlation.confidence, 3)
          )

        {:error, reason} ->
          Logger.error("Failed to store temporal correlation: #{inspect(reason)}")
      end

      # Broadcast enhanced correlation data
      broadcast_temporal_correlation(correlation)
    rescue
      error ->
        Logger.error("Exception storing temporal correlation: #{inspect(error)}")
    end
  end

  defp broadcast_temporal_correlation(correlation) do
    # Enhanced broadcast with temporal information
    correlation_data = %{
      id: correlation.id,
      pattern: correlation.pattern_type,
      temporal_pattern: correlation.temporal_pattern.pattern_type,
      confidence: Float.round(correlation.confidence, 2),
      transcription: correlation.transcription_text,
      chat_user: correlation.chat_user,
      chat_message: correlation.chat_text,
      time_offset_ms: correlation.time_offset_ms,
      timing_deviation_ms: correlation.timing_deviation_ms,
      delay_confidence: Float.round(correlation.delay_confidence, 2),
      timestamp: correlation.timestamp
    }

    Phoenix.PubSub.broadcast(
      Server.PubSub,
      "correlation:temporal",
      {:temporal_correlation, correlation_data}
    )
  end

  defp get_current_session_id do
    # Get current streaming session ID
    case Server.Sessions.get_current_session() do
      %{id: session_id} -> session_id
      _ -> nil
    end
  end
end

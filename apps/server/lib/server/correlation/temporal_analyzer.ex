defmodule Server.Correlation.TemporalAnalyzer do
  @moduledoc """
  Advanced temporal analysis for stream correlations with dynamic delay detection.

  Implements a two-stage approach:
  1. Delay Estimation: Uses cross-correlation to detect actual stream delay (3-20s)
  2. Event Correlation: Uses detected delay for precise correlation windows

  Accounts for variable stream delay between broadcaster and viewers, which can
  vary based on platform settings, network conditions, and viewer location.
  """

  use GenServer
  require Logger

  # Time series configuration
  # 2-second buckets for signal generation
  @signal_bucket_size_ms 2_000
  # 5 minutes of data for delay estimation
  @analysis_window_ms 300_000
  # Minimum expected stream delay
  @delay_range_min_ms 3_000
  # Maximum expected stream delay
  @delay_range_max_ms 20_000
  # Window around detected delay for event correlation
  @correlation_window_ms 4_000

  # Update frequencies
  # Re-estimate delay every 60 seconds
  @delay_estimation_interval_ms 60_000
  # Clean old signal data every 2 minutes
  @signal_cleanup_interval_ms 120_000

  # Signal quality thresholds
  # Minimum correlation peak to trust delay estimate
  @min_signal_strength 0.3
  # How confidence degrades over time
  @confidence_decay_rate 0.95

  defstruct [
    # Current delay estimate
    # Default to 8 seconds
    estimated_delay_ms: 8_000,
    # Confidence in current estimate
    delay_confidence: 0.5,
    last_estimation: nil,

    # Time series signals
    # timestamp_bucket -> word_count
    transcription_signal: %{},
    # timestamp_bucket -> message_count
    chat_signal: %{},

    # Signal generation state
    current_bucket: nil,
    transcription_words_in_bucket: 0,
    chat_messages_in_bucket: 0,

    # Timers
    estimation_timer: nil,
    cleanup_timer: nil,

    # Metrics
    total_estimations: 0,
    successful_estimations: 0,
    last_correlation_peak: 0.0
  ]

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the current estimated stream delay and confidence.
  """
  def get_delay_estimate do
    GenServer.call(__MODULE__, :get_delay_estimate)
  end

  @doc """
  Get optimal correlation window for an event at given timestamp.
  Returns {start_time, end_time} for correlation analysis.
  """
  def get_correlation_window(event_timestamp_ms) do
    GenServer.call(__MODULE__, {:get_correlation_window, event_timestamp_ms})
  end

  @doc """
  Add transcription event for signal generation.
  """
  def add_transcription_event(timestamp_ms, word_count) do
    GenServer.cast(__MODULE__, {:transcription_event, timestamp_ms, word_count})
  end

  @doc """
  Add chat event for signal generation.
  """
  def add_chat_event(timestamp_ms) do
    GenServer.cast(__MODULE__, {:chat_event, timestamp_ms})
  end

  @doc """
  Get current temporal analysis metrics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  ## Server Callbacks

  @impl GenServer
  def init(_opts) do
    Logger.info("Starting temporal analyzer with delay estimation")

    # Schedule periodic delay estimation
    estimation_timer = Process.send_after(self(), :estimate_delay, @delay_estimation_interval_ms)
    cleanup_timer = Process.send_after(self(), :cleanup_signals, @signal_cleanup_interval_ms)

    state = %__MODULE__{
      estimation_timer: estimation_timer,
      cleanup_timer: cleanup_timer,
      current_bucket: current_time_bucket(),
      last_estimation: DateTime.utc_now()
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_delay_estimate, _from, state) do
    result = %{
      estimated_delay_ms: state.estimated_delay_ms,
      confidence: state.delay_confidence,
      last_estimation: state.last_estimation
    }

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:get_correlation_window, event_timestamp_ms}, _from, state) do
    # Calculate correlation window based on current delay estimate
    delay_ms = state.estimated_delay_ms
    window_half = div(@correlation_window_ms, 2)

    correlation_start = event_timestamp_ms + delay_ms - window_half
    correlation_end = event_timestamp_ms + delay_ms + window_half

    window = {correlation_start, correlation_end}
    {:reply, window, state}
  end

  @impl GenServer
  def handle_call(:get_metrics, _from, state) do
    signal_health = %{
      transcription_buckets: map_size(state.transcription_signal),
      chat_buckets: map_size(state.chat_signal),
      current_bucket: state.current_bucket,
      signal_age_minutes: signal_age_minutes(state)
    }

    estimation_metrics = %{
      total_estimations: state.total_estimations,
      successful_estimations: state.successful_estimations,
      success_rate:
        if(state.total_estimations > 0, do: state.successful_estimations / state.total_estimations, else: 0.0),
      last_correlation_peak: state.last_correlation_peak
    }

    metrics = %{
      delay: %{
        estimated_ms: state.estimated_delay_ms,
        confidence: state.delay_confidence,
        last_estimation: state.last_estimation
      },
      signal_health: signal_health,
      estimation_metrics: estimation_metrics
    }

    {:reply, metrics, state}
  end

  @impl GenServer
  def handle_cast({:transcription_event, timestamp_ms, word_count}, state) do
    bucket = time_bucket_for_timestamp(timestamp_ms)
    new_state = add_to_signal(state, :transcription_signal, bucket, word_count)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast({:chat_event, timestamp_ms}, state) do
    bucket = time_bucket_for_timestamp(timestamp_ms)
    new_state = add_to_signal(state, :chat_signal, bucket, 1)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:estimate_delay, state) do
    new_state = perform_delay_estimation(state)

    # Schedule next estimation
    timer = Process.send_after(self(), :estimate_delay, @delay_estimation_interval_ms)
    new_state = %{new_state | estimation_timer: timer}

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:cleanup_signals, state) do
    new_state = cleanup_old_signals(state)

    # Schedule next cleanup
    timer = Process.send_after(self(), :cleanup_signals, @signal_cleanup_interval_ms)
    new_state = %{new_state | cleanup_timer: timer}

    {:noreply, new_state}
  end

  ## Private Functions

  defp current_time_bucket do
    System.system_time(:millisecond)
    |> div(@signal_bucket_size_ms)
    |> Kernel.*(@signal_bucket_size_ms)
  end

  defp time_bucket_for_timestamp(timestamp_ms) do
    timestamp_ms
    |> div(@signal_bucket_size_ms)
    |> Kernel.*(@signal_bucket_size_ms)
  end

  defp add_to_signal(state, signal_field, bucket, value) do
    current_signal = Map.get(state, signal_field)
    existing_value = Map.get(current_signal, bucket, 0)
    updated_signal = Map.put(current_signal, bucket, existing_value + value)

    Map.put(state, signal_field, updated_signal)
  end

  defp perform_delay_estimation(state) do
    Logger.debug("Performing stream delay estimation")

    new_state = %{state | total_estimations: state.total_estimations + 1}

    # Get recent signal data for cross-correlation
    cutoff_time = System.system_time(:millisecond) - @analysis_window_ms
    transcription_data = filter_recent_signal(state.transcription_signal, cutoff_time)
    chat_data = filter_recent_signal(state.chat_signal, cutoff_time)

    case calculate_cross_correlation(transcription_data, chat_data) do
      {:ok, delay_ms, correlation_peak} ->
        Logger.info("Detected stream delay: #{delay_ms}ms (confidence: #{Float.round(correlation_peak, 3)})")

        confidence = calculate_confidence(correlation_peak, state.delay_confidence)

        %{
          new_state
          | estimated_delay_ms: delay_ms,
            delay_confidence: confidence,
            last_estimation: DateTime.utc_now(),
            successful_estimations: new_state.successful_estimations + 1,
            last_correlation_peak: correlation_peak
        }

      {:error, reason} ->
        Logger.debug("Delay estimation failed: #{reason}")

        # Decay confidence in current estimate
        decayed_confidence = state.delay_confidence * @confidence_decay_rate

        %{new_state | delay_confidence: decayed_confidence, last_estimation: DateTime.utc_now()}
    end
  end

  defp filter_recent_signal(signal, cutoff_time) do
    signal
    |> Enum.filter(fn {bucket, _value} -> bucket >= cutoff_time end)
    |> Enum.sort_by(fn {bucket, _value} -> bucket end)
  end

  defp calculate_cross_correlation(transcription_data, chat_data) do
    # Convert signal data to time-aligned arrays for correlation
    if length(transcription_data) < 10 or length(chat_data) < 10 do
      {:error, "insufficient_signal_data"}
    else
      try do
        # Create aligned time series
        {trans_series, chat_series} = align_time_series(transcription_data, chat_data)

        # Calculate cross-correlation for different delays
        best_delay = find_best_correlation_delay(trans_series, chat_series)

        case best_delay do
          {delay_ms, correlation_value} when correlation_value >= @min_signal_strength ->
            {:ok, delay_ms, correlation_value}

          {_delay_ms, correlation_value} ->
            {:error, "correlation_too_weak: #{correlation_value}"}
        end
      rescue
        error ->
          {:error, "calculation_error: #{inspect(error)}"}
      end
    end
  end

  defp align_time_series(transcription_data, chat_data) do
    # Find common time range
    trans_buckets = Enum.map(transcription_data, fn {bucket, _} -> bucket end)
    chat_buckets = Enum.map(chat_data, fn {bucket, _} -> bucket end)

    min_bucket = max(Enum.min(trans_buckets), Enum.min(chat_buckets))
    max_bucket = min(Enum.max(trans_buckets), Enum.max(chat_buckets))

    # Create aligned series with 0 for missing buckets
    bucket_range = min_bucket..max_bucket//@signal_bucket_size_ms

    trans_map = Map.new(transcription_data)
    chat_map = Map.new(chat_data)

    trans_series = Enum.map(bucket_range, &Map.get(trans_map, &1, 0))
    chat_series = Enum.map(bucket_range, &Map.get(chat_map, &1, 0))

    {trans_series, chat_series}
  end

  defp find_best_correlation_delay(trans_series, chat_series) do
    delay_range = @delay_range_min_ms..@delay_range_max_ms//@signal_bucket_size_ms

    delay_range
    |> Enum.map(fn delay_ms ->
      # Convert delay to bucket offset
      bucket_offset = div(delay_ms, @signal_bucket_size_ms)

      # Calculate correlation at this delay
      correlation = calculate_correlation_at_offset(trans_series, chat_series, bucket_offset)

      {delay_ms, correlation}
    end)
    |> Enum.max_by(fn {_delay, correlation} -> correlation end)
  end

  defp calculate_correlation_at_offset(series1, series2, offset) do
    # Simple correlation calculation for the offset
    # This is a simplified version - could use more sophisticated correlation measures
    len1 = length(series1)
    len2 = length(series2)

    if offset >= 0 and offset < len2 do
      # Shift series2 by offset and compare overlapping portion
      shifted_series2 = Enum.drop(series2, offset)
      overlap_len = min(len1, length(shifted_series2))

      if overlap_len > 0 do
        s1_overlap = Enum.take(series1, overlap_len)
        s2_overlap = Enum.take(shifted_series2, overlap_len)

        # Calculate Pearson correlation coefficient
        pearson_correlation(s1_overlap, s2_overlap)
      else
        0.0
      end
    else
      0.0
    end
  end

  defp pearson_correlation(series1, series2) do
    n = length(series1)

    if n == 0 do
      0.0
    else
      mean1 = Enum.sum(series1) / n
      mean2 = Enum.sum(series2) / n

      numerator =
        Enum.zip(series1, series2)
        |> Enum.map(fn {x, y} -> (x - mean1) * (y - mean2) end)
        |> Enum.sum()

      sum_sq1 = Enum.map(series1, fn x -> (x - mean1) * (x - mean1) end) |> Enum.sum()
      sum_sq2 = Enum.map(series2, fn x -> (x - mean2) * (x - mean2) end) |> Enum.sum()

      denominator = :math.sqrt(sum_sq1 * sum_sq2)

      if denominator == 0.0 do
        0.0
      else
        numerator / denominator
      end
    end
  end

  defp calculate_confidence(correlation_peak, previous_confidence) do
    # Combine new correlation strength with historical confidence
    new_confidence = correlation_peak * 0.7 + previous_confidence * 0.3
    min(1.0, max(0.0, new_confidence))
  end

  defp cleanup_old_signals(state) do
    cutoff_time = System.system_time(:millisecond) - @analysis_window_ms * 2

    transcription_signal =
      Map.filter(state.transcription_signal, fn {bucket, _} ->
        bucket >= cutoff_time
      end)

    chat_signal =
      Map.filter(state.chat_signal, fn {bucket, _} ->
        bucket >= cutoff_time
      end)

    %{state | transcription_signal: transcription_signal, chat_signal: chat_signal}
  end

  defp signal_age_minutes(state) do
    if map_size(state.transcription_signal) > 0 do
      oldest_bucket = state.transcription_signal |> Map.keys() |> Enum.min()
      current_time = System.system_time(:millisecond)
      (current_time - oldest_bucket) / 60_000
    else
      0
    end
  end
end

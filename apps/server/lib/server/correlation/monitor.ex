defmodule Server.Correlation.Monitor do
  @moduledoc """
  Monitoring module for the correlation engine that tracks key metrics and exposes them via Phoenix telemetry.

  This module provides comprehensive monitoring for the correlation engine including:
  - Correlation detection metrics (count, patterns, confidence levels)
  - Buffer health metrics (size, pruning rate)
  - Database operation metrics (success/failure rates)
  - Performance metrics (processing latency)
  - Pattern distribution analysis
  - Rate calculations (correlations per minute)

  ## Telemetry Events

  The module emits the following telemetry events:

  - `[:correlation, :detection]` - When a correlation is detected
  - `[:correlation, :buffer, :prune]` - When buffers are pruned
  - `[:correlation, :database, :operation]` - Database operations
  - `[:correlation, :engine, :status]` - Engine status updates
  - `[:correlation, :performance]` - Performance metrics

  ## Dashboard Integration

  Metrics are automatically broadcast to the dashboard channel for real-time monitoring.
  """

  use GenServer
  require Logger

  # Metric collection intervals
  # 2 seconds
  @metrics_collection_interval 2_000
  # 1 minute window for rate calculations
  @rate_calculation_window 60_000
  # Update pattern distribution every 5 seconds
  @pattern_distribution_update 5_000

  # Metric history retention
  # Keep last 100 metric snapshots
  @max_metric_history 100

  defstruct [
    # Core metrics
    :correlation_count,
    :buffer_metrics,
    :database_metrics,
    :performance_metrics,
    :pattern_distribution,

    # Rate calculations
    :correlation_timestamps,
    :rate_metrics,

    # Metric history for trend analysis
    :metric_history,

    # State
    :last_collection_time,
    :started_at
  ]

  # Client API

  @doc """
  Starts the correlation monitor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets current metrics for dashboard display.

  ## Returns

  A map containing:
  - `:correlation_metrics` - Detection metrics and counts
  - `:buffer_health` - Buffer size and health status
  - `:database_metrics` - Database operation statistics
  - `:performance_metrics` - Processing latency and performance
  - `:rate_metrics` - Correlations per minute and trend data
  - `:pattern_distribution` - Distribution of correlation patterns
  - `:uptime_seconds` - Monitor uptime
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Records a correlation detection event with telemetry.

  ## Parameters

  - `correlation` - The correlation data
  - `processing_time_ms` - Time taken to process the correlation
  """
  def record_correlation_detected(correlation, processing_time_ms \\ nil) do
    GenServer.cast(__MODULE__, {:correlation_detected, correlation, processing_time_ms})
  end

  @doc """
  Records buffer pruning activity.

  ## Parameters

  - `buffer_type` - `:transcription` or `:chat`
  - `items_pruned` - Number of items removed
  - `new_size` - Buffer size after pruning
  """
  def record_buffer_pruned(buffer_type, items_pruned, new_size) do
    GenServer.cast(__MODULE__, {:buffer_pruned, buffer_type, items_pruned, new_size})
  end

  @doc """
  Records database operation results.

  ## Parameters

  - `operation` - Operation type (`:store_correlation`, `:start_session`, etc.)
  - `result` - `:success` or `:error`
  - `latency_ms` - Operation latency in milliseconds
  """
  def record_database_operation(operation, result, latency_ms) do
    GenServer.cast(__MODULE__, {:database_operation, operation, result, latency_ms})
  end

  @doc """
  Records engine status changes.

  ## Parameters

  - `status` - Status information map
  """
  def record_engine_status(status) do
    GenServer.cast(__MODULE__, {:engine_status, status})
  end

  @doc """
  Gets metric history for trend analysis.

  ## Parameters

  - `opts` - Options including `:limit` for number of historical points
  """
  def get_metric_history(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    GenServer.call(__MODULE__, {:get_metric_history, limit})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting Correlation Monitor")

    # Schedule periodic metric collection
    Process.send_after(self(), :collect_metrics, @metrics_collection_interval)
    Process.send_after(self(), :update_pattern_distribution, @pattern_distribution_update)

    state = %__MODULE__{
      correlation_count: 0,
      buffer_metrics: %{
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
      pattern_distribution: %{},
      correlation_timestamps: [],
      rate_metrics: %{
        correlations_per_minute: 0.0,
        trend: :stable,
        peak_rate: 0.0
      },
      metric_history: [],
      last_collection_time: System.system_time(:millisecond),
      started_at: System.system_time(:millisecond)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    current_time = System.system_time(:millisecond)
    uptime_seconds = div(current_time - state.started_at, 1000)

    metrics = %{
      correlation_metrics: %{
        total_count: state.correlation_count,
        patterns: state.pattern_distribution
      },
      buffer_health: state.buffer_metrics,
      database_metrics: state.database_metrics,
      performance_metrics: state.performance_metrics,
      rate_metrics: state.rate_metrics,
      pattern_distribution: state.pattern_distribution,
      uptime_seconds: uptime_seconds
    }

    {:reply, metrics, state}
  end

  @impl true
  def handle_call({:get_metric_history, limit}, _from, state) do
    history =
      state.metric_history
      |> Enum.take(limit)
      |> Enum.reverse()

    {:reply, history, state}
  end

  @impl true
  def handle_cast({:correlation_detected, correlation, processing_time_ms}, state) do
    current_time = System.system_time(:millisecond)

    # Update correlation count
    state = %{state | correlation_count: state.correlation_count + 1}

    # Track correlation timestamp for rate calculation
    timestamps = [current_time | state.correlation_timestamps]
    state = %{state | correlation_timestamps: timestamps}

    # Update performance metrics if processing time provided
    state =
      if processing_time_ms do
        update_performance_metrics(state, processing_time_ms)
      else
        state
      end

    # Emit telemetry
    :telemetry.execute(
      [:correlation, :detection],
      %{count: 1, processing_time: processing_time_ms || 0},
      %{
        pattern_type: correlation.pattern_type,
        confidence: correlation.confidence,
        time_offset_ms: correlation.time_offset_ms
      }
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast({:buffer_pruned, buffer_type, items_pruned, new_size}, state) do
    current_time = System.system_time(:millisecond)

    # Update buffer metrics
    buffer_metrics =
      state.buffer_metrics
      |> Map.put(:"#{buffer_type}_size", new_size)
      |> Map.put(:last_prune_time, current_time)
      |> update_prune_rate(items_pruned, current_time)

    state = %{state | buffer_metrics: buffer_metrics}

    # Emit telemetry
    :telemetry.execute(
      [:correlation, :buffer, :prune],
      %{items_pruned: items_pruned, new_size: new_size},
      %{buffer_type: buffer_type}
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast({:database_operation, operation, result, latency_ms}, state) do
    # Update database metrics
    database_metrics = update_database_metrics(state.database_metrics, result, latency_ms)
    state = %{state | database_metrics: database_metrics}

    # Emit telemetry
    :telemetry.execute(
      [:correlation, :database, :operation],
      %{latency: latency_ms, count: 1},
      %{operation: operation, result: result}
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast({:engine_status, status}, state) do
    # Update buffer metrics from engine status
    buffer_metrics =
      Map.merge(state.buffer_metrics, %{
        transcription_size: status[:transcription_count] || 0,
        chat_size: status[:chat_count] || 0,
        correlation_count: status[:correlation_count] || 0
      })

    state = %{state | buffer_metrics: buffer_metrics}

    # Emit telemetry
    :telemetry.execute(
      [:correlation, :engine, :status],
      %{count: 1},
      %{stream_active: status[:stream_active] || false}
    )

    {:noreply, state}
  end

  @impl true
  def handle_info(:collect_metrics, state) do
    # Collect current metrics and update rates
    current_time = System.system_time(:millisecond)

    # Update rate calculations
    state = update_rate_metrics(state, current_time)

    # Update circuit breaker status
    circuit_status = get_circuit_breaker_status()
    database_metrics = Map.put(state.database_metrics, :circuit_breaker_status, circuit_status.state)
    state = %{state | database_metrics: database_metrics}

    # Create metric snapshot for history
    snapshot = create_metric_snapshot(state, current_time)
    metric_history = [snapshot | state.metric_history] |> Enum.take(@max_metric_history)
    state = %{state | metric_history: metric_history}

    # Broadcast metrics to dashboard
    broadcast_metrics_to_dashboard(snapshot)

    # Emit performance telemetry
    :telemetry.execute(
      [:correlation, :performance],
      %{
        correlations_per_minute: state.rate_metrics.correlations_per_minute / 1,
        avg_processing_time: state.performance_metrics.avg_processing_time_ms / 1
      },
      %{trend: state.rate_metrics.trend}
    )

    state = %{state | last_collection_time: current_time}

    # Schedule next collection
    Process.send_after(self(), :collect_metrics, @metrics_collection_interval)

    {:noreply, state}
  end

  @impl true
  def handle_info(:update_pattern_distribution, state) do
    # Update pattern distribution from recent correlations
    pattern_distribution = fetch_recent_pattern_distribution()
    state = %{state | pattern_distribution: pattern_distribution}

    # Schedule next update
    Process.send_after(self(), :update_pattern_distribution, @pattern_distribution_update)

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Correlation Monitor received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp update_performance_metrics(state, processing_time_ms) do
    times = [processing_time_ms | state.performance_metrics.processing_times]
    # Keep only recent processing times (last 100)
    times = Enum.take(times, 100)

    avg_time = if Enum.empty?(times), do: 0.0, else: Enum.sum(times) / length(times)
    max_time = if Enum.empty?(times), do: 0.0, else: Enum.max(times)
    min_time = if Enum.empty?(times), do: 0.0, else: Enum.min(times)

    performance_metrics = %{
      avg_processing_time_ms: Float.round(avg_time, 2),
      max_processing_time_ms: max_time,
      min_processing_time_ms: min_time,
      processing_times: times
    }

    %{state | performance_metrics: performance_metrics}
  end

  defp update_prune_rate(buffer_metrics, items_pruned, current_time) do
    # Calculate pruning rate (items per minute)
    last_prune = buffer_metrics[:last_prune_time]

    if last_prune && current_time - last_prune > 0 do
      time_diff_minutes = (current_time - last_prune) / 60_000
      rate = items_pruned / time_diff_minutes
      Map.put(buffer_metrics, :prune_rate, Float.round(rate, 2))
    else
      Map.put(buffer_metrics, :prune_rate, 0.0)
    end
  end

  defp update_database_metrics(db_metrics, result, latency_ms) do
    total = db_metrics.operations_total + 1
    success_count = if result == :success, do: db_metrics.operations_success + 1, else: db_metrics.operations_success
    error_count = if result == :error, do: db_metrics.operations_error + 1, else: db_metrics.operations_error

    success_rate = if total > 0, do: success_count / total, else: 1.0

    # Update average latency
    current_avg = db_metrics.avg_latency_ms
    new_avg = if total == 1, do: latency_ms / 1, else: (current_avg * (total - 1) + latency_ms) / total

    %{
      operations_total: total,
      operations_success: success_count,
      operations_error: error_count,
      success_rate: Float.round(success_rate, 3),
      avg_latency_ms: Float.round(new_avg / 1, 2),
      circuit_breaker_status: db_metrics.circuit_breaker_status
    }
  end

  defp update_rate_metrics(state, current_time) do
    # Filter timestamps to last minute
    cutoff_time = current_time - @rate_calculation_window
    recent_timestamps = Enum.filter(state.correlation_timestamps, &(&1 > cutoff_time))

    # Calculate correlations per minute
    correlations_per_minute = length(recent_timestamps)

    # Determine trend based on recent history
    trend = calculate_trend(state.metric_history, correlations_per_minute)

    # Update peak rate
    peak_rate = max(state.rate_metrics.peak_rate, correlations_per_minute)

    rate_metrics = %{
      correlations_per_minute: correlations_per_minute,
      trend: trend,
      peak_rate: peak_rate
    }

    %{state | correlation_timestamps: recent_timestamps, rate_metrics: rate_metrics}
  end

  defp calculate_trend(metric_history, current_rate) do
    # Look at last 5 data points to determine trend
    recent_rates =
      metric_history
      |> Enum.take(5)
      |> Enum.map(&Map.get(&1, :correlations_per_minute, 0))

    if length(recent_rates) < 3 do
      :stable
    else
      avg_recent = Enum.sum(recent_rates) / length(recent_rates)

      cond do
        current_rate > avg_recent * 1.2 -> :increasing
        current_rate < avg_recent * 0.8 -> :decreasing
        true -> :stable
      end
    end
  end

  defp create_metric_snapshot(state, timestamp) do
    %{
      timestamp: timestamp,
      correlation_count: state.correlation_count,
      correlations_per_minute: state.rate_metrics.correlations_per_minute,
      buffer_health_score: calculate_buffer_health_score(state.buffer_metrics),
      database_success_rate: state.database_metrics.success_rate,
      avg_processing_time: state.performance_metrics.avg_processing_time_ms,
      circuit_breaker_status: state.database_metrics.circuit_breaker_status
    }
  end

  defp calculate_buffer_health_score(buffer_metrics) do
    # Simple health score based on buffer sizes and prune rate
    # Score from 0.0 (unhealthy) to 1.0 (healthy)

    trans_size = buffer_metrics.transcription_size || 0
    chat_size = buffer_metrics.chat_size || 0
    prune_rate = buffer_metrics.prune_rate || 0

    # Optimal buffer sizes (from correlation engine constants)
    # Half of max buffer size
    optimal_size = 50

    # Calculate size health (closer to optimal is better)
    size_health =
      (optimal_size - abs(trans_size - optimal_size)) / optimal_size +
        (optimal_size - abs(chat_size - optimal_size)) / optimal_size

    # Average and ensure non-negative
    size_health = max(0.0, size_health / 2)

    # Prune rate health (moderate pruning is healthy)
    prune_health =
      cond do
        # No pruning needed
        prune_rate == 0 -> 1.0
        # Low pruning is fine
        prune_rate <= 10 -> 1.0
        # Moderate pruning
        prune_rate <= 50 -> 0.7
        # High pruning indicates stress
        true -> 0.3
      end

    # Combine metrics
    health_score = size_health * 0.6 + prune_health * 0.4
    Float.round(min(1.0, max(0.0, health_score)), 3)
  end

  defp fetch_recent_pattern_distribution do
    # Get pattern distribution from correlation engine or repository
    try do
      # Try to get from repository for recent correlations
      recent_correlations = Server.Correlation.Repository.get_recent_correlations(limit: 100)

      pattern_counts =
        recent_correlations
        |> Enum.group_by(& &1.pattern_type)
        |> Enum.map(fn {pattern, correlations} ->
          {pattern,
           %{
             count: length(correlations),
             avg_confidence: calculate_avg_confidence(correlations)
           }}
        end)
        |> Map.new()

      pattern_counts
    rescue
      _ ->
        # Fallback to empty distribution if repository unavailable
        %{}
    end
  end

  defp calculate_avg_confidence(correlations) do
    if Enum.empty?(correlations) do
      0.0
    else
      avg = correlations |> Enum.map(& &1.confidence) |> Enum.sum() |> Kernel./(length(correlations))
      Float.round(avg, 3)
    end
  end

  defp get_circuit_breaker_status do
    try do
      Server.Correlation.Repository.get_circuit_breaker_status()
    rescue
      _ ->
        %{state: :unknown, failure_count: 0}
    end
  end

  defp broadcast_metrics_to_dashboard(metrics) do
    # Broadcast to dashboard channel for real-time monitoring
    Phoenix.PubSub.broadcast(
      Server.PubSub,
      "dashboard:telemetry",
      {:correlation_metrics, metrics}
    )
  end
end

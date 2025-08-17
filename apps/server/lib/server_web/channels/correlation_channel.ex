defmodule ServerWeb.CorrelationChannel do
  @moduledoc """
  Phoenix Channel for real-time correlation engine monitoring.

  Provides WebSocket access to correlation engine metrics, insights, and monitoring data.
  This channel is designed for dashboard integration and real-time monitoring of the
  correlation engine's performance and activity.

  ## Events Subscribed To
  - `correlation:insights` - New correlation detections
  - `dashboard:telemetry` - Correlation monitoring metrics

  ## Events Sent to Client
  - `correlation_metrics` - Real-time metrics update
  - `new_correlation` - Individual correlation detected
  - `engine_status` - Engine status changes
  - `buffer_health` - Buffer health updates
  - `performance_update` - Performance metrics

  ## Incoming Commands
  - `get_metrics` - Request current metrics
  - `get_correlations` - Request recent correlations
  - `get_engine_status` - Request engine status
  - `get_pattern_distribution` - Request pattern analysis
  """

  use ServerWeb.ChannelBase

  @impl true
  def join("correlation:" <> room_id, _payload, socket) do
    socket =
      socket
      |> setup_correlation_id()
      |> assign(:room_id, room_id)

    # Subscribe to correlation events
    topics = [
      "correlation:insights",
      "dashboard:telemetry"
    ]

    Logger.info("CorrelationChannel subscribing to PubSub topics",
      topics: topics,
      room_id: room_id
    )

    subscribe_to_topics(topics)

    # Send initial metrics after join
    send_after_join(socket, :send_initial_metrics)

    # Emit telemetry for channel join
    emit_joined_telemetry("correlation:#{room_id}", socket)

    {:ok, socket}
  end

  @impl true
  def handle_info(:send_initial_metrics, socket) do
    # Send current correlation metrics to the newly connected client
    # Handle gracefully if monitor is not available (e.g., in test environment)
    try do
      metrics = Server.Correlation.Engine.get_monitoring_metrics()

      push(socket, "correlation_metrics", %{
        data: metrics,
        timestamp: System.system_time(:second)
      })
    rescue
      _ ->
        # Monitor not available, send empty metrics
        push(socket, "correlation_metrics", %{
          data: %{
            correlation_metrics: %{total_count: 0},
            buffer_health: %{},
            database_metrics: %{},
            performance_metrics: %{},
            rate_metrics: %{},
            pattern_distribution: %{},
            uptime_seconds: 0
          },
          timestamp: System.system_time(:second)
        })
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_correlation, correlation}, socket) do
    # Forward new correlation insights to dashboard
    push(socket, "new_correlation", correlation)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:correlation_metrics, metrics}, socket) do
    # Forward correlation metrics updates from monitor
    # Extract data from nested monitor metrics structure
    push(socket, "correlation_metrics", %{
      data: %{
        correlation_count: get_in(metrics, [:buffer_health, :correlation_count]) || 0,
        correlations_per_minute: get_in(metrics, [:rate_metrics, :correlations_per_minute]) || 0.0,
        buffer_health_score: calculate_buffer_health_score(metrics),
        database_success_rate: get_in(metrics, [:database_metrics, :success_rate]) || 1.0,
        avg_processing_time: get_in(metrics, [:performance_metrics, :avg_processing_time_ms]) || 0.0,
        circuit_breaker_status: get_in(metrics, [:database_metrics, :circuit_breaker_status]) || :closed
      },
      timestamp: metrics[:timestamp] || System.system_time(:millisecond)
    })

    {:noreply, socket}
  end

  # Catch-all handler to prevent crashes from unexpected messages
  @impl true
  def handle_info(unhandled_msg, socket) do
    Logger.warning("Unhandled message in #{__MODULE__}",
      message: inspect(unhandled_msg),
      room_id: socket.assigns[:room_id]
    )

    {:noreply, socket}
  end

  # Handle incoming messages from client

  @impl true
  def handle_in("ping", payload, socket) do
    handle_ping(payload, socket)
  end

  @impl true
  def handle_in("get_metrics", _payload, socket) do
    correlation_id = socket.assigns.correlation_id

    CorrelationId.with_context(correlation_id, fn ->
      try do
        metrics = Server.Correlation.Engine.get_monitoring_metrics()
        {:ok, response} = ResponseBuilder.success(metrics)
        {:reply, {:ok, response}, socket}
      rescue
        _ ->
          # Return minimal metrics if monitor unavailable
          minimal_metrics = %{
            correlation_metrics: %{total_count: 0},
            buffer_health: %{},
            database_metrics: %{},
            performance_metrics: %{},
            rate_metrics: %{},
            pattern_distribution: %{},
            uptime_seconds: 0
          }

          {:ok, response} = ResponseBuilder.success(minimal_metrics)
          {:reply, {:ok, response}, socket}
      end
    end)
  end

  @impl true
  def handle_in("get_correlations", %{"limit" => limit}, socket) when is_integer(limit) do
    correlation_id = socket.assigns.correlation_id

    CorrelationId.with_context(correlation_id, fn ->
      try do
        correlations = Server.Correlation.Engine.get_recent_correlations(limit)

        {:ok, response} = ResponseBuilder.success(%{correlations: correlations})
        {:reply, {:ok, response}, socket}
      catch
        :exit, _ ->
          {:ok, response} = ResponseBuilder.success(%{correlations: []})
          {:reply, {:ok, response}, socket}
      end
    end)
  end

  @impl true
  def handle_in("get_correlations", _payload, socket) do
    # Default to 20 recent correlations
    handle_in("get_correlations", %{"limit" => 20}, socket)
  end

  @impl true
  def handle_in("get_engine_status", _payload, socket) do
    correlation_id = socket.assigns.correlation_id

    CorrelationId.with_context(correlation_id, fn ->
      try do
        status = Server.Correlation.Engine.get_buffer_state()

        {:ok, response} = ResponseBuilder.success(status)
        {:reply, {:ok, response}, socket}
      catch
        :exit, _ ->
          minimal_status = %{
            transcription_count: 0,
            chat_count: 0,
            correlation_count: 0,
            stream_active: false,
            fingerprint_count: 0
          }

          {:ok, response} = ResponseBuilder.success(minimal_status)
          {:reply, {:ok, response}, socket}
      end
    end)
  end

  @impl true
  def handle_in("get_pattern_distribution", _payload, socket) do
    correlation_id = socket.assigns.correlation_id

    CorrelationId.with_context(correlation_id, fn ->
      try do
        metrics = Server.Correlation.Engine.get_monitoring_metrics()
        pattern_data = metrics.pattern_distribution

        {:ok, response} = ResponseBuilder.success(%{patterns: pattern_data})
        {:reply, {:ok, response}, socket}
      rescue
        _ ->
          {:ok, response} = ResponseBuilder.success(%{patterns: %{}})
          {:reply, {:ok, response}, socket}
      end
    end)
  end

  @impl true
  def handle_in("get_metric_history", %{"limit" => limit}, socket) when is_integer(limit) do
    correlation_id = socket.assigns.correlation_id

    CorrelationId.with_context(correlation_id, fn ->
      try do
        history = Server.Correlation.Monitor.get_metric_history(limit: limit)

        {:ok, response} = ResponseBuilder.success(%{history: history})
        {:reply, {:ok, response}, socket}
      catch
        :exit, _ ->
          {:ok, response} = ResponseBuilder.success(%{history: []})
          {:reply, {:ok, response}, socket}
      end
    end)
  end

  @impl true
  def handle_in("get_metric_history", _payload, socket) do
    # Default to 50 historical data points
    handle_in("get_metric_history", %{"limit" => 50}, socket)
  end

  # Catch-all for unhandled events
  @impl true
  def handle_in(event, payload, socket) do
    log_unhandled_message(event, payload, socket)
    {:error, response} = ResponseBuilder.error("unknown_command", "Command not recognized")
    {:reply, {:error, response}, socket}
  end

  # Private helper functions

  defp calculate_buffer_health_score(metrics) do
    # Simple health score based on buffer utilization and prune rate
    # Returns a value between 0.0 (poor) and 1.0 (excellent)
    buffer_health = get_in(metrics, [:buffer_health]) || %{}

    transcription_size = Map.get(buffer_health, :transcription_size, 0)
    chat_size = Map.get(buffer_health, :chat_size, 0)
    prune_rate = Map.get(buffer_health, :prune_rate, 0.0)

    # Assume healthy buffer sizes are under 80% of max capacity (100 items)
    # and prune rate is reasonable (< 10 items/minute)
    max_healthy_size = 80
    max_healthy_prune_rate = 10.0

    size_score = max(0.0, 1.0 - max(transcription_size, chat_size) / max_healthy_size)
    prune_score = max(0.0, 1.0 - prune_rate / max_healthy_prune_rate)

    # Weight size more heavily than prune rate
    (size_score * 0.7 + prune_score * 0.3) |> Float.round(2)
  end
end

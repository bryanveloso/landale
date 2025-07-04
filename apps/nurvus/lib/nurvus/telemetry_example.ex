defmodule Nurvus.TelemetryExample do
  @moduledoc """
  Example telemetry handlers for Nurvus events.

  This module demonstrates how to attach telemetry handlers to monitor
  process lifecycle events, HTTP API performance, and system metrics.

  To use this in your application:

      # In your application start
      Nurvus.TelemetryExample.attach_handlers()

  Available telemetry events:

  ## Process Lifecycle
  - [:nurvus, :process, :started] - When a process starts
  - [:nurvus, :process, :stopped] - When a process is manually stopped
  - [:nurvus, :process, :restarted] - When a process is manually restarted
  - [:nurvus, :process, :crashed] - When a process crashes
  - [:nurvus, :process, :auto_restart_scheduled] - When auto-restart is triggered

  ## HTTP API
  - [:nurvus, :http, :request] - HTTP request timing and metadata

  ## Metrics & Monitoring
  - [:nurvus, :metrics, :collected] - Process metrics collection
  - [:nurvus, :alert, :generated] - System alerts (high CPU/memory)
  """

  require Logger

  def attach_handlers do
    # Process lifecycle events
    :telemetry.attach_many(
      "nurvus-process-lifecycle",
      [
        [:nurvus, :process, :started],
        [:nurvus, :process, :stopped],
        [:nurvus, :process, :restarted],
        [:nurvus, :process, :crashed],
        [:nurvus, :process, :auto_restart_scheduled]
      ],
      &handle_process_event/4,
      %{}
    )

    # HTTP API events
    :telemetry.attach(
      "nurvus-http-requests",
      [:nurvus, :http, :request],
      &handle_http_event/4,
      %{}
    )

    # Metrics events
    :telemetry.attach(
      "nurvus-metrics",
      [:nurvus, :metrics, :collected],
      &handle_metrics_event/4,
      %{}
    )

    # Alert events
    :telemetry.attach(
      "nurvus-alerts",
      [:nurvus, :alert, :generated],
      &handle_alert_event/4,
      %{}
    )

    Logger.info("Attached Nurvus telemetry handlers")
  end

  def detach_handlers do
    :telemetry.detach("nurvus-process-lifecycle")
    :telemetry.detach("nurvus-http-requests")
    :telemetry.detach("nurvus-metrics")
    :telemetry.detach("nurvus-alerts")

    Logger.info("Detached Nurvus telemetry handlers")
  end

  ## Event Handlers

  defp handle_process_event([:nurvus, :process, event], _measurements, metadata, _config) do
    case event do
      :started ->
        Logger.info("🚀 Process #{metadata.process_id} (#{metadata.process_name}) started")

      :stopped ->
        Logger.info("⏹️  Process #{metadata.process_id} stopped")

      :restarted ->
        Logger.info("🔄 Process #{metadata.process_id} restarted")

      :crashed ->
        Logger.warning("💥 Process #{metadata.process_id} crashed: #{metadata.reason}")

      :auto_restart_scheduled ->
        Logger.info("🔧 Auto-restart scheduled for #{metadata.process_id}")
    end
  end

  defp handle_http_event([:nurvus, :http, :request], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.debug("🌐 #{metadata.method} #{metadata.path} → #{metadata.status} (#{duration_ms}ms)")

    # You could send this to a metrics system like StatsD, Prometheus, etc.
    # Example: send_to_metrics_system("http.request.duration", duration_ms, metadata)
  end

  defp handle_metrics_event([:nurvus, :metrics, :collected], measurements, metadata, _config) do
    # Log if metrics are concerning
    if measurements.cpu_percent > 50 or measurements.memory_mb > 200 do
      Logger.info(
        "📊 #{metadata.process_id}: CPU #{Float.round(measurements.cpu_percent, 1)}%, " <>
          "Memory #{Float.round(measurements.memory_mb, 1)}MB, " <>
          "Uptime #{measurements.uptime_seconds}s"
      )
    end

    # You could aggregate metrics here for dashboards
    # Example: store_metrics(metadata.process_id, measurements)
  end

  defp handle_alert_event([:nurvus, :alert, :generated], _measurements, metadata, _config) do
    case metadata.alert_type do
      :high_cpu ->
        Logger.warning(
          "🔥 HIGH CPU ALERT: #{metadata.process_id} using #{metadata.cpu_percent}% CPU"
        )

      :high_memory ->
        Logger.warning(
          "🧠 HIGH MEMORY ALERT: #{metadata.process_id} using #{metadata.memory_mb}MB memory"
        )
    end

    # You could send alerts to external systems here
    # Example: send_to_slack(metadata) or send_to_pagerduty(metadata)
  end
end

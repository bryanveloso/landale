defmodule Server.ConnectionManagerTelemetry do
  @moduledoc """
  Telemetry instrumentation for ConnectionManager.

  This module adds low-overhead telemetry events to monitor connection
  management operations without affecting existing functionality.

  ## Events

  The following events are emitted:

  * `[:connection_manager, :monitor, :add]` - When a monitor is added
    * Measurements: none
    * Metadata: `:pid`, `:label`
    
  * `[:connection_manager, :monitor, :remove]` - When a monitor is removed
    * Measurements: none
    * Metadata: `:pid`, `:label`, `:found`
    
  * `[:connection_manager, :monitor, :down]` - When a monitored process goes down
    * Measurements: none
    * Metadata: `:pid`, `:label`, `:reason`
    
  * `[:connection_manager, :timer, :add]` - When a timer is added
    * Measurements: none
    * Metadata: `:label`
    
  * `[:connection_manager, :timer, :cancel]` - When a timer is cancelled
    * Measurements: none
    * Metadata: `:label`, `:found`
    
  * `[:connection_manager, :cleanup]` - When cleanup operations occur
    * Measurements: `:monitor_count`, `:timer_count`
    * Metadata: none
  """

  require Logger

  @doc """
  Emits a telemetry event for adding a monitor.
  """
  def monitor_added(pid, label) do
    :telemetry.execute(
      [:connection_manager, :monitor, :add],
      %{},
      %{pid: pid, label: label}
    )
  end

  @doc """
  Emits a telemetry event for removing a monitor.
  """
  def monitor_removed(pid, label, found?) do
    :telemetry.execute(
      [:connection_manager, :monitor, :remove],
      %{},
      %{pid: pid, label: label, found: found?}
    )
  end

  @doc """
  Emits a telemetry event for a monitor going down.
  """
  def monitor_down(pid, label, reason) do
    :telemetry.execute(
      [:connection_manager, :monitor, :down],
      %{},
      %{pid: pid, label: label, reason: reason}
    )
  end

  @doc """
  Emits a telemetry event for adding a timer.
  """
  def timer_added(label) do
    :telemetry.execute(
      [:connection_manager, :timer, :add],
      %{},
      %{label: label}
    )
  end

  @doc """
  Emits a telemetry event for cancelling a timer.
  """
  def timer_cancelled(label, found?) do
    :telemetry.execute(
      [:connection_manager, :timer, :cancel],
      %{},
      %{label: label, found: found?}
    )
  end

  @doc """
  Emits a telemetry event for cleanup operations.
  """
  def cleanup(monitor_count, timer_count) do
    :telemetry.execute(
      [:connection_manager, :cleanup],
      %{monitor_count: monitor_count, timer_count: timer_count},
      %{}
    )
  end

  @doc """
  Attaches default handlers for logging telemetry events.
  Call this in your application startup.
  """
  def attach_default_handlers do
    events = [
      [:connection_manager, :monitor, :add],
      [:connection_manager, :monitor, :remove],
      [:connection_manager, :monitor, :down],
      [:connection_manager, :timer, :add],
      [:connection_manager, :timer, :cancel],
      [:connection_manager, :cleanup]
    ]

    :telemetry.attach_many(
      "connection-manager-log-handler",
      events,
      &handle_event/4,
      nil
    )
  end

  defp handle_event([:connection_manager, :monitor, :down], _measurements, metadata, _config) do
    if metadata.reason != :normal do
      Logger.warning("ConnectionManager monitored process went down",
        pid: inspect(metadata.pid),
        label: metadata.label,
        reason: inspect(metadata.reason)
      )
    end
  end

  defp handle_event([:connection_manager, :cleanup], measurements, _metadata, _config) do
    if measurements.monitor_count > 0 || measurements.timer_count > 0 do
      Logger.debug("ConnectionManager cleanup performed",
        monitors_cleaned: measurements.monitor_count,
        timers_cleaned: measurements.timer_count
      )
    end
  end

  defp handle_event(_event, _measurements, _metadata, _config) do
    # Other events are handled silently by default
    :ok
  end
end

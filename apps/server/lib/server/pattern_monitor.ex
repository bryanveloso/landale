defmodule Server.PatternMonitor do
  @moduledoc """
  Telemetry-based monitoring for data access patterns.

  Tracks and reports on:
  - Mixed access pattern occurrences
  - Pattern conversion events
  - Potential crash points
  - Performance impact of conversions

  ## Architecture
  Attaches to telemetry events from SafeTokenHandler, BoundaryConverter,
  and ChannelSafety to provide real-time visibility into pattern issues.

  ## Usage
      # Start monitoring in application.ex
      Server.PatternMonitor.start_link([])

      # View current stats
      Server.PatternMonitor.get_stats()

      # Reset counters
      Server.PatternMonitor.reset_stats()
  """

  use GenServer
  require Logger

  @telemetry_events [
    [:server, :safe_token_handler, :access_pattern],
    [:server, :safe_token_handler, :new_atom_created],
    [:server, :boundary_converter, :conversion],
    [:server, :boundary_converter, :unknown_field],
    [:server, :channel_safety, :pattern_conversion],
    [:server, :channel_safety, :crash_prevented],
    [:server, :channel_safety, :handle_in],
    # DataAccessGuard events
    [:server, :data_access_guard, :validation],
    [:server, :data_access_guard, :warn],
    [:server, :data_access_guard, :error],
    [:server, :data_access_guard, :location]
  ]

  defmodule State do
    @moduledoc false
    defstruct [
      :started_at,
      pattern_counts: %{},
      conversion_counts: %{},
      crash_prevention_count: 0,
      unknown_fields: MapSet.new(),
      performance_metrics: %{},
      hourly_stats: %{},
      # DataAccessGuard tracking
      data_guard_stats: %{
        validations: 0,
        warnings: 0,
        errors: 0,
        # Map of {module, function, line} -> count
        locations: %{}
      }
    ]
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  def reset_stats do
    GenServer.call(__MODULE__, :reset_stats)
  end

  def get_report do
    GenServer.call(__MODULE__, :get_report)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Attach telemetry handlers
    attach_telemetry_handlers()

    # Schedule periodic reporting
    schedule_periodic_report()

    {:ok, %State{started_at: DateTime.utc_now()}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      uptime_hours: DateTime.diff(DateTime.utc_now(), state.started_at, :hour),
      pattern_counts: state.pattern_counts,
      conversion_counts: state.conversion_counts,
      crashes_prevented: state.crash_prevention_count,
      unique_unknown_fields: MapSet.size(state.unknown_fields),
      performance_metrics: calculate_performance_metrics(state),
      data_access_guard: state.data_guard_stats
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:reset_stats, _from, _state) do
    new_state = %State{started_at: DateTime.utc_now()}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_report, _from, state) do
    report = generate_detailed_report(state)
    {:reply, report, state}
  end

  @impl true
  def handle_info(:periodic_report, state) do
    # Log summary statistics
    if should_log_report?(state) do
      log_pattern_report(state)
    end

    # Update hourly stats
    current_time = DateTime.utc_now()
    hour_key = DateTime.truncate(current_time, :hour)
    updated_hourly = update_hourly_stats(state.hourly_stats, hour_key, state)

    # Schedule next report
    schedule_periodic_report()

    {:noreply, %{state | hourly_stats: updated_hourly}}
  end

  @impl true
  def handle_info({:telemetry_event, measurements, metadata, event_name}, state) do
    updated_state = handle_telemetry_event(event_name, measurements, metadata, state)
    {:noreply, updated_state}
  end

  # Telemetry handling

  defp attach_telemetry_handlers do
    Enum.each(@telemetry_events, fn event ->
      handler_id = "pattern-monitor-#{Enum.join(event, "-")}"

      :telemetry.attach(
        handler_id,
        event,
        &handle_telemetry/4,
        nil
      )
    end)
  end

  defp handle_telemetry(event_name, measurements, metadata, _config) do
    send(__MODULE__, {:telemetry_event, measurements, metadata, event_name})
  end

  defp handle_telemetry_event([:server, :safe_token_handler, :access_pattern], _measurements, metadata, state) do
    pattern_type = metadata[:type]
    updated_counts = Map.update(state.pattern_counts, pattern_type, 1, &(&1 + 1))

    %{state | pattern_counts: updated_counts}
  end

  defp handle_telemetry_event([:server, :safe_token_handler, :new_atom_created], _measurements, metadata, state) do
    field = metadata[:field]
    updated_fields = MapSet.put(state.unknown_fields, field)

    # Log if we're creating many new atoms
    if MapSet.size(updated_fields) > 50 and rem(MapSet.size(updated_fields), 10) == 0 do
      Logger.warning("High number of new atoms being created",
        count: MapSet.size(updated_fields),
        latest: field
      )
    end

    %{state | unknown_fields: updated_fields}
  end

  defp handle_telemetry_event([:server, :boundary_converter, :conversion], _measurements, metadata, state) do
    direction = metadata[:direction]
    key = {direction, metadata[:keys]}
    updated_counts = Map.update(state.conversion_counts, key, 1, &(&1 + 1))

    %{state | conversion_counts: updated_counts}
  end

  defp handle_telemetry_event([:server, :boundary_converter, :unknown_field], _measurements, metadata, state) do
    field = metadata[:field]
    updated_fields = MapSet.put(state.unknown_fields, field)

    # Log if we're seeing many unknown fields from boundary converter
    if MapSet.size(updated_fields) > 50 and rem(MapSet.size(updated_fields), 10) == 0 do
      Logger.warning("High number of unknown fields from BoundaryConverter",
        count: MapSet.size(updated_fields),
        latest: field
      )
    end

    %{state | unknown_fields: updated_fields}
  end

  defp handle_telemetry_event([:server, :channel_safety, :crash_prevented], _measurements, _metadata, state) do
    %{state | crash_prevention_count: state.crash_prevention_count + 1}
  end

  defp handle_telemetry_event([:server, :channel_safety, :handle_in], measurements, metadata, state) do
    duration = measurements[:duration_us]
    event = metadata[:event]

    updated_metrics =
      update_performance_metrics(
        state.performance_metrics,
        event,
        duration
      )

    %{state | performance_metrics: updated_metrics}
  end

  defp handle_telemetry_event([:server, :data_access_guard, :validation], _measurements, _metadata, state) do
    updated_stats =
      state.data_guard_stats
      |> Map.update(:validations, 1, &(&1 + 1))

    %{state | data_guard_stats: updated_stats}
  end

  defp handle_telemetry_event([:server, :data_access_guard, :warn], _measurements, metadata, state) do
    updated_stats =
      state.data_guard_stats
      |> Map.update(:warnings, 1, &(&1 + 1))

    # Log warning for investigation
    Logger.warning(
      "DataAccessGuard warning at #{metadata.module}.#{elem(metadata.function, 0)}/#{elem(metadata.function, 1)}:#{metadata.line}",
      schema: metadata.schema,
      reason: metadata[:reason]
    )

    %{state | data_guard_stats: updated_stats}
  end

  defp handle_telemetry_event([:server, :data_access_guard, :error], _measurements, _metadata, state) do
    updated_stats =
      state.data_guard_stats
      |> Map.update(:errors, 1, &(&1 + 1))

    %{state | data_guard_stats: updated_stats}
  end

  defp handle_telemetry_event([:server, :data_access_guard, :location], _measurements, metadata, state) do
    location_key = {metadata.module, metadata.function, metadata.line}

    updated_locations =
      state.data_guard_stats.locations
      |> Map.update(location_key, 1, &(&1 + 1))

    updated_stats =
      state.data_guard_stats
      |> Map.put(:locations, updated_locations)

    # Log if this location is becoming problematic
    if Map.get(updated_locations, location_key) == 10 do
      Logger.warning("DataAccessGuard: Frequent validation failures at #{inspect(location_key)}")
    end

    %{state | data_guard_stats: updated_stats}
  end

  defp handle_telemetry_event(_event, _measurements, _metadata, state) do
    state
  end

  # Reporting functions

  defp schedule_periodic_report do
    # Report every 5 minutes
    Process.send_after(self(), :periodic_report, 5 * 60 * 1000)
  end

  defp should_log_report?(state) do
    # Log if we have concerning patterns
    mixed_patterns = Map.get(state.pattern_counts, :mixed_map, 0)
    string_patterns = Map.get(state.pattern_counts, :string_map, 0)
    crashes_prevented = state.crash_prevention_count

    mixed_patterns > 0 or string_patterns > 10 or crashes_prevented > 0
  end

  defp log_pattern_report(state) do
    Logger.info("Data Access Pattern Report",
      pattern_counts: inspect(state.pattern_counts),
      crashes_prevented: state.crash_prevention_count,
      unknown_fields: MapSet.size(state.unknown_fields),
      top_unknown: state.unknown_fields |> Enum.take(5)
    )

    # Log critical issues
    if state.crash_prevention_count > 0 do
      Logger.error("CRITICAL: Channel crashes were prevented",
        count: state.crash_prevention_count,
        action: "Investigate and fix data access patterns immediately"
      )
    end

    mixed_count = Map.get(state.pattern_counts, :mixed_map, 0)

    if mixed_count > 0 do
      Logger.warning("Mixed data access patterns detected",
        occurrences: mixed_count,
        action: "Review code for consistent map access"
      )
    end
  end

  defp generate_detailed_report(state) do
    %{
      summary: %{
        monitoring_since: state.started_at,
        total_conversions: Enum.sum(Map.values(state.conversion_counts)),
        crashes_prevented: state.crash_prevention_count,
        pattern_distribution: calculate_pattern_distribution(state.pattern_counts)
      },
      patterns: %{
        atom_maps: Map.get(state.pattern_counts, :atom_map, 0),
        string_maps: Map.get(state.pattern_counts, :string_map, 0),
        mixed_maps: Map.get(state.pattern_counts, :mixed_map, 0)
      },
      risk_assessment: assess_risk_level(state),
      recommendations: generate_recommendations(state),
      unknown_fields: Enum.take(state.unknown_fields, 20)
    }
  end

  defp calculate_pattern_distribution(pattern_counts) do
    total = Enum.sum(Map.values(pattern_counts))

    if total > 0 do
      pattern_counts
      |> Enum.map(fn {type, count} ->
        {type, Float.round(count / total * 100, 2)}
      end)
      |> Enum.into(%{})
    else
      %{}
    end
  end

  defp assess_risk_level(state) do
    mixed_count = Map.get(state.pattern_counts, :mixed_map, 0)
    crashes = state.crash_prevention_count

    cond do
      crashes > 10 or mixed_count > 100 -> :critical
      crashes > 5 or mixed_count > 50 -> :high
      crashes > 0 or mixed_count > 10 -> :medium
      mixed_count > 0 -> :low
      true -> :none
    end
  end

  defp generate_recommendations(state) do
    recommendations = []

    mixed_count = Map.get(state.pattern_counts, :mixed_map, 0)

    recommendations =
      if mixed_count > 0 do
        recommendations ++ ["Fix mixed access patterns in #{mixed_count} locations"]
      else
        recommendations
      end

    recommendations =
      if state.crash_prevention_count > 0 do
        recommendations ++ ["Investigate #{state.crash_prevention_count} prevented crashes"]
      else
        recommendations
      end

    recommendations =
      if MapSet.size(state.unknown_fields) > 50 do
        recommendations ++ ["Review #{MapSet.size(state.unknown_fields)} unknown fields for schema definition"]
      else
        recommendations
      end

    recommendations
  end

  defp update_performance_metrics(metrics, event, duration) do
    Map.update(metrics, event, {1, duration, duration, duration}, fn {count, total, min, max} ->
      {
        count + 1,
        total + duration,
        min(min, duration),
        max(max, duration)
      }
    end)
  end

  defp calculate_performance_metrics(state) do
    state.performance_metrics
    |> Enum.map(fn {event, {count, total, min, max}} ->
      {event,
       %{
         count: count,
         avg_us: div(total, count),
         min_us: min,
         max_us: max
       }}
    end)
    |> Enum.into(%{})
  end

  defp update_hourly_stats(hourly_stats, hour_key, current_state) do
    stats_snapshot = %{
      patterns: current_state.pattern_counts,
      crashes: current_state.crash_prevention_count,
      unknown_fields: MapSet.size(current_state.unknown_fields)
    }

    Map.put(hourly_stats, hour_key, stats_snapshot)
    # Keep last 24 hours
    |> keep_recent_hours(24)
  end

  defp keep_recent_hours(hourly_stats, hours_to_keep) do
    current_utc = DateTime.utc_now()
    cutoff = DateTime.add(current_utc, -hours_to_keep, :hour)

    hourly_stats
    |> Enum.filter(fn {hour, _} -> DateTime.compare(hour, cutoff) == :gt end)
    |> Enum.into(%{})
  end
end

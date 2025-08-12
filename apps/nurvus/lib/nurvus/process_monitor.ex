defmodule Nurvus.ProcessMonitor do
  @moduledoc """
  GenServer that provides health monitoring and metrics collection for managed processes.

  This module:
  - Periodically checks process health
  - Collects CPU, memory, and runtime metrics
  - Triggers alerts for unhealthy processes
  - Maintains historical performance data
  """

  use GenServer
  require Logger

  # 30 seconds
  @default_check_interval Duration.new!(second: 30)
  @default_history_limit 100

  defstruct [
    :check_interval,
    :history_limit,
    metrics: %{},
    alerts: [],
    last_check: nil
  ]

  ## Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_metrics(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_metrics(process_id) do
    GenServer.call(__MODULE__, {:get_metrics, process_id})
  end

  @spec get_all_metrics() :: map()
  def get_all_metrics do
    GenServer.call(__MODULE__, :get_all_metrics)
  end

  @spec get_alerts() :: [map()]
  def get_alerts do
    GenServer.call(__MODULE__, :get_alerts)
  end

  @spec clear_alerts() :: :ok
  def clear_alerts do
    GenServer.cast(__MODULE__, :clear_alerts)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    check_interval = Keyword.get(opts, :check_interval, @default_check_interval)
    history_limit = Keyword.get(opts, :history_limit, @default_history_limit)

    state = %__MODULE__{
      check_interval: check_interval,
      history_limit: history_limit,
      metrics: %{},
      alerts: [],
      last_check: DateTime.utc_now()
    }

    # Schedule first health check
    schedule_health_check(check_interval)

    {:ok, state}
  end

  @impl true
  def handle_call({:get_metrics, process_id}, _from, state) do
    case Map.get(state.metrics, process_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      metrics ->
        {:reply, {:ok, metrics}, state}
    end
  end

  @impl true
  def handle_call(:get_all_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  @impl true
  def handle_call(:get_alerts, _from, state) do
    {:reply, state.alerts, state}
  end

  @impl true
  def handle_cast(:clear_alerts, state) do
    {:noreply, %{state | alerts: []}}
  end

  @impl true
  def handle_info(:health_check, state) do
    Logger.debug("Running health check for all processes")

    # Get list of running processes
    processes = Nurvus.ProcessManager.list_processes()

    # Collect metrics for each running process
    {new_metrics, new_alerts} = collect_metrics(processes, state.metrics, state.alerts)

    # Update state
    new_state = %{
      state
      | metrics: new_metrics,
        alerts: new_alerts,
        last_check: DateTime.utc_now()
    }

    # Schedule next check
    schedule_health_check(state.check_interval)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message in ProcessMonitor: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Functions

  defp schedule_health_check(%Duration{} = interval) do
    interval_ms = System.convert_time_unit(interval.second, :second, :millisecond)
    Process.send_after(self(), :health_check, interval_ms)
  end

  defp schedule_health_check(interval) when is_integer(interval) do
    Process.send_after(self(), :health_check, interval)
  end

  defp collect_metrics(processes, existing_metrics, existing_alerts) do
    Enum.reduce(processes, {existing_metrics, existing_alerts}, fn process, acc ->
      collect_single_process_metrics(process, acc)
    end)
  end

  defp collect_single_process_metrics(process, {acc_metrics, acc_alerts}) do
    case process.status do
      :running -> handle_running_process(process, acc_metrics, acc_alerts)
      _ -> handle_stopped_process(process, acc_metrics, acc_alerts)
    end
  end

  defp handle_running_process(process, acc_metrics, acc_alerts) do
    case collect_process_metrics(process.id) do
      {:ok, metrics} ->
        updated_metrics = update_process_metrics(acc_metrics, process.id, metrics)
        new_alerts = check_for_alerts(process.id, metrics, acc_alerts)
        {updated_metrics, new_alerts}

      {:error, reason} ->
        Logger.warning("Failed to collect metrics for #{process.id}: #{inspect(reason)}")
        {acc_metrics, acc_alerts}
    end
  end

  defp handle_stopped_process(process, acc_metrics, acc_alerts) do
    # Process not running, remove from metrics
    {Map.delete(acc_metrics, process.id), acc_alerts}
  end

  defp update_process_metrics(acc_metrics, process_id, metrics) do
    process_metrics = Map.get(acc_metrics, process_id, %{history: [], current: nil})
    updated_history = add_to_history(process_metrics.history, metrics, 100)
    updated_metrics = %{current: metrics, history: updated_history}
    Map.put(acc_metrics, process_id, updated_metrics)
  end

  defp collect_process_metrics(process_id) do
    # Get process status first
    case Nurvus.ProcessManager.get_process_status(process_id) do
      {:ok, :running} ->
        # For now, just return base metrics
        # TODO: Add health check integration once ProcessManager exposes config
        metrics = collect_base_metrics(process_id)
        {:ok, metrics}

      _ ->
        {:error, :not_running}
    end
  end

  defp add_to_history(history, new_entry, limit) do
    updated_history = [new_entry | history]

    if length(updated_history) > limit do
      Enum.take(updated_history, limit)
    else
      updated_history
    end
  end

  defp check_for_alerts(process_id, metrics, existing_alerts) do
    alerts = []

    # Check CPU usage
    alerts =
      if metrics.cpu_percent > 80 do
        alert = %{
          process_id: process_id,
          type: :high_cpu,
          message: "High CPU usage: #{Float.round(metrics.cpu_percent, 1)}%",
          timestamp: DateTime.utc_now(),
          severity: :warning
        }

        [alert | alerts]
      else
        alerts
      end

    # Check memory usage
    alerts =
      if metrics.memory_mb > 500 do
        alert = %{
          process_id: process_id,
          type: :high_memory,
          message: "High memory usage: #{Float.round(metrics.memory_mb, 1)}MB",
          timestamp: DateTime.utc_now(),
          severity: :warning
        }

        [alert | alerts]
      else
        alerts
      end

    # Add new alerts to existing ones (keep last 50)
    all_alerts = alerts ++ existing_alerts
    Enum.take(all_alerts, 50)
  end

  defp collect_base_metrics(_process_id) do
    timestamp = DateTime.utc_now()

    # For now, return mock metrics
    # In a real implementation, we'd collect:
    # - CPU usage via platform-specific tools
    # - Memory usage (RSS, VSZ)
    # - File descriptors
    # - Network connections
    # - Uptime from process start time

    %{
      timestamp: timestamp,
      # Mock CPU usage 0-10%
      cpu_percent: :rand.uniform() * 10,
      # Mock memory 50-150MB
      memory_mb: :rand.uniform(100) + 50,
      # Mock uptime
      uptime_seconds: :rand.uniform(3600),
      file_descriptors: :rand.uniform(20),
      status: :healthy
    }
  end
end

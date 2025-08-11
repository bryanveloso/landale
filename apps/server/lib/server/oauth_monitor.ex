defmodule Server.OAuthMonitor do
  @moduledoc """
  Comprehensive monitoring and alerting for OAuth operations.

  Provides operational visibility into:
  - Token refresh health and retry patterns
  - Circuit breaker state changes
  - Exponential backoff behavior
  - Critical failure detection and alerting

  Integrates with telemetry and audit logs to provide a complete
  picture of OAuth system health.
  """

  use GenServer
  require Logger

  # 30 seconds
  @check_interval 30_000
  @alert_threshold_failures 3

  defmodule State do
    @moduledoc false
    defstruct [
      :monitors,
      :alerts,
      :check_timer
    ]
  end

  defmodule ServiceMonitor do
    @moduledoc false
    defstruct [
      :service_name,
      :last_refresh_attempt,
      :last_refresh_success,
      :consecutive_failures,
      :retry_count,
      :circuit_breaker_state,
      :token_expires_at,
      :alert_sent
    ]
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a token refresh attempt.
  """
  def record_refresh_attempt(service_name) do
    GenServer.cast(__MODULE__, {:refresh_attempt, service_name})

    # Emit telemetry
    :telemetry.execute(
      [:server, :oauth, :monitor, :refresh_attempt],
      %{count: 1},
      %{service: service_name}
    )
  end

  @doc """
  Records a successful token refresh.
  """
  def record_refresh_success(service_name, expires_at) do
    GenServer.cast(__MODULE__, {:refresh_success, service_name, expires_at})

    # Emit telemetry
    :telemetry.execute(
      [:server, :oauth, :monitor, :refresh_success],
      %{count: 1},
      %{service: service_name}
    )
  end

  @doc """
  Records a failed token refresh.
  """
  def record_refresh_failure(service_name, reason) do
    GenServer.cast(__MODULE__, {:refresh_failure, service_name, reason})

    # Emit telemetry
    :telemetry.execute(
      [:server, :oauth, :monitor, :refresh_failure],
      %{count: 1},
      %{service: service_name, reason: inspect(reason)}
    )
  end

  @doc """
  Records circuit breaker state change.
  """
  def record_circuit_breaker_change(service_name, old_state, new_state) do
    GenServer.cast(__MODULE__, {:circuit_breaker_change, service_name, old_state, new_state})

    # Emit telemetry
    :telemetry.execute(
      [:server, :oauth, :monitor, :circuit_breaker],
      %{count: 1},
      %{
        service: service_name,
        old_state: old_state,
        new_state: new_state
      }
    )
  end

  @doc """
  Records retry count for exponential backoff tracking.
  """
  def record_retry_count(service_name, retry_count) do
    GenServer.cast(__MODULE__, {:retry_count, service_name, retry_count})

    # Emit telemetry
    :telemetry.execute(
      [:server, :oauth, :monitor, :retry_count],
      %{value: retry_count},
      %{service: service_name}
    )
  end

  @doc """
  Gets current health status for all monitored services.
  """
  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end

  @doc """
  Gets detailed metrics for a specific service.
  """
  def get_service_metrics(service_name) do
    GenServer.call(__MODULE__, {:get_service_metrics, service_name})
  end

  # Server Callbacks

  @impl GenServer
  def init(_opts) do
    Logger.info("OAuth Monitor starting")

    # Schedule first health check
    timer = Process.send_after(self(), :check_health, @check_interval)

    # Attach telemetry handlers
    attach_telemetry_handlers()

    state = %State{
      monitors: %{},
      alerts: %{},
      check_timer: timer
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:refresh_attempt, service_name}, state) do
    monitor = get_or_create_monitor(state, service_name)
    updated_monitor = %{monitor | last_refresh_attempt: DateTime.utc_now()}

    new_monitors = Map.put(state.monitors, service_name, updated_monitor)
    {:noreply, %{state | monitors: new_monitors}}
  end

  @impl GenServer
  def handle_cast({:refresh_success, service_name, expires_at}, state) do
    monitor = get_or_create_monitor(state, service_name)

    updated_monitor = %{
      monitor
      | last_refresh_success: DateTime.utc_now(),
        consecutive_failures: 0,
        retry_count: 0,
        token_expires_at: expires_at,
        alert_sent: false
    }

    new_monitors = Map.put(state.monitors, service_name, updated_monitor)

    # Clear any active alerts for this service
    new_alerts = Map.delete(state.alerts, service_name)

    {:noreply, %{state | monitors: new_monitors, alerts: new_alerts}}
  end

  @impl GenServer
  def handle_cast({:refresh_failure, service_name, reason}, state) do
    monitor = get_or_create_monitor(state, service_name)
    updated_monitor = %{monitor | consecutive_failures: monitor.consecutive_failures + 1}

    new_monitors = Map.put(state.monitors, service_name, updated_monitor)
    new_state = %{state | monitors: new_monitors}

    # Check if we need to send an alert
    new_state = maybe_send_alert(new_state, service_name, reason)

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast({:circuit_breaker_change, service_name, _old_state, new_state}, state) do
    monitor = get_or_create_monitor(state, service_name)
    updated_monitor = %{monitor | circuit_breaker_state: new_state}

    new_monitors = Map.put(state.monitors, service_name, updated_monitor)

    # Alert if circuit breaker opened
    new_state =
      if new_state == :open do
        send_circuit_breaker_alert(state, service_name)
      else
        state
      end

    {:noreply, %{new_state | monitors: new_monitors}}
  end

  @impl GenServer
  def handle_cast({:retry_count, service_name, retry_count}, state) do
    monitor = get_or_create_monitor(state, service_name)
    updated_monitor = %{monitor | retry_count: retry_count}

    new_monitors = Map.put(state.monitors, service_name, updated_monitor)
    {:noreply, %{state | monitors: new_monitors}}
  end

  @impl GenServer
  def handle_call(:get_health_status, _from, state) do
    health_status =
      Enum.map(state.monitors, fn {service_name, monitor} ->
        status = determine_health_status(monitor)

        {service_name,
         %{
           status: status,
           consecutive_failures: monitor.consecutive_failures,
           retry_count: monitor.retry_count,
           circuit_breaker: monitor.circuit_breaker_state,
           token_expires_at: monitor.token_expires_at,
           last_success: monitor.last_refresh_success,
           alert_active: Map.has_key?(state.alerts, service_name)
         }}
      end)
      |> Map.new()

    {:reply, {:ok, health_status}, state}
  end

  @impl GenServer
  def handle_call({:get_service_metrics, service_name}, _from, state) do
    case Map.get(state.monitors, service_name) do
      nil ->
        {:reply, {:error, :service_not_monitored}, state}

      monitor ->
        metrics = %{
          last_refresh_attempt: monitor.last_refresh_attempt,
          last_refresh_success: monitor.last_refresh_success,
          consecutive_failures: monitor.consecutive_failures,
          retry_count: monitor.retry_count,
          circuit_breaker_state: monitor.circuit_breaker_state,
          token_expires_at: monitor.token_expires_at,
          health_status: determine_health_status(monitor),
          time_until_expiry: calculate_time_until_expiry(monitor.token_expires_at),
          backoff_delay: calculate_backoff_delay(monitor.retry_count)
        }

        {:reply, {:ok, metrics}, state}
    end
  end

  @impl GenServer
  def handle_info(:check_health, state) do
    # Check each monitored service
    new_state =
      Enum.reduce(state.monitors, state, fn {service_name, monitor}, acc_state ->
        check_service_health(acc_state, service_name, monitor)
      end)

    # Emit overall health metrics
    emit_health_metrics(new_state)

    # Schedule next check
    timer = Process.send_after(self(), :check_health, @check_interval)

    {:noreply, %{new_state | check_timer: timer}}
  end

  # Private Functions

  defp get_or_create_monitor(state, service_name) do
    Map.get(state.monitors, service_name, %ServiceMonitor{
      service_name: service_name,
      consecutive_failures: 0,
      retry_count: 0,
      circuit_breaker_state: :closed,
      alert_sent: false
    })
  end

  defp determine_health_status(monitor) do
    cond do
      monitor.circuit_breaker_state == :open ->
        :critical

      monitor.consecutive_failures >= @alert_threshold_failures ->
        :unhealthy

      monitor.retry_count > 0 or monitor.consecutive_failures > 0 ->
        :degraded

      token_expiring_soon?(monitor.token_expires_at) ->
        :warning

      true ->
        :healthy
    end
  end

  defp token_expiring_soon?(nil), do: false

  defp token_expiring_soon?(expires_at) do
    case DateTime.diff(expires_at, DateTime.utc_now(), :minute) do
      minutes when minutes < 5 -> true
      _ -> false
    end
  end

  defp calculate_time_until_expiry(nil), do: nil

  defp calculate_time_until_expiry(expires_at) do
    DateTime.diff(expires_at, DateTime.utc_now(), :second)
  end

  defp calculate_backoff_delay(retry_count) do
    base_delay = 60_000
    max_delay = 3_600_000
    min(base_delay * :math.pow(2, retry_count), max_delay)
  end

  defp maybe_send_alert(state, service_name, reason) do
    monitor = Map.get(state.monitors, service_name)

    if monitor.consecutive_failures >= @alert_threshold_failures and not monitor.alert_sent do
      send_failure_alert(state, service_name, reason, monitor)
    else
      state
    end
  end

  defp send_failure_alert(state, service_name, reason, monitor) do
    Logger.error("""
    [OAUTH_ALERT] Critical: Token refresh failures for #{service_name}
    Consecutive failures: #{monitor.consecutive_failures}
    Last success: #{monitor.last_refresh_success || "never"}
    Reason: #{inspect(reason)}
    Action required: Check OAuth credentials and service availability
    """)

    # Record alert
    alert = %{
      timestamp: DateTime.utc_now(),
      type: :refresh_failures,
      consecutive_failures: monitor.consecutive_failures,
      reason: reason
    }

    new_alerts = Map.put(state.alerts, service_name, alert)

    # Mark alert as sent
    updated_monitor = %{monitor | alert_sent: true}
    new_monitors = Map.put(state.monitors, service_name, updated_monitor)

    # Emit critical telemetry event
    :telemetry.execute(
      [:server, :oauth, :monitor, :alert],
      %{count: 1},
      %{
        service: service_name,
        type: :refresh_failures,
        consecutive_failures: monitor.consecutive_failures
      }
    )

    %{state | monitors: new_monitors, alerts: new_alerts}
  end

  defp send_circuit_breaker_alert(state, service_name) do
    Logger.error("""
    [OAUTH_ALERT] Circuit breaker opened for #{service_name}
    Service is being protected from cascading failures
    Will attempt recovery in half-open state after cooldown period
    """)

    # Record alert
    alert = %{
      timestamp: DateTime.utc_now(),
      type: :circuit_breaker_open
    }

    new_alerts = Map.put(state.alerts, service_name, alert)

    # Emit critical telemetry event
    :telemetry.execute(
      [:server, :oauth, :monitor, :alert],
      %{count: 1},
      %{
        service: service_name,
        type: :circuit_breaker_open
      }
    )

    %{state | alerts: new_alerts}
  end

  defp check_service_health(state, service_name, monitor) do
    # Check if token is about to expire
    if monitor.token_expires_at do
      minutes_until_expiry = DateTime.diff(monitor.token_expires_at, DateTime.utc_now(), :minute)

      cond do
        minutes_until_expiry < 0 ->
          Logger.warning("[OAuth Monitor] Token expired for #{service_name}")
          send_expiry_alert(state, service_name, :expired)

        minutes_until_expiry < 5 ->
          Logger.warning("[OAuth Monitor] Token expiring soon for #{service_name} (#{minutes_until_expiry} minutes)")
          send_expiry_alert(state, service_name, :expiring_soon)

        true ->
          state
      end
    else
      state
    end
  end

  defp send_expiry_alert(state, service_name, expiry_type) do
    Logger.warning("""
    [OAUTH_ALERT] Token #{expiry_type} for #{service_name}
    Auto-refresh should handle this, but manual intervention may be needed
    if refresh continues to fail.
    """)

    # Emit telemetry
    :telemetry.execute(
      [:server, :oauth, :monitor, :token_expiry],
      %{count: 1},
      %{
        service: service_name,
        type: expiry_type
      }
    )

    state
  end

  defp emit_health_metrics(state) do
    # Count services by health status
    status_counts =
      Enum.reduce(state.monitors, %{}, fn {_service, monitor}, acc ->
        status = determine_health_status(monitor)
        Map.update(acc, status, 1, &(&1 + 1))
      end)

    # Emit metrics for each status
    Enum.each([:healthy, :warning, :degraded, :unhealthy, :critical], fn status ->
      count = Map.get(status_counts, status, 0)

      :telemetry.execute(
        [:server, :oauth, :monitor, :health],
        %{count: count},
        %{status: status}
      )
    end)

    # Emit total retry count across all services
    total_retries =
      Enum.reduce(state.monitors, 0, fn {_service, monitor}, acc ->
        acc + monitor.retry_count
      end)

    :telemetry.execute(
      [:server, :oauth, :monitor, :total_retries],
      %{value: total_retries},
      %{}
    )
  end

  defp attach_telemetry_handlers do
    # Attach to circuit breaker events
    :telemetry.attach(
      "oauth-monitor-circuit-breaker",
      [:server, :circuit_breaker, :state_change],
      &handle_circuit_breaker_telemetry/4,
      nil
    )

    Logger.info("OAuth Monitor telemetry handlers attached")
  end

  defp handle_circuit_breaker_telemetry(_event_name, _measurements, metadata, _config) do
    # Forward circuit breaker changes to monitor
    if String.contains?(to_string(metadata.service), "oauth") do
      record_circuit_breaker_change(
        metadata.service,
        metadata.old_state,
        metadata.new_state
      )
    end
  end
end

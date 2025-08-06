defmodule Server.Health.HealthMonitorServer do
  @moduledoc """
  GenServer that monitors system health and broadcasts status changes.

  Periodically checks system health using SystemHealth.determine_system_status/0
  and broadcasts changes via Phoenix PubSub to prevent "silent failures".

  Features:
  - Non-blocking health checks using Task.async
  - Broadcasts only on status changes to reduce network chatter
  - Graceful handling of check failures with automatic retry
  - Supervision tree integration for reliability
  """

  use GenServer
  require Logger

  alias Server.Health.SystemHealth

  # 30 seconds - configurable
  @check_interval_ms 30_000
  @health_pubsub_topic "system:health"

  # Client API

  @doc """
  Starts the HealthMonitorServer under supervision.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current system health status.
  Returns nil if no check has completed yet.
  """
  @spec get_current_status() :: String.t() | nil
  def get_current_status do
    GenServer.call(__MODULE__, :get_current_status)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    # Perform an initial check on startup, then schedule the next one.
    # The initial state is `nil` to guarantee the first check broadcasts.
    Logger.info("Starting HealthMonitorServer with #{@check_interval_ms}ms interval")

    state = %{last_status: nil, check_task_ref: nil}
    send(self(), :check_health)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_current_status, _from, %{last_status: status} = state) do
    {:reply, status, state}
  end

  @impl true
  def handle_info(:check_health, state) do
    # Run the check in a separate, monitored task to prevent blocking
    Logger.debug("Starting health check")

    task =
      Task.async(fn ->
        SystemHealth.determine_system_status()
      end)

    new_state = %{state | check_task_ref: task.ref}
    {:noreply, new_state}
  end

  @impl true
  def handle_info({ref, new_status}, %{check_task_ref: ref, last_status: old_status} = state) do
    # Task finished successfully, process the result
    Process.demonitor(ref, [:flush])

    Logger.debug("Health check completed", status: new_status)

    # Schedule the next check
    Process.send_after(self(), :check_health, @check_interval_ms)

    # Only broadcast if the status has changed
    if new_status != old_status do
      Logger.info("System health status changed", from: old_status, to: new_status)

      ServerWeb.Endpoint.broadcast!(@health_pubsub_topic, "health_update", %{
        status: new_status,
        timestamp: System.system_time(:second)
      })
    end

    {:noreply, %{state | last_status: new_status, check_task_ref: nil}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{check_task_ref: ref} = state) do
    # The health check task crashed or timed out
    Logger.warning("Health check task failed", reason: reason)

    # Schedule the next check and continue
    Process.send_after(self(), :check_health, @check_interval_ms)

    {:noreply, %{state | check_task_ref: nil}}
  end

  # Catch-all for unexpected messages
  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unexpected message in HealthMonitorServer", message: inspect(msg))
    {:noreply, state}
  end

  # Helper to get the health topic name (useful for tests)
  @doc false
  def health_topic, do: @health_pubsub_topic
end

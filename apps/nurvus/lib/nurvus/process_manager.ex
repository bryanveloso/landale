defmodule Nurvus.ProcessManager do
  @moduledoc """
  Main GenServer that manages process definitions and coordinates with the dynamic supervisor.

  This module handles:
  - Loading and storing process configurations
  - Starting and stopping processes
  - Querying process status
  - Handling process lifecycle events
  """

  use GenServer
  require Logger

  alias Nurvus.ProcessSupervisor

  @type process_config :: %{
          id: String.t(),
          name: String.t(),
          command: String.t(),
          args: [String.t()],
          cwd: String.t() | nil,
          env: %{String.t() => String.t()},
          auto_restart: boolean(),
          max_restarts: non_neg_integer(),
          restart_window: non_neg_integer()
        }

  @type process_status :: :running | :stopped | :failed | :unknown

  defstruct processes: %{}, monitors: %{}

  ## Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec add_process(process_config()) :: :ok | {:error, term()}
  def add_process(config) do
    GenServer.call(__MODULE__, {:add_process, config})
  end

  @spec remove_process(String.t()) :: :ok | {:error, :not_found}
  def remove_process(process_id) do
    GenServer.call(__MODULE__, {:remove_process, process_id})
  end

  @spec start_process(String.t()) :: :ok | {:error, term()}
  def start_process(process_id) do
    GenServer.call(__MODULE__, {:start_process, process_id})
  end

  @spec stop_process(String.t()) :: :ok | {:error, term()}
  def stop_process(process_id) do
    GenServer.call(__MODULE__, {:stop_process, process_id})
  end

  @spec restart_process(String.t()) :: :ok | {:error, term()}
  def restart_process(process_id) do
    GenServer.call(__MODULE__, {:restart_process, process_id})
  end

  @spec get_process_status(String.t()) :: {:ok, process_status()} | {:error, :not_found}
  def get_process_status(process_id) do
    GenServer.call(__MODULE__, {:get_process_status, process_id})
  end

  @spec list_processes() :: [%{id: String.t(), name: String.t(), status: process_status()}]
  def list_processes do
    GenServer.call(__MODULE__, :list_processes)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    config_path = Keyword.get(opts, :config_path)

    state = %__MODULE__{
      processes: %{},
      monitors: %{}
    }

    # Load initial process configurations
    case Nurvus.Config.load_config(config_path) do
      {:ok, processes} ->
        loaded_processes =
          processes
          |> Enum.map(fn config -> {config.id, config} end)
          |> Enum.into(%{})

        updated_state = %{state | processes: loaded_processes}
        Logger.info("Loaded #{map_size(loaded_processes)} process configurations")
        {:ok, updated_state}

      {:error, reason} ->
        Logger.error("Failed to load process configurations: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_call({:add_process, config}, _from, state) do
    case Nurvus.Config.validate_process_config(config) do
      {:ok, validated_config} ->
        process_id = validated_config.id
        updated_processes = Map.put(state.processes, process_id, validated_config)
        new_state = %{state | processes: updated_processes}

        Logger.info("Added process configuration: #{process_id}")
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:remove_process, process_id}, _from, state) do
    case Map.has_key?(state.processes, process_id) do
      true ->
        # Stop the process if it's running
        _result = stop_process_internal(process_id, state)

        updated_processes = Map.delete(state.processes, process_id)
        updated_monitors = Map.delete(state.monitors, process_id)
        new_state = %{state | processes: updated_processes, monitors: updated_monitors}

        Logger.info("Removed process: #{process_id}")
        {:reply, :ok, new_state}

      false ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:start_process, process_id}, _from, state) do
    case Map.get(state.processes, process_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      config ->
        case ProcessSupervisor.start_process(config) do
          {:ok, pid} ->
            Logger.info("Process start initiated: #{process_id} -> #{config.name}")

            Logger.debug(
              "Process start config: #{inspect(%{command: config.command, args: config.args, cwd: config.cwd, env: config.env})}"
            )

            # Emit telemetry event for process start
            :telemetry.execute(
              [:nurvus, :process, :started],
              %{count: 1},
              %{process_id: process_id, process_name: config.name}
            )

            monitor_ref = Process.monitor(pid)
            updated_monitors = Map.put(state.monitors, process_id, {pid, monitor_ref})
            new_state = %{state | monitors: updated_monitors}

            Logger.info("Started process: #{process_id} (#{inspect(pid)}) - monitoring active")
            Logger.debug("Current monitors: #{inspect(Map.keys(updated_monitors))}")
            {:reply, :ok, new_state}

          {:error, reason} ->
            Logger.error("Failed to start process #{process_id}: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:stop_process, process_id}, _from, state) do
    result = stop_process_internal(process_id, state)

    case result do
      :ok ->
        # Emit telemetry event for process stop
        :telemetry.execute(
          [:nurvus, :process, :stopped],
          %{count: 1},
          %{process_id: process_id}
        )

        updated_monitors = Map.delete(state.monitors, process_id)
        new_state = %{state | monitors: updated_monitors}
        {:reply, :ok, new_state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:restart_process, process_id}, _from, state) do
    Logger.info("Process restart initiated: #{process_id}")
    Logger.debug("Restart sequence starting for: #{process_id}")

    # Stop then start
    case stop_process_internal(process_id, state) do
      :ok ->
        Logger.debug("Stop phase completed for restart: #{process_id}")
        # Remove from monitors temporarily
        updated_monitors = Map.delete(state.monitors, process_id)
        temp_state = %{state | monitors: updated_monitors}
        Logger.debug("Monitors cleared for restart: #{process_id}")

        # Start again
        Logger.debug("Start phase beginning for restart: #{process_id}")

        case handle_call({:start_process, process_id}, nil, temp_state) do
          {:reply, :ok, new_state} ->
            Logger.info("Successfully restarted process: #{process_id}")
            Logger.debug("Restart sequence completed: #{process_id}")

            # Emit telemetry event for process restart
            :telemetry.execute(
              [:nurvus, :process, :restarted],
              %{count: 1},
              %{process_id: process_id}
            )

            {:reply, :ok, new_state}

          {:reply, error, _} ->
            Logger.error("Restart failed during start phase for #{process_id}: #{inspect(error)}")
            {:reply, error, temp_state}
        end

      error ->
        Logger.error("Restart failed during stop phase for #{process_id}: #{inspect(error)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_process_status, process_id}, _from, state) do
    case Map.get(state.monitors, process_id) do
      nil ->
        # Check if process config exists but not running
        if Map.has_key?(state.processes, process_id) do
          {:reply, {:ok, :stopped}, state}
        else
          {:reply, {:error, :not_found}, state}
        end

      {pid, _monitor_ref} ->
        status = if Process.alive?(pid), do: :running, else: :failed
        {:reply, {:ok, status}, state}
    end
  end

  @impl true
  def handle_call(:list_processes, _from, state) do
    processes =
      state.processes
      |> Enum.map(fn {id, config} ->
        {_reply, status, _state} = handle_call({:get_process_status, id}, nil, state)

        status =
          case status do
            {:ok, s} -> s
            _ -> :unknown
          end

        %{id: id, name: config.name, status: status}
      end)

    {:reply, processes, state}
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, reason}, state) do
    Logger.debug("Received DOWN message: #{inspect(monitor_ref)} reason: #{inspect(reason)}")

    # Find which process died
    case find_process_by_monitor(state.monitors, monitor_ref) do
      {process_id, pid} ->
        Logger.warning("Process #{process_id} (#{inspect(pid)}) exited: #{inspect(reason)}")

        Logger.debug(
          "Process exit details - ID: #{process_id}, PID: #{inspect(pid)}, Monitor: #{inspect(monitor_ref)}"
        )

        # Emit telemetry event for process crash
        :telemetry.execute(
          [:nurvus, :process, :crashed],
          %{count: 1},
          %{process_id: process_id, reason: inspect(reason)}
        )

        # Remove from monitors
        updated_monitors = Map.delete(state.monitors, process_id)
        new_state = %{state | monitors: updated_monitors}

        Logger.debug(
          "Removed #{process_id} from monitors. Remaining: #{inspect(Map.keys(updated_monitors))}"
        )

        # Check if auto-restart is enabled
        case Map.get(state.processes, process_id) do
          %{auto_restart: true} = config ->
            Logger.info("Auto-restart enabled for #{process_id} - scheduling restart in 1000ms")

            Logger.debug(
              "Auto-restart config: #{inspect(%{max_restarts: config.max_restarts, restart_window: config.restart_window})}"
            )

            # Emit telemetry event for auto-restart
            :telemetry.execute(
              [:nurvus, :process, :auto_restart_scheduled],
              %{count: 1},
              %{process_id: process_id}
            )

            # Schedule restart after a delay
            Process.send_after(self(), {:restart_process, process_id}, 1000)
            {:noreply, new_state}

          config when not is_nil(config) ->
            Logger.debug("Auto-restart disabled for #{process_id} - process will remain stopped")
            {:noreply, new_state}

          nil ->
            Logger.debug("No configuration found for #{process_id} - removing from management")
            {:noreply, new_state}
        end

      nil ->
        Logger.warning("Received DOWN message for unknown monitor: #{inspect(monitor_ref)}")
        Logger.debug("Known monitors: #{inspect(Map.keys(state.monitors))}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:restart_process, process_id}, state) do
    Logger.info("Executing scheduled auto-restart for: #{process_id}")
    Logger.debug("Auto-restart triggered - attempting start for: #{process_id}")

    case handle_call({:start_process, process_id}, nil, state) do
      {:reply, :ok, new_state} ->
        Logger.info("Auto-restart successful for: #{process_id}")
        Logger.debug("Process #{process_id} back online via auto-restart")
        {:noreply, new_state}

      {:reply, {:error, reason}, _} ->
        Logger.error("Auto-restart failed for #{process_id}: #{inspect(reason)}")
        Logger.debug("Auto-restart failure details: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  ## Private Functions

  defp stop_process_internal(process_id, state) do
    case Map.get(state.monitors, process_id) do
      nil ->
        Logger.warning("Process stop requested but not monitored: #{process_id}")
        {:error, :not_running}

      {pid, monitor_ref} ->
        Logger.info("Process stop initiated: #{process_id} (#{inspect(pid)})")
        Logger.debug("Demonitoring process: #{process_id} with ref #{inspect(monitor_ref)}")
        Process.demonitor(monitor_ref, [:flush])

        # Signal the ProcessRunner to initiate graceful shutdown
        Logger.debug("Requesting graceful shutdown for process: #{process_id}")

        try do
          # Send TERM signal to allow graceful shutdown before supervisor termination
          GenServer.cast(pid, :graceful_shutdown)

          # Wait briefly for graceful shutdown to complete
          Process.sleep(100)
        catch
          :exit, _reason ->
            Logger.debug("ProcessRunner #{inspect(pid)} already terminated")
        end

        # Now stop via supervisor
        Logger.debug("Requesting supervisor stop for process: #{process_id}")
        result = ProcessSupervisor.stop_process(pid)
        Logger.debug("Supervisor stop result: #{inspect(result)}")

        # Verify the process actually stopped
        Logger.debug("Verifying process termination: #{process_id}")

        case verify_process_stopped(pid, process_id) do
          :ok ->
            Logger.info("Successfully stopped process: #{process_id}")
            Logger.debug("Process #{process_id} verified as terminated")
            :ok

          {:error, reason} ->
            Logger.error("Failed to stop process #{process_id}: #{reason}")
            {:error, reason}
        end
    end
  end

  defp verify_process_stopped(pid, process_id, timeout_ms \\ 10_000) do
    start_time = System.monotonic_time(:millisecond)
    # Check every 100ms
    check_interval = 100

    verify_process_stopped_loop(pid, process_id, start_time, timeout_ms, check_interval)
  end

  defp verify_process_stopped_loop(pid, process_id, start_time, timeout_ms, check_interval) do
    current_time = System.monotonic_time(:millisecond)
    elapsed = current_time - start_time

    if elapsed >= timeout_ms do
      {:error, "Process #{process_id} did not stop within timeout"}
    else
      if Process.alive?(pid) do
        # Process still alive, wait and check again
        Process.sleep(check_interval)
        verify_process_stopped_loop(pid, process_id, start_time, timeout_ms, check_interval)
      else
        # Process has stopped
        :ok
      end
    end
  end

  defp find_process_by_monitor(monitors, target_ref) do
    Enum.find_value(monitors, fn {id, {pid, ref}} ->
      if ref == target_ref, do: {id, pid}, else: nil
    end)
  end
end

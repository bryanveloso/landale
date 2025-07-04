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
        :ok = stop_process_internal(process_id, state)

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
            # Emit telemetry event for process start
            :telemetry.execute(
              [:nurvus, :process, :started],
              %{count: 1},
              %{process_id: process_id, process_name: config.name}
            )

            monitor_ref = Process.monitor(pid)
            updated_monitors = Map.put(state.monitors, process_id, {pid, monitor_ref})
            new_state = %{state | monitors: updated_monitors}

            Logger.info("Started process: #{process_id} (#{inspect(pid)})")
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
    # Stop then start
    case stop_process_internal(process_id, state) do
      :ok ->
        # Remove from monitors temporarily
        updated_monitors = Map.delete(state.monitors, process_id)
        temp_state = %{state | monitors: updated_monitors}

        # Start again
        case handle_call({:start_process, process_id}, nil, temp_state) do
          {:reply, :ok, new_state} ->
            # Emit telemetry event for process restart
            :telemetry.execute(
              [:nurvus, :process, :restarted],
              %{count: 1},
              %{process_id: process_id}
            )

            {:reply, :ok, new_state}

          {:reply, error, _} ->
            {:reply, error, temp_state}
        end

      error ->
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
    # Find which process died
    case find_process_by_monitor(state.monitors, monitor_ref) do
      {process_id, _pid} ->
        # Emit telemetry event for process crash
        :telemetry.execute(
          [:nurvus, :process, :crashed],
          %{count: 1},
          %{process_id: process_id, reason: inspect(reason)}
        )

        Logger.warning("Process #{process_id} exited: #{inspect(reason)}")

        # Remove from monitors
        updated_monitors = Map.delete(state.monitors, process_id)
        new_state = %{state | monitors: updated_monitors}

        # Check if auto-restart is enabled
        case Map.get(state.processes, process_id) do
          %{auto_restart: true} = _config ->
            # Emit telemetry event for auto-restart
            :telemetry.execute(
              [:nurvus, :process, :auto_restart_scheduled],
              %{count: 1},
              %{process_id: process_id}
            )

            Logger.info("Auto-restarting process: #{process_id}")
            # Schedule restart after a delay
            Process.send_after(self(), {:restart_process, process_id}, 1000)
            {:noreply, new_state}

          _ ->
            {:noreply, new_state}
        end

      nil ->
        Logger.warning("Received DOWN message for unknown process: #{inspect(monitor_ref)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:restart_process, process_id}, state) do
    case handle_call({:start_process, process_id}, nil, state) do
      {:reply, :ok, new_state} ->
        {:noreply, new_state}

      {:reply, {:error, reason}, _} ->
        Logger.error("Failed to auto-restart process #{process_id}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  ## Private Functions

  defp stop_process_internal(process_id, state) do
    case Map.get(state.monitors, process_id) do
      nil ->
        {:error, :not_running}

      {pid, monitor_ref} ->
        Process.demonitor(monitor_ref, [:flush])
        ProcessSupervisor.stop_process(pid)
        Logger.info("Stopped process: #{process_id}")
        :ok
    end
  end

  defp find_process_by_monitor(monitors, target_ref) do
    Enum.find_value(monitors, fn {id, {pid, ref}} ->
      if ref == target_ref, do: {id, pid}, else: nil
    end)
  end
end

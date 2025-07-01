defmodule Server.Services.ProcessSupervisor do
  @moduledoc """
  Distributed process supervision service for the Landale cluster.

  This GenServer coordinates process management across all nodes in the cluster,
  providing a unified interface for starting, stopping, and monitoring processes
  on any machine in the distributed system.

  ## Architecture

  - Each node runs a ProcessSupervisor instance
  - Platform-specific implementations handle OS-level process management
  - Cluster communication enables remote process control
  - Real-time status updates via Phoenix PubSub

  ## Usage

      # Start OBS on the demi node
      ProcessSupervisor.start_process("demi", "obs")
      
      # Get status of all processes across cluster
      ProcessSupervisor.cluster_status()
      
      # Monitor process events in real-time
      Phoenix.PubSub.subscribe(Server.PubSub, "process_events")
  """

  use GenServer
  require Logger

  alias Server.ProcessSupervisorBehaviour

  @type node_name :: String.t()
  @type process_name :: String.t()
  @type process_action :: :start | :stop | :restart

  defmodule State do
    @moduledoc false
    defstruct [
      :platform_supervisor,
      :node_name,
      :managed_processes,
      :process_states,
      :monitoring_interval
    ]

    @type t :: %__MODULE__{
            platform_supervisor: module(),
            node_name: String.t(),
            managed_processes: [String.t()],
            process_states: %{String.t() => ProcessSupervisorBehaviour.process_info()},
            monitoring_interval: integer()
          }
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start a process on a specific node in the cluster.

  If the node is the current node, handles the request locally.
  Otherwise, makes a cluster call to the target node.
  """
  @spec start_process(node_name(), process_name()) :: :ok | {:error, term()}
  def start_process(node_name, process_name) do
    if node_name == get_node_name() do
      GenServer.call(__MODULE__, {:start_process, process_name})
    else
      cluster_call(node_name, {:start_process, process_name})
    end
  end

  @doc """
  Stop a process on a specific node in the cluster.
  """
  @spec stop_process(node_name(), process_name()) :: :ok | {:error, term()}
  def stop_process(node_name, process_name) do
    if node_name == get_node_name() do
      GenServer.call(__MODULE__, {:stop_process, process_name})
    else
      cluster_call(node_name, {:stop_process, process_name})
    end
  end

  @doc """
  Restart a process on a specific node in the cluster.
  """
  @spec restart_process(node_name(), process_name()) :: :ok | {:error, term()}
  def restart_process(node_name, process_name) do
    if node_name == get_node_name() do
      GenServer.call(__MODULE__, {:restart_process, process_name})
    else
      cluster_call(node_name, {:restart_process, process_name})
    end
  end

  @doc """
  Get process information for a specific process on a node.
  """
  @spec get_process_info(node_name(), process_name()) ::
          {:ok, ProcessSupervisorBehaviour.process_info()} | {:error, term()}
  def get_process_info(node_name, process_name) do
    if node_name == get_node_name() do
      GenServer.call(__MODULE__, {:get_process_info, process_name})
    else
      cluster_call(node_name, {:get_process_info, process_name})
    end
  end

  @doc """
  List all processes managed by a specific node.
  """
  @spec list_processes(node_name()) :: {:ok, [ProcessSupervisorBehaviour.process_info()]} | {:error, term()}
  def list_processes(node_name) do
    if node_name == get_node_name() do
      GenServer.call(__MODULE__, :list_processes)
    else
      cluster_call(node_name, :list_processes)
    end
  end

  @doc """
  Get the status of all processes across the entire cluster.

  Returns a map where keys are node names and values are process lists.
  """
  @spec cluster_status() :: %{node_name() => [ProcessSupervisorBehaviour.process_info()]}
  def cluster_status do
    nodes = get_cluster_nodes()

    Enum.reduce(nodes, %{}, fn node_name, acc ->
      case list_processes(node_name) do
        {:ok, processes} -> Map.put(acc, node_name, processes)
        {:error, _} -> Map.put(acc, node_name, [])
      end
    end)
  end

  @doc """
  Get the list of all active nodes in the cluster.
  """
  @spec get_cluster_nodes() :: [node_name()]
  def get_cluster_nodes do
    [Node.self() | Node.list()]
    |> Enum.map(&node_to_name/1)
    |> Enum.sort()
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    # Determine platform and load appropriate supervisor
    platform_supervisor = determine_platform_supervisor()
    node_name = get_node_name()
    monitoring_interval = Keyword.get(opts, :monitoring_interval, 5_000)

    # Initialize the platform supervisor
    case platform_supervisor.init() do
      :ok ->
        managed_processes = platform_supervisor.managed_processes()

        state = %State{
          platform_supervisor: platform_supervisor,
          node_name: node_name,
          managed_processes: managed_processes,
          process_states: %{},
          monitoring_interval: monitoring_interval
        }

        Logger.info("ProcessSupervisor initialized",
          node: node_name,
          platform: platform_supervisor,
          managed_processes: managed_processes
        )

        # Schedule initial process monitoring
        schedule_monitoring(monitoring_interval)

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to initialize platform supervisor",
          platform: platform_supervisor,
          error: reason
        )

        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:start_process, process_name}, _from, state) do
    case state.platform_supervisor.start_process(process_name) do
      :ok ->
        Logger.info("Process started", node: state.node_name, process: process_name)
        broadcast_process_event(:process_started, state.node_name, process_name)
        {:reply, :ok, state}

      {:error, reason} = error ->
        Logger.error("Failed to start process",
          node: state.node_name,
          process: process_name,
          error: reason
        )

        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:stop_process, process_name}, _from, state) do
    case state.platform_supervisor.stop_process(process_name) do
      :ok ->
        Logger.info("Process stopped", node: state.node_name, process: process_name)
        broadcast_process_event(:process_stopped, state.node_name, process_name)
        {:reply, :ok, state}

      {:error, reason} = error ->
        Logger.error("Failed to stop process",
          node: state.node_name,
          process: process_name,
          error: reason
        )

        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:restart_process, process_name}, _from, state) do
    case state.platform_supervisor.restart_process(process_name) do
      :ok ->
        Logger.info("Process restarted", node: state.node_name, process: process_name)
        broadcast_process_event(:process_restarted, state.node_name, process_name)
        {:reply, :ok, state}

      {:error, reason} = error ->
        Logger.error("Failed to restart process",
          node: state.node_name,
          process: process_name,
          error: reason
        )

        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_process_info, process_name}, _from, state) do
    case state.platform_supervisor.get_process(process_name) do
      {:ok, process_info} ->
        {:reply, {:ok, process_info}, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:list_processes, _from, state) do
    case state.platform_supervisor.list_processes() do
      {:ok, processes} ->
        {:reply, {:ok, processes}, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_info(:monitor_processes, state) do
    case state.platform_supervisor.list_processes() do
      {:ok, processes} ->
        # Check for status changes
        old_states = state.process_states
        new_states = Map.new(processes, fn proc -> {proc.name, proc} end)

        # Detect and broadcast status changes
        Enum.each(new_states, fn {name, new_proc} ->
          case Map.get(old_states, name) do
            nil ->
              # New process detected
              broadcast_process_event(:process_detected, state.node_name, name, new_proc)

            old_proc when old_proc.status != new_proc.status ->
              # Status changed
              broadcast_process_event(:process_status_changed, state.node_name, name, new_proc)

            _ ->
              # No change
              :ok
          end
        end)

        # Schedule next monitoring cycle
        schedule_monitoring(state.monitoring_interval)

        {:noreply, %{state | process_states: new_states}}

      {:error, reason} ->
        Logger.warning("Process monitoring failed",
          node: state.node_name,
          error: reason
        )

        schedule_monitoring(state.monitoring_interval)
        {:noreply, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("ProcessSupervisor terminating",
      node: state.node_name,
      reason: reason
    )

    state.platform_supervisor.cleanup()
    :ok
  end

  # Private Functions

  defp determine_platform_supervisor do
    case :os.type() do
      {:win32, _} -> Server.ProcessSupervisor.Windows
      {:unix, :darwin} -> Server.ProcessSupervisor.MacOS
      {:unix, _} -> Server.ProcessSupervisor.Linux
    end
  end

  defp get_node_name do
    Node.self()
    |> Atom.to_string()
    |> String.split("@")
    |> List.last()
  end

  defp node_to_name(node_atom) do
    node_atom
    |> Atom.to_string()
    |> String.split("@")
    |> List.last()
  end

  defp cluster_call(node_name, message) do
    target_node = :"server@#{node_name}"

    try do
      GenServer.call({__MODULE__, target_node}, message, 30_000)
    catch
      :exit, {:noproc, _} ->
        {:error, :node_not_available}

      :exit, {:timeout, _} ->
        {:error, :timeout}

      :exit, reason ->
        {:error, reason}
    end
  end

  defp schedule_monitoring(interval) do
    Process.send_after(self(), :monitor_processes, interval)
  end

  defp broadcast_process_event(event_type, node_name, process_name, process_info \\ nil) do
    event_data = %{
      event: event_type,
      node: node_name,
      process: process_name,
      process_info: process_info,
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(Server.PubSub, "process_events", event_data)
  end
end

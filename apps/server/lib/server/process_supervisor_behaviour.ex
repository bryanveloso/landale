defmodule Server.ProcessSupervisorBehaviour do
  @moduledoc """
  Behaviour for platform-specific process supervision implementations.

  Each platform (Windows, macOS, Linux) implements this behaviour to provide
  native process management capabilities within the distributed Elixir cluster.
  """

  @type process_status :: :running | :stopped | :starting | :stopping | :crashed | :unknown

  @type process_info :: %{
          name: String.t(),
          display_name: String.t(),
          pid: integer() | nil,
          status: process_status(),
          cpu_percent: float(),
          memory_mb: float()
        }

  @type process_action_result :: :ok | {:error, term()}

  @doc """
  List all managed processes on this machine.

  Returns a list of process information for all processes that this
  supervisor is configured to manage.
  """
  @callback list_processes() :: {:ok, [process_info()]} | {:error, term()}

  @doc """
  Get detailed information about a specific process.

  Returns process information including current status, resource usage,
  and operational metrics.
  """
  @callback get_process(String.t()) :: {:ok, process_info()} | {:error, :not_found | term()}

  @doc """
  Start a managed process.

  Launches the specified process using platform-appropriate methods.
  Does not wait for the process to fully start - returns immediately
  after launching.
  """
  @callback start_process(String.t()) :: process_action_result()

  @doc """
  Stop a managed process gracefully.

  Attempts to stop the process gracefully first, then forcefully
  if necessary. Returns after the process has been terminated.
  """
  @callback stop_process(String.t()) :: process_action_result()

  @doc """
  Restart a managed process.

  Stops the process if running, then starts it again.
  Equivalent to stop_process/1 followed by start_process/1.
  """
  @callback restart_process(String.t()) :: process_action_result()

  @doc """
  Check if a process is currently running.

  Quick status check that returns true if the process is active,
  false otherwise. More efficient than get_process/1 for simple
  status checks.
  """
  @callback process_running?(String.t()) :: boolean()

  @doc """
  Get the list of process names this supervisor manages.

  Returns the configuration of which processes this supervisor
  is responsible for on this platform.
  """
  @callback managed_processes() :: [String.t()]

  @doc """
  Initialize the process supervisor.

  Called during startup to initialize any platform-specific
  resources or configurations needed for process management.
  """
  @callback init() :: :ok | {:error, term()}

  @doc """
  Clean up the process supervisor.

  Called during shutdown to clean up any resources or stop
  any background monitoring tasks.
  """
  @callback cleanup() :: :ok
end

defmodule Nurvus do
  @moduledoc """
  Nurvus - A lightweight process manager built with Elixir OTP.

  Nurvus provides process management capabilities similar to PM2 but designed
  specifically for Elixir applications with proper OTP supervision.

  ## Features

  - Process lifecycle management (start, stop, restart)
  - Health monitoring and metrics collection
  - Auto-restart capabilities
  - Configuration-based process definitions
  - Lightweight HTTP API for control
  - Real-time status monitoring

  ## Usage

      # Add a process
      Nurvus.add_process(%{
        id: "my_app",
        name: "My Application", 
        command: "bun",
        args: ["run", "start"],
        cwd: "/path/to/app",
        auto_restart: true
      })
      
      # Start the process
      Nurvus.start_process("my_app")
      
      # Check status
      Nurvus.get_status("my_app")
      
      # List all processes
      Nurvus.list_processes()
  """

  alias Nurvus.{ProcessManager, ProcessMonitor}

  ## Process Management API

  @doc """
  Adds a new process configuration.
  """
  @spec add_process(map()) :: :ok | {:error, term()}
  def add_process(config) do
    ProcessManager.add_process(config)
  end

  @doc """
  Removes a process configuration and stops it if running.
  """
  @spec remove_process(String.t()) :: :ok | {:error, :not_found}
  def remove_process(process_id) do
    ProcessManager.remove_process(process_id)
  end

  @doc """
  Starts a configured process.
  """
  @spec start_process(String.t()) :: :ok | {:error, term()}
  def start_process(process_id) do
    ProcessManager.start_process(process_id)
  end

  @doc """
  Stops a running process.
  """
  @spec stop_process(String.t()) :: :ok | {:error, term()}
  def stop_process(process_id) do
    ProcessManager.stop_process(process_id)
  end

  @doc """
  Restarts a process (stop then start).
  """
  @spec restart_process(String.t()) :: :ok | {:error, term()}
  def restart_process(process_id) do
    ProcessManager.restart_process(process_id)
  end

  @doc """
  Gets the current status of a process.
  """
  @spec get_status(String.t()) :: {:ok, atom()} | {:error, :not_found}
  def get_status(process_id) do
    ProcessManager.get_process_status(process_id)
  end

  @doc """
  Lists all configured processes with their current status.
  """
  @spec list_processes() :: [map()]
  def list_processes do
    ProcessManager.list_processes()
  end

  ## Monitoring API

  @doc """
  Gets performance metrics for a specific process.
  """
  @spec get_metrics(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_metrics(process_id) do
    ProcessMonitor.get_metrics(process_id)
  end

  @doc """
  Gets performance metrics for all processes.
  """
  @spec get_all_metrics() :: map()
  def get_all_metrics do
    ProcessMonitor.get_all_metrics()
  end

  @doc """
  Gets current alerts for unhealthy processes.
  """
  @spec get_alerts() :: [map()]
  def get_alerts do
    ProcessMonitor.get_alerts()
  end

  @doc """
  Clears all current alerts.
  """
  @spec clear_alerts() :: :ok
  def clear_alerts do
    ProcessMonitor.clear_alerts()
  end

  ## Utility Functions

  @doc """
  Gets overall system status including process count and health.
  """
  @spec system_status() :: map()
  def system_status do
    processes = list_processes()

    %{
      total_processes: length(processes),
      running: Enum.count(processes, &(&1.status == :running)),
      stopped: Enum.count(processes, &(&1.status == :stopped)),
      failed: Enum.count(processes, &(&1.status == :failed)),
      alerts: length(get_alerts()),
      uptime: get_uptime()
    }
  end

  defp get_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    # Convert to seconds
    div(uptime_ms, 1000)
  end
end

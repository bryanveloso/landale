defmodule Server.ProcessSupervisor.Saya do
  @moduledoc """
  Process supervision for saya (Mac Mini with Docker services).

  Manages Docker Compose services: landale-server, overlays, postgres, seq.
  Since these are all Docker containers, this could be simplified to just
  manage docker-compose up/down for the entire stack.

  ## Managed Processes

  - landale-server: Main Landale server container
  - landale-overlays: Overlay services container  
  - postgres: PostgreSQL database container
  - seq: Structured logging container
  """

  @behaviour Server.ProcessSupervisorBehaviour

  require Logger

  alias Server.ProcessSupervisorBehaviour


  # Simple Docker Compose stack management
  # OrbStack handles the individual containers beautifully, so we just manage the entire stack
  @managed_processes %{
    "stack" => %{
      name: "stack",
      display_name: "Landale Docker Stack",
      type: :docker_compose_stack,
      compose_file: "/opt/landale/docker-compose.yml",
      description: "Entire Landale stack (server, overlays, postgres, seq)"
    }
  }

  @impl ProcessSupervisorBehaviour
  def init do
    Logger.info("Initializing Saya ProcessSupervisor (Docker Compose stub)")

    # Verify we can run docker commands
    case System.cmd("docker", ["--version"], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("Docker available, Saya ProcessSupervisor ready")
        {:ok, "Saya ProcessSupervisor initialized (Docker stack management only)"}

      {error, _exit_code} ->
        Logger.error("Docker not available", error: error)
        {:error, "Docker not available: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception during Saya ProcessSupervisor initialization", error: inspect(error))
      {:error, "System command error: #{inspect(error)}"}
  end

  @impl ProcessSupervisorBehaviour
  def managed_processes do
    Map.keys(@managed_processes)
  end

  @impl ProcessSupervisorBehaviour
  def list_processes do
    {:ok,
     [
       %{
         name: "stack",
         display_name: "Landale Docker Stack",
         status: :managed_by_orbstack,
         note: "Use OrbStack UI for detailed container information"
       }
     ]}
  end

  @impl ProcessSupervisorBehaviour
  def get_process("stack") do
    Logger.info("Checking Docker stack status")

    case System.cmd("docker", ["compose", "-f", "/opt/landale/docker-compose.yml", "ps", "--format", "json"],
           stderr_to_stdout: true,
           cd: "/opt/landale"
         ) do
      {output, 0} ->
        # Parse the JSON output to determine if services are running
        running_containers =
          output
          |> String.split("\n")
          |> Enum.filter(&(&1 != ""))
          |> Enum.count()

        status = if running_containers > 0, do: :running, else: :stopped

        {:ok,
         %{
           name: "stack",
           display_name: "Landale Docker Stack",
           status: status,
           containers: running_containers,
           description: "Managed by OrbStack - use OrbStack UI for detailed container info"
         }}

      {error, _exit_code} ->
        Logger.error("Failed to get Docker stack status", error: error)
        {:error, "Failed to get stack status: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception getting Docker stack status", error: inspect(error))
      {:error, "System error: #{inspect(error)}"}
  end

  def get_process(_process_name) do
    {:error, "Only 'stack' management supported. Use OrbStack UI for individual containers."}
  end

  @impl ProcessSupervisorBehaviour
  def start_process("stack") do
    Logger.info("Starting Landale Docker stack")

    case System.cmd("docker", ["compose", "-f", "/opt/landale/docker-compose.yml", "up", "-d"],
           stderr_to_stdout: true,
           cd: "/opt/landale"
         ) do
      {_output, 0} ->
        Logger.info("Docker stack started successfully")
        :ok

      {error, _exit_code} ->
        Logger.error("Failed to start Docker stack", error: error)
        {:error, "Failed to start stack: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception starting Docker stack", error: inspect(error))
      {:error, "System error: #{inspect(error)}"}
  end

  def start_process(_process_name) do
    {:error, "Only 'stack' management supported. Use OrbStack UI for individual containers."}
  end

  @impl ProcessSupervisorBehaviour
  def stop_process("stack") do
    Logger.info("Stopping Landale Docker stack")

    case System.cmd("docker", ["compose", "-f", "/opt/landale/docker-compose.yml", "down"],
           stderr_to_stdout: true,
           cd: "/opt/landale"
         ) do
      {_output, 0} ->
        Logger.info("Docker stack stopped successfully")
        :ok

      {error, _exit_code} ->
        Logger.error("Failed to stop Docker stack", error: error)
        {:error, "Failed to stop stack: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception stopping Docker stack", error: inspect(error))
      {:error, "System error: #{inspect(error)}"}
  end

  def stop_process(_process_name) do
    {:error, "Only 'stack' management supported. Use OrbStack UI for individual containers."}
  end

  @impl ProcessSupervisorBehaviour
  def restart_process("stack") do
    Logger.info("Restarting Landale Docker stack")

    case stop_process("stack") do
      :ok ->
        # Wait for graceful shutdown
        Process.sleep(2000)
        start_process("stack")

      error ->
        error
    end
  end

  def restart_process(_process_name) do
    {:error, "Only 'stack' management supported. Use OrbStack UI for individual containers."}
  end

  @impl ProcessSupervisorBehaviour
  def process_running?("stack") do
    case get_process("stack") do
      {:ok, %{status: :running}} -> true
      _ -> false
    end
  end
  def process_running?(_), do: false

  @impl ProcessSupervisorBehaviour
  def cleanup do
    Logger.info("Saya ProcessSupervisor cleanup completed")
    :ok
  end
end

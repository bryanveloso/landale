defmodule Server.ProcessSupervisor.Linux do
  @moduledoc """
  Linux-specific process supervision implementation.

  Uses Linux system commands (ps, kill, systemctl, etc.) to manage processes
  on Linux machines in the distributed Elixir cluster.

  ## Managed Processes

  - nginx: Nginx web server
  - postgresql: PostgreSQL database
  - redis: Redis server
  - docker: Docker daemon
  - nodejs: Node.js applications
  - python: Python applications
  """

  @behaviour Server.ProcessSupervisorBehaviour

  require Logger

  alias Server.ProcessSupervisorBehaviour

  # Process definitions for Linux
  @managed_processes %{
    "nginx" => %{
      name: "nginx",
      display_name: "Nginx Web Server",
      service_name: "nginx",
      process_name: "nginx",
      type: :systemd_service
    },
    "postgresql" => %{
      name: "postgresql",
      display_name: "PostgreSQL Database",
      service_name: "postgresql",
      process_name: "postgres",
      type: :systemd_service
    },
    "redis" => %{
      name: "redis",
      display_name: "Redis Server",
      service_name: "redis-server",
      process_name: "redis-server",
      type: :systemd_service
    },
    "docker" => %{
      name: "docker",
      display_name: "Docker Daemon",
      service_name: "docker",
      process_name: "dockerd",
      type: :systemd_service
    },
    "nodejs" => %{
      name: "nodejs",
      display_name: "Node.js Application",
      process_name: "node",
      start_command: "node /opt/app/server.js",
      type: :process
    },
    "python" => %{
      name: "python",
      display_name: "Python Application",
      process_name: "python3",
      start_command: "python3 /opt/app/main.py",
      type: :process
    }
  }

  @impl ProcessSupervisorBehaviour
  def init do
    Logger.info("Initializing Linux ProcessSupervisor")

    # Verify we can run Linux commands
    case System.cmd("ps", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        if String.contains?(output, "procps") or String.contains?(output, "BusyBox") do
          Logger.info("Linux system commands verified successfully")
          :ok
        else
          {:error, "Unable to verify Linux system - ps command not recognized"}
        end

      {error, _code} ->
        Logger.error("Failed to initialize Linux ProcessSupervisor", error: error)
        {:error, "Unable to run Linux system commands: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception during Linux ProcessSupervisor initialization", error: inspect(error))
      {:error, "System command error: #{inspect(error)}"}
  end

  @impl ProcessSupervisorBehaviour
  def managed_processes do
    Map.keys(@managed_processes)
  end

  @impl ProcessSupervisorBehaviour
  def list_processes do
    case System.cmd("ps", ["aux"], stderr_to_stdout: true) do
      {output, 0} ->
        processes = parse_ps_output(output)
        {:ok, processes}

      {error, code} ->
        Logger.error("Failed to list Linux processes", error: error, exit_code: code)
        {:error, "ps command failed: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception listing Linux processes", error: inspect(error))
      {:error, "System error: #{inspect(error)}"}
  end

  @impl ProcessSupervisorBehaviour
  def get_process(process_name) do
    case Map.get(@managed_processes, process_name) do
      nil ->
        {:error, :process_not_managed}

      process_config ->
        case find_running_process(process_config.process_name) do
          nil ->
            # For systemd services, also check service status
            status =
              if process_config.type == :systemd_service do
                get_systemd_service_status(process_config.service_name)
              else
                :stopped
              end

            {:ok,
             %{
               name: process_name,
               display_name: process_config.display_name,
               status: status,
               pid: nil,
               memory_mb: 0,
               cpu_percent: 0.0
             }}

          process_info ->
            {:ok, process_info}
        end
    end
  end

  @impl ProcessSupervisorBehaviour
  def start_process(process_name) do
    case Map.get(@managed_processes, process_name) do
      nil ->
        {:error, :process_not_managed}

      process_config ->
        case process_config.type do
          :systemd_service ->
            start_systemd_service(process_config)

          :process ->
            start_regular_process(process_config)
        end
    end
  end

  @impl ProcessSupervisorBehaviour
  def stop_process(process_name) do
    case Map.get(@managed_processes, process_name) do
      nil ->
        {:error, :process_not_managed}

      process_config ->
        case process_config.type do
          :systemd_service ->
            stop_systemd_service(process_config)

          :process ->
            stop_regular_process(process_config)
        end
    end
  end

  @impl ProcessSupervisorBehaviour
  def restart_process(process_name) do
    case Map.get(@managed_processes, process_name) do
      nil ->
        {:error, :process_not_managed}

      process_config ->
        case process_config.type do
          :systemd_service ->
            restart_systemd_service(process_config)

          :process ->
            case stop_process(process_name) do
              :ok ->
                Process.sleep(2000)
                start_process(process_name)

              error ->
                error
            end
        end
    end
  end

  @impl ProcessSupervisorBehaviour
  def process_running?(process_name) do
    case Map.get(@managed_processes, process_name) do
      nil ->
        false

      process_config ->
        case process_config.type do
          :systemd_service ->
            get_systemd_service_status(process_config.service_name) == :running

          :process ->
            case find_running_process(process_config.process_name) do
              nil -> false
              _process -> true
            end
        end
    end
  end

  @impl ProcessSupervisorBehaviour
  def cleanup do
    Logger.info("Linux ProcessSupervisor cleanup completed")
    :ok
  end

  # Private Functions

  defp parse_ps_output(output) do
    output
    |> String.split("\n", trim: true)
    # Skip header
    |> Enum.drop(1)
    |> Enum.map(&parse_ps_row/1)
    |> Enum.filter(&(&1 != nil))
    |> Enum.filter(&managed_process?/1)
  end

  defp parse_ps_row(row) do
    case String.split(row, ~r/\s+/, trim: true, parts: 11) do
      [_user, pid_str, cpu_str, mem_str, _vsz, _rss, _tty, _stat, _start, _time, command | _] ->
        case {parse_integer(pid_str), parse_float(cpu_str), parse_float(mem_str)} do
          {{:ok, pid}, {:ok, cpu}, {:ok, mem}} ->
            process_name = find_process_name_by_command(command)

            if process_name do
              process_config = Map.get(@managed_processes, process_name)

              # Convert memory percentage to MB (rough estimation)
              memory_mb = estimate_memory_mb(mem)

              %{
                name: process_name,
                display_name: process_config.display_name,
                status: :running,
                pid: pid,
                memory_mb: memory_mb,
                cpu_percent: cpu
              }
            else
              nil
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  rescue
    _error ->
      nil
  end

  defp find_running_process(process_name) do
    case list_processes() do
      {:ok, processes} ->
        Enum.find(processes, fn proc ->
          case Map.get(@managed_processes, proc.name) do
            nil -> false
            config -> config.process_name == process_name
          end
        end)

      {:error, _} ->
        nil
    end
  end

  defp start_systemd_service(process_config) do
    Logger.info("Starting Linux systemd service",
      service: process_config.service_name
    )

    case System.cmd("systemctl", ["start", process_config.service_name], stderr_to_stdout: true) do
      {_output, 0} ->
        # Wait a moment then verify service started
        Process.sleep(2000)

        case get_systemd_service_status(process_config.service_name) do
          :running ->
            Logger.info("Linux systemd service started successfully",
              service: process_config.service_name
            )

            :ok

          _status ->
            {:error, "Service failed to start or start verification failed"}
        end

      {error, code} ->
        Logger.error("Failed to start Linux systemd service",
          service: process_config.service_name,
          error: error,
          exit_code: code
        )

        {:error, "systemctl start failed: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception starting Linux systemd service",
        service: process_config.service_name,
        error: inspect(error)
      )

      {:error, "System error: #{inspect(error)}"}
  end

  defp stop_systemd_service(process_config) do
    Logger.info("Stopping Linux systemd service",
      service: process_config.service_name
    )

    case System.cmd("systemctl", ["stop", process_config.service_name], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("Linux systemd service stopped successfully",
          service: process_config.service_name
        )

        :ok

      {error, code} ->
        Logger.error("Failed to stop Linux systemd service",
          service: process_config.service_name,
          error: error,
          exit_code: code
        )

        {:error, "systemctl stop failed: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception stopping Linux systemd service",
        service: process_config.service_name,
        error: inspect(error)
      )

      {:error, "System error: #{inspect(error)}"}
  end

  defp restart_systemd_service(process_config) do
    Logger.info("Restarting Linux systemd service",
      service: process_config.service_name
    )

    case System.cmd("systemctl", ["restart", process_config.service_name], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("Linux systemd service restarted successfully",
          service: process_config.service_name
        )

        :ok

      {error, code} ->
        Logger.error("Failed to restart Linux systemd service",
          service: process_config.service_name,
          error: error,
          exit_code: code
        )

        {:error, "systemctl restart failed: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception restarting Linux systemd service",
        service: process_config.service_name,
        error: inspect(error)
      )

      {:error, "System error: #{inspect(error)}"}
  end

  defp start_regular_process(process_config) do
    Logger.info("Starting Linux process",
      process: process_config.name,
      command: process_config.start_command
    )

    case System.cmd("sh", ["-c", process_config.start_command <> " &"], stderr_to_stdout: true) do
      {_output, 0} ->
        # Process starting is asynchronous, wait a moment then verify
        Process.sleep(3000)

        case find_running_process(process_config.process_name) do
          nil ->
            {:error, "Process failed to start or start verification failed"}

          _process ->
            Logger.info("Linux process started successfully", process: process_config.name)
            :ok
        end

      {error, code} ->
        Logger.error("Failed to start Linux process",
          process: process_config.name,
          error: error,
          exit_code: code
        )

        {:error, "Start command failed: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception starting Linux process",
        process: process_config.name,
        error: inspect(error)
      )

      {:error, "System error: #{inspect(error)}"}
  end

  defp stop_regular_process(process_config) do
    case find_running_process(process_config.process_name) do
      nil ->
        Logger.info("Process not running", process: process_config.name)
        :ok

      %{pid: pid} ->
        Logger.info("Stopping Linux process",
          pid: pid,
          process: process_config.name
        )

        terminate_linux_process(pid, process_config)
    end
  rescue
    error ->
      Logger.error("Exception stopping Linux process",
        process: process_config.name,
        error: inspect(error)
      )

      {:error, "System error: #{inspect(error)}"}
  end

  defp terminate_linux_process(pid, process_config) do
    # Try graceful termination first
    case System.cmd("kill", ["-TERM", to_string(pid)], stderr_to_stdout: true) do
      {_output, 0} ->
        # Wait a moment for graceful shutdown
        Process.sleep(2000)
        check_process_terminated(pid, process_config)

      {error, code} ->
        Logger.error("Failed to send termination signal to Linux process",
          pid: pid,
          process: process_config.name,
          error: error,
          exit_code: code
        )

        {:error, "Termination signal failed: #{error}"}
    end
  end

  defp check_process_terminated(pid, process_config) do
    # Check if process is still running
    case System.cmd("ps", ["-p", to_string(pid)], stderr_to_stdout: true) do
      {_output, 0} ->
        # Process still running, force kill
        Logger.info("Graceful termination failed, forcing kill",
          pid: pid,
          process: process_config.name
        )

        force_kill_process(pid, process_config)

      {_output, 1} ->
        # Process terminated gracefully
        Logger.info("Linux process stopped gracefully",
          pid: pid,
          process: process_config.name
        )

        :ok
    end
  end

  defp force_kill_process(pid, process_config) do
    case System.cmd("kill", ["-9", to_string(pid)], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("Linux process stopped successfully",
          pid: pid,
          process: process_config.name
        )

        :ok

      {error, code} ->
        Logger.error("Failed to force kill Linux process",
          pid: pid,
          process: process_config.name,
          error: error,
          exit_code: code
        )

        {:error, "Force kill failed: #{error}"}
    end
  end

  defp get_systemd_service_status(service_name) do
    case System.cmd("systemctl", ["is-active", service_name], stderr_to_stdout: true) do
      {"active\n", 0} -> :running
      {"inactive\n", _} -> :stopped
      {"failed\n", _} -> :failed
      _ -> :unknown
    end
  rescue
    _error -> :unknown
  end

  defp managed_process?(%{name: name}) do
    Map.has_key?(@managed_processes, name)
  end

  defp find_process_name_by_command(command) do
    @managed_processes
    |> Enum.find_value(fn {name, config} ->
      if String.contains?(command, config.process_name) do
        name
      else
        nil
      end
    end)
  end

  defp parse_integer(str) do
    case Integer.parse(str) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_integer}
    end
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {float, ""} -> {:ok, float}
      _ -> {:error, :invalid_float}
    end
  end

  defp estimate_memory_mb(mem_percent) do
    # Rough estimation: assume 8GB total RAM for Linux servers
    # This is a simplification - in production you'd get actual system memory
    total_ram_mb = 8 * 1024
    Float.round(total_ram_mb * mem_percent / 100.0, 1)
  end
end

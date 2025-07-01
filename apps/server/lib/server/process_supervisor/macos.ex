defmodule Server.ProcessSupervisor.MacOS do
  @moduledoc """
  macOS-specific process supervision implementation.

  Uses macOS system commands (ps, kill, open, etc.) to manage processes
  on macOS machines in the distributed Elixir cluster.

  ## Managed Processes

  - terminal: Terminal.app
  - finder: Finder.app
  - safari: Safari.app
  - chrome: Google Chrome.app
  - vscode: Visual Studio Code.app
  - streamdeck: Stream Deck.app
  """

  @behaviour Server.ProcessSupervisorBehaviour

  require Logger

  alias Server.ProcessSupervisorBehaviour

  # Process definitions for macOS
  @managed_processes %{
    "terminal" => %{
      name: "terminal",
      display_name: "Terminal",
      app_name: "Terminal",
      bundle_id: "com.apple.Terminal",
      app_path: "/System/Applications/Utilities/Terminal.app"
    },
    "finder" => %{
      name: "finder",
      display_name: "Finder",
      app_name: "Finder",
      bundle_id: "com.apple.finder",
      app_path: "/System/Library/CoreServices/Finder.app"
    },
    "safari" => %{
      name: "safari",
      display_name: "Safari",
      app_name: "Safari",
      bundle_id: "com.apple.Safari",
      app_path: "/Applications/Safari.app"
    },
    "chrome" => %{
      name: "chrome",
      display_name: "Google Chrome",
      app_name: "Google Chrome",
      bundle_id: "com.google.Chrome",
      app_path: "/Applications/Google Chrome.app"
    },
    "vscode" => %{
      name: "vscode",
      display_name: "Visual Studio Code",
      app_name: "Visual Studio Code",
      bundle_id: "com.microsoft.VSCode",
      app_path: "/Applications/Visual Studio Code.app"
    },
    "streamdeck" => %{
      name: "streamdeck",
      display_name: "Stream Deck",
      app_name: "Stream Deck",
      bundle_id: "com.elgato.StreamDeck",
      app_path: "/Applications/Stream Deck.app"
    }
  }

  @impl ProcessSupervisorBehaviour
  def init do
    Logger.info("Initializing macOS ProcessSupervisor")

    # Verify we can run macOS commands
    case System.cmd("ps", ["-A", "-o", "pid,comm"], stderr_to_stdout: true) do
      {output, 0} ->
        if String.contains?(output, "kernel") do
          Logger.info("macOS system commands verified successfully")
          :ok
        else
          {:error, "Unable to verify macOS system - kernel process not found"}
        end

      {error, _code} ->
        Logger.error("Failed to initialize macOS ProcessSupervisor", error: error)
        {:error, "Unable to run macOS system commands: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception during macOS ProcessSupervisor initialization", error: inspect(error))
      {:error, "System command error: #{inspect(error)}"}
  end

  @impl ProcessSupervisorBehaviour
  def managed_processes do
    Map.keys(@managed_processes)
  end

  @impl ProcessSupervisorBehaviour
  def list_processes do
    case System.cmd("ps", ["-A", "-o", "pid,ppid,comm,%cpu,%mem"], stderr_to_stdout: true) do
      {output, 0} ->
        processes = parse_ps_output(output)
        {:ok, processes}

      {error, code} ->
        Logger.error("Failed to list macOS processes", error: error, exit_code: code)
        {:error, "ps command failed: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception listing macOS processes", error: inspect(error))
      {:error, "System error: #{inspect(error)}"}
  end

  @impl ProcessSupervisorBehaviour
  def get_process(process_name) do
    case Map.get(@managed_processes, process_name) do
      nil ->
        {:error, :process_not_managed}

      process_config ->
        case find_running_process(process_config.app_name) do
          nil ->
            {:ok,
             %{
               name: process_name,
               display_name: process_config.display_name,
               status: :stopped,
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
        # Check if already running
        case find_running_process(process_config.app_name) do
          nil ->
            execute_start_command(process_config)

          _running ->
            Logger.info("Process already running", process: process_name)
            :ok
        end
    end
  end

  @impl ProcessSupervisorBehaviour
  def stop_process(process_name) do
    case Map.get(@managed_processes, process_name) do
      nil ->
        {:error, :process_not_managed}

      process_config ->
        case find_running_process(process_config.app_name) do
          nil ->
            Logger.info("Process not running", process: process_name)
            :ok

          %{pid: pid} ->
            execute_stop_command(pid, process_config)
        end
    end
  end

  @impl ProcessSupervisorBehaviour
  def restart_process(process_name) do
    case stop_process(process_name) do
      :ok ->
        # Wait a moment for the process to fully terminate
        Process.sleep(2000)
        start_process(process_name)

      error ->
        error
    end
  end

  @impl ProcessSupervisorBehaviour
  def process_running?(process_name) do
    case Map.get(@managed_processes, process_name) do
      nil ->
        false

      process_config ->
        case find_running_process(process_config.app_name) do
          nil -> false
          _process -> true
        end
    end
  end

  @impl ProcessSupervisorBehaviour
  def cleanup do
    Logger.info("macOS ProcessSupervisor cleanup completed")
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
    case String.split(row, ~r/\s+/, trim: true) do
      [pid_str, _ppid_str, comm, cpu_str, mem_str | _] ->
        case {parse_integer(pid_str), parse_float(cpu_str), parse_float(mem_str)} do
          {{:ok, pid}, {:ok, cpu}, {:ok, mem}} ->
            process_name = find_process_name_by_command(comm)

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

  defp find_running_process(app_name) do
    case list_processes() do
      {:ok, processes} ->
        Enum.find(processes, fn proc ->
          case Map.get(@managed_processes, proc.name) do
            nil -> false
            config -> config.app_name == app_name
          end
        end)

      {:error, _} ->
        nil
    end
  end

  defp execute_start_command(process_config) do
    Logger.info("Starting macOS application",
      process: process_config.name,
      app_path: process_config.app_path
    )

    case System.cmd("open", ["-a", process_config.app_name], stderr_to_stdout: true) do
      {_output, 0} ->
        # macOS app launching is asynchronous, wait a moment then verify
        Process.sleep(3000)

        case find_running_process(process_config.app_name) do
          nil ->
            {:error, "Application failed to start or start verification failed"}

          _process ->
            Logger.info("macOS application started successfully", process: process_config.name)
            :ok
        end

      {error, code} ->
        Logger.error("Failed to start macOS application",
          process: process_config.name,
          error: error,
          exit_code: code
        )

        {:error, "Start command failed: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception starting macOS application",
        process: process_config.name,
        error: inspect(error)
      )

      {:error, "System error: #{inspect(error)}"}
  end

  defp execute_stop_command(pid, process_config) do
    Logger.info("Stopping macOS application",
      pid: pid,
      process: process_config.name
    )

    # Try graceful termination first
    case System.cmd("kill", ["-TERM", to_string(pid)], stderr_to_stdout: true) do
      {_output, 0} ->
        # Wait a moment for graceful shutdown
        Process.sleep(2000)

        # Check if process is still running
        case System.cmd("ps", ["-p", to_string(pid)], stderr_to_stdout: true) do
          {_output, 0} ->
            # Process still running, force kill
            Logger.info("Graceful termination failed, forcing kill",
              pid: pid,
              process: process_config.name
            )

            case System.cmd("kill", ["-9", to_string(pid)], stderr_to_stdout: true) do
              {_output, 0} ->
                Logger.info("macOS application stopped successfully",
                  pid: pid,
                  process: process_config.name
                )

                :ok

              {error, code} ->
                Logger.error("Failed to force kill macOS application",
                  pid: pid,
                  process: process_config.name,
                  error: error,
                  exit_code: code
                )

                {:error, "Force kill failed: #{error}"}
            end

          {_output, 1} ->
            # Process terminated gracefully
            Logger.info("macOS application stopped gracefully",
              pid: pid,
              process: process_config.name
            )

            :ok
        end

      {error, code} ->
        Logger.error("Failed to send termination signal to macOS application",
          pid: pid,
          process: process_config.name,
          error: error,
          exit_code: code
        )

        {:error, "Termination signal failed: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception stopping macOS application",
        pid: pid,
        process: process_config.name,
        error: inspect(error)
      )

      {:error, "System error: #{inspect(error)}"}
  end

  defp managed_process?(%{name: name}) do
    Map.has_key?(@managed_processes, name)
  end

  defp find_process_name_by_command(command) do
    # macOS ps command shows full path, extract app name
    app_name =
      command
      |> String.split("/")
      |> List.last()
      |> String.replace(".app", "")

    @managed_processes
    |> Enum.find_value(fn {name, config} ->
      if String.contains?(String.downcase(config.app_name), String.downcase(app_name)) or
           String.contains?(String.downcase(command), String.downcase(config.app_name)) do
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
    # Rough estimation: assume 16GB total RAM for Mac Studio
    # This is a simplification - in production you'd want to get actual system memory
    total_ram_mb = 16 * 1024
    Float.round(total_ram_mb * mem_percent / 100.0, 1)
  end
end

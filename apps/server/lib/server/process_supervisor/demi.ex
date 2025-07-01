defmodule Server.ProcessSupervisor.Demi do
  @moduledoc """
  Process supervision for demi (Windows streaming machine).

  Manages streaming applications: OBS Studio, VTube Studio, TITS Launcher
  on Windows machines in the distributed Elixir cluster.

  ## Managed Processes

  - obs: OBS Studio
  - streamdeck: Elgato Stream Deck software
  - discord: Discord application
  - chrome: Google Chrome browser
  """

  @behaviour Server.ProcessSupervisorBehaviour

  require Logger

  alias Server.ProcessSupervisorBehaviour


  # Process definitions for Windows (demi - streaming machine)
  @managed_processes %{
    "obs-studio" => %{
      name: "obs-studio",
      display_name: "OBS Studio",
      executable: "obs64.exe",
      start_command: ~s["C:\\Program Files\\obs-studio\\bin\\64bit\\obs64.exe" --enable-media-stream],
      process_name: "obs64.exe",
      cwd: "C:\\Program Files\\obs-studio\\bin\\64bit"
    },
    "vtube-studio" => %{
      name: "vtube-studio",
      display_name: "VTube Studio",
      executable: "VTube Studio.exe",
      start_command: ~s["D:\\Steam\\steamapps\\common\\VTube Studio\\VTube Studio.exe"],
      process_name: "VTube Studio.exe",
      cwd: "D:\\Steam\\steamapps\\common\\VTube Studio"
    },
    "tits" => %{
      name: "tits",
      display_name: "TITS Launcher",
      executable: "TITS Launcher.exe",
      start_command: ~s["D:\\Applications\\TITS\\TITS Launcher.exe"],
      process_name: "TITS Launcher.exe",
      cwd: "D:\\Applications\\TITS"
    }
  }

  @impl ProcessSupervisorBehaviour
  def init do
    Logger.info("Initializing Windows ProcessSupervisor")

    # Verify we can run Windows commands
    case System.cmd("tasklist", ["/FI", "IMAGENAME eq explorer.exe"], stderr_to_stdout: true) do
      {output, 0} ->
        if String.contains?(output, "explorer.exe") do
          Logger.info("Windows system commands verified successfully")
          :ok
        else
          {:error, "Unable to verify Windows system - explorer.exe not found"}
        end

      {error, _code} ->
        Logger.error("Failed to initialize Windows ProcessSupervisor", error: error)
        {:error, "Unable to run Windows system commands: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception during Windows ProcessSupervisor initialization", error: inspect(error))
      {:error, "System command error: #{inspect(error)}"}
  end

  @impl ProcessSupervisorBehaviour
  def managed_processes do
    Map.keys(@managed_processes)
  end

  @impl ProcessSupervisorBehaviour
  def list_processes do
    case System.cmd("tasklist", ["/FO", "CSV"], stderr_to_stdout: true) do
      {output, 0} ->
        processes = parse_tasklist_output(output)
        {:ok, processes}

      {error, code} ->
        Logger.error("Failed to list Windows processes", error: error, exit_code: code)
        {:error, "tasklist command failed: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception listing Windows processes", error: inspect(error))
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
        case find_running_process(process_config.process_name) do
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
        case find_running_process(process_config.process_name) do
          nil ->
            Logger.info("Process not running", process: process_name)
            :ok

          %{pid: pid} ->
            execute_stop_command(pid, process_config.process_name)
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
        case find_running_process(process_config.process_name) do
          nil -> false
          _process -> true
        end
    end
  end

  @impl ProcessSupervisorBehaviour
  def cleanup do
    Logger.info("Windows ProcessSupervisor cleanup completed")
    :ok
  end

  # Private Functions

  defp parse_tasklist_output(output) do
    output
    |> String.split("\n", trim: true)
    # Skip header
    |> Enum.drop(1)
    |> Enum.map(&parse_tasklist_row/1)
    |> Enum.filter(&(&1 != nil))
    |> Enum.filter(&managed_process?/1)
  end

  defp parse_tasklist_row(row) do
    case String.split(row, "\",\"") do
      [image_name_quoted, pid_quoted, _, _, memory_quoted | _] ->
        image_name = String.trim(image_name_quoted, "\"")

        case {parse_integer(String.trim(pid_quoted, "\"")), parse_memory(String.trim(memory_quoted, "\""))} do
          {{:ok, pid}, {:ok, memory_kb}} ->
            process_name = find_process_name_by_executable(image_name)

            if process_name do
              process_config = Map.get(@managed_processes, process_name)

              %{
                name: process_name,
                display_name: process_config.display_name,
                status: :running,
                pid: pid,
                memory_mb: Float.round(memory_kb / 1024.0, 1),
                # Windows tasklist doesn't provide CPU in CSV format
                cpu_percent: 0.0
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

  defp find_running_process(executable_name) do
    case list_processes() do
      {:ok, processes} ->
        Enum.find(processes, fn proc ->
          case Map.get(@managed_processes, proc.name) do
            nil -> false
            config -> config.process_name == executable_name
          end
        end)

      {:error, _} ->
        nil
    end
  end

  defp execute_start_command(process_config) do
    Logger.info("Starting Windows process",
      process: process_config.name,
      command: process_config.start_command
    )

    case System.cmd("cmd", ["/c", process_config.start_command], stderr_to_stdout: true) do
      {_output, 0} ->
        # Windows process starting is asynchronous, wait a moment then verify
        Process.sleep(3000)

        case find_running_process(process_config.process_name) do
          nil ->
            {:error, "Process failed to start or start verification failed"}

          _process ->
            Logger.info("Windows process started successfully", process: process_config.name)
            :ok
        end

      {error, code} ->
        Logger.error("Failed to start Windows process",
          process: process_config.name,
          error: error,
          exit_code: code
        )

        {:error, "Start command failed: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception starting Windows process",
        process: process_config.name,
        error: inspect(error)
      )

      {:error, "System error: #{inspect(error)}"}
  end

  defp execute_stop_command(pid, process_name) do
    Logger.info("Stopping Windows process", pid: pid, process: process_name)

    case System.cmd("taskkill", ["/PID", to_string(pid), "/F"], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("Windows process stopped successfully", pid: pid, process: process_name)
        :ok

      {error, code} ->
        Logger.error("Failed to stop Windows process",
          pid: pid,
          process: process_name,
          error: error,
          exit_code: code
        )

        {:error, "Stop command failed: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception stopping Windows process",
        pid: pid,
        process: process_name,
        error: inspect(error)
      )

      {:error, "System error: #{inspect(error)}"}
  end

  defp managed_process?(%{name: name}) do
    Map.has_key?(@managed_processes, name)
  end

  defp find_process_name_by_executable(executable) do
    @managed_processes
    |> Enum.find_value(fn {name, config} ->
      if config.process_name == executable, do: name, else: nil
    end)
  end

  defp parse_integer(str) do
    case Integer.parse(String.replace(str, ",", "")) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_integer}
    end
  end

  defp parse_memory(memory_str) do
    # Windows tasklist shows memory like "123,456 K"
    memory_str
    |> String.replace(",", "")
    |> String.replace(" K", "")
    |> String.trim()
    |> Integer.parse()
    |> case do
      {memory_kb, ""} -> {:ok, memory_kb}
      _ -> {:error, :invalid_memory}
    end
  end
end

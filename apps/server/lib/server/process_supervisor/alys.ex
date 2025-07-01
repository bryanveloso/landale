defmodule Server.ProcessSupervisor.Alys do
  @moduledoc """
  Process supervisor for alys (Windows Gaming Machine).

  Manages:
  - streamer-bot: Streaming automation software
  """

  @behaviour Server.ProcessSupervisorBehaviour

  require Logger

  alias Server.ProcessSupervisorBehaviour

  # Input validation helpers
  defp validate_process_name(name) when is_binary(name) do
    cond do
      String.length(name) > 50 ->
        {:error, :process_name_too_long}

      not Regex.match?(~r/^[a-zA-Z0-9_-]+$/, name) ->
        {:error, :invalid_process_name_format}

      not Map.has_key?(@managed_processes, name) ->
        {:error, :process_not_managed}

      true ->
        {:ok, name}
    end
  end

  defp validate_process_name(_), do: {:error, :invalid_process_name_type}

  # Process definitions for Windows (alys - gaming machine)
  @managed_processes %{
    "streamer-bot" => %{
      name: "streamer-bot",
      display_name: "Streamer.Bot",
      executable: "Streamer.Bot.exe",
      start_command: ~s["D:\\Utilities\\Streamer.Bot\\Streamer.Bot.exe"],
      process_name: "Streamer.Bot.exe",
      cwd: "D:\\Utilities\\Streamer.Bot"
    }
  }

  @impl ProcessSupervisorBehaviour
  def init do
    Logger.info("Initializing Windows Alys ProcessSupervisor")

    # Verify we can run Windows commands
    case System.cmd("tasklist", ["/FI", "IMAGENAME eq explorer.exe"], stderr_to_stdout: true) do
      {output, 0} ->
        if String.contains?(output, "explorer.exe") do
          Logger.info("Windows commands working, ProcessSupervisor ready")
          {:ok, "Windows Alys ProcessSupervisor initialized"}
        else
          Logger.warning("Windows environment check failed")
          {:error, "Windows environment verification failed"}
        end

      {error, _exit_code} ->
        Logger.error("Unable to run Windows system commands", error: error)
        {:error, "Unable to run Windows system commands: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception during Windows Alys ProcessSupervisor initialization", error: inspect(error))
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
        processes =
          output
          |> String.split("\n")
          |> Enum.drop(1)
          |> Enum.filter(&(&1 != ""))
          |> Enum.map(&parse_tasklist_line/1)
          |> Enum.filter(&(!is_nil(&1)))

        {:ok, processes}

      {error, _exit_code} ->
        Logger.error("Failed to list Windows processes", error: error)
        {:error, "Unable to list processes: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception listing Windows Alys processes", error: inspect(error))
      {:error, "System error: #{inspect(error)}"}
  end

  @impl ProcessSupervisorBehaviour
  def get_process(process_name) do
    with {:ok, validated_name} <- validate_process_name(process_name),
         {:ok, process_config} <- get_process_config(validated_name) do
      case find_running_process(process_config.process_name) do
        nil ->
          {:ok,
           %{
             name: validated_name,
             display_name: process_config.display_name,
             status: :stopped,
             pid: nil,
             memory_mb: 0,
             cpu_percent: 0.0
           }}

        process_info ->
          {:ok, process_info}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl ProcessSupervisorBehaviour
  def start_process(process_name) do
    with {:ok, validated_name} <- validate_process_name(process_name),
         {:ok, process_config} <- get_process_config(validated_name) do
      # Check if already running
      case find_running_process(process_config.process_name) do
        nil ->
          execute_start_command(process_config)

        _running ->
          Logger.info("Process already running", process: validated_name)
          :ok
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl ProcessSupervisorBehaviour
  def stop_process(process_name) do
    with {:ok, validated_name} <- validate_process_name(process_name),
         {:ok, process_config} <- get_process_config(validated_name) do
      case find_running_process(process_config.process_name) do
        nil ->
          Logger.info("Process not running", process: validated_name)
          :ok

        process_info ->
          terminate_process(process_info.pid, validated_name)
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl ProcessSupervisorBehaviour
  def restart_process(process_name) do
    case stop_process(process_name) do
      :ok ->
        # Wait a moment for process to fully terminate
        Process.sleep(2000)
        start_process(process_name)

      error ->
        error
    end
  end

  @impl ProcessSupervisorBehaviour
  def managed_process?(process_name) do
    Map.has_key?(@managed_processes, process_name)
  end

  # Private helper functions

  defp get_process_config(process_name) do
    case Map.get(@managed_processes, process_name) do
      nil -> {:error, :process_not_managed}
      config -> {:ok, config}
    end
  end

  defp execute_start_command(process_config) do
    cmd_parts = String.split(process_config.start_command, " ", parts: 2)

    case cmd_parts do
      [executable] ->
        case System.cmd("cmd", ["/c", "start", "/d", process_config.cwd, executable]) do
          {_output, 0} ->
            Logger.info("Started Windows process", process: process_config.name)
            :ok

          {error, exit_code} ->
            Logger.error("Failed to start Windows process",
              process: process_config.name,
              error: error,
              exit_code: exit_code
            )

            {:error, "Failed to start process: #{error}"}
        end

      [executable, args] ->
        case System.cmd("cmd", ["/c", "start", "/d", process_config.cwd, executable, args]) do
          {_output, 0} ->
            Logger.info("Started Windows process with args", process: process_config.name)
            :ok

          {error, exit_code} ->
            Logger.error("Failed to start Windows process with args",
              process: process_config.name,
              error: error,
              exit_code: exit_code
            )

            {:error, "Failed to start process: #{error}"}
        end
    end
  rescue
    error ->
      Logger.error("Exception starting Windows process",
        process: process_config.name,
        error: inspect(error)
      )

      {:error, "System error: #{inspect(error)}"}
  end

  defp find_running_process(process_name) do
    case System.cmd("tasklist", ["/FI", "IMAGENAME eq #{process_name}", "/FO", "CSV"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.drop(1)
        |> Enum.find(&String.contains?(&1, process_name))
        |> case do
          nil -> nil
          line -> parse_tasklist_line(line)
        end

      _ ->
        nil
    end
  end

  defp parse_tasklist_line(line) when is_binary(line) do
    case String.split(line, "\",\"") do
      [name_quoted, pid_quoted, _session, _session_num, memory_quoted] ->
        name = String.trim(name_quoted, "\"")
        pid_str = String.trim(pid_quoted, "\"")
        memory_str = String.trim(memory_quoted, "\"")

        case {Integer.parse(pid_str), parse_memory(memory_str)} do
          {{pid, ""}, {memory_kb, ""}} ->
            %{
              name: name,
              pid: pid,
              memory_mb: div(memory_kb, 1024),
              cpu_percent: 0.0,
              status: :running
            }

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp parse_memory(memory_str) do
    memory_str
    |> String.replace(",", "")
    |> String.replace(" K", "")
    |> Integer.parse()
  rescue
    _ -> {0, ""}
  end

  defp terminate_process(pid, process_name) do
    case System.cmd("taskkill", ["/PID", "#{pid}", "/F"], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("Terminated Windows process", process: process_name, pid: pid)
        :ok

      {error, _exit_code} ->
        Logger.error("Failed to terminate Windows process",
          process: process_name,
          pid: pid,
          error: error
        )

        {:error, "Failed to terminate process: #{error}"}
    end
  rescue
    error ->
      Logger.error("Exception terminating Windows process",
        process: process_name,
        pid: pid,
        error: inspect(error)
      )

      {:error, "System error: #{inspect(error)}"}
  end
end

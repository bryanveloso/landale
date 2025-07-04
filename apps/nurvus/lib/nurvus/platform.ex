defmodule Nurvus.Platform do
  @moduledoc """
  Platform-specific utilities for process detection and management.

  Handles differences between Windows, macOS, and Linux for:
  - Process detection (tasklist vs ps)
  - Process identification
  - Platform-specific commands
  """

  require Logger

  @type platform :: :win32 | :darwin | :linux
  @type process_info :: %{
          pid: integer(),
          name: String.t(),
          command: String.t(),
          memory_kb: integer() | nil,
          cpu_percent: float() | nil
        }

  ## Public API

  @doc """
  Detects the current platform.
  """
  @spec current_platform() :: platform()
  def current_platform do
    case :os.type() do
      {:win32, _} -> :win32
      {:unix, :darwin} -> :darwin
      {:unix, _} -> :linux
    end
  end

  @doc """
  Checks if a process is running by name.
  """
  @spec process_running?(String.t(), platform()) :: boolean()
  def process_running?(process_name, platform \\ current_platform()) do
    case get_process_list(platform) do
      {:ok, processes} ->
        processes
        |> Enum.any?(fn process ->
          String.contains?(String.downcase(process.name), String.downcase(process_name))
        end)

      {:error, _reason} ->
        false
    end
  end

  @doc """
  Gets detailed information about a specific process.
  """
  @spec get_process_info(String.t(), platform()) :: {:ok, process_info()} | {:error, term()}
  def get_process_info(process_name, platform \\ current_platform()) do
    with {:ok, processes} <- get_process_list(platform),
         process when not is_nil(process) <- find_process_by_name(processes, process_name) do
      {:ok, process}
    else
      {:error, reason} -> {:error, reason}
      nil -> {:error, :not_found}
    end
  end

  defp find_process_by_name(processes, process_name) do
    Enum.find(processes, fn process ->
      String.contains?(String.downcase(process.name), String.downcase(process_name))
    end)
  end

  @doc """
  Gets a list of all running processes.
  """
  @spec get_process_list(platform()) :: {:ok, [process_info()]} | {:error, term()}
  def get_process_list(platform \\ current_platform()) do
    case platform do
      :win32 -> get_windows_processes()
      :darwin -> get_darwin_processes()
      :linux -> get_linux_processes()
    end
  end

  @doc """
  Kills a process by PID using platform-specific commands.
  """
  @spec kill_process(integer(), platform()) :: :ok | {:error, term()}
  def kill_process(pid, platform \\ current_platform()) do
    {command, args} =
      case platform do
        :win32 -> {"taskkill", ["/PID", to_string(pid), "/F"]}
        _ -> {"kill", ["-TERM", to_string(pid)]}
      end

    case System.cmd(command, args) do
      {_output, 0} ->
        :ok

      {output, exit_code} ->
        Logger.warning("Failed to kill process #{pid}: #{output} (exit: #{exit_code})")
        {:error, {:kill_failed, exit_code}}
    end
  end

  @doc """
  Gets process metrics (CPU, memory) by PID.
  """
  @spec get_process_metrics(integer(), platform()) :: {:ok, map()} | {:error, term()}
  def get_process_metrics(pid, platform \\ current_platform()) do
    case platform do
      :win32 -> get_windows_process_metrics(pid)
      :darwin -> get_darwin_process_metrics(pid)
      :linux -> get_linux_process_metrics(pid)
    end
  end

  ## Private Functions - Windows

  defp get_windows_processes do
    {output, 0} =
      System.cmd("wmic", [
        "process",
        "get",
        "ProcessId,Name,CommandLine,WorkingSetSize,PageFileUsage",
        "/format:csv"
      ])

    processes =
      output
      |> String.split("\r\n")
      |> Enum.drop(2)
      |> Enum.filter(&(String.trim(&1) != ""))
      |> Enum.map(&parse_windows_process_line/1)
      |> Enum.filter(& &1)

    {:ok, processes}
  rescue
    error ->
      Logger.error("Failed to get Windows processes: #{inspect(error)}")
      {:error, :command_failed}
  end

  defp parse_windows_process_line(line) do
    case String.split(line, ",") do
      [_node, command, name, _page_file, pid, working_set] ->
        with {pid_int, ""} <- Integer.parse(String.trim(pid)),
             {memory_kb, ""} <- Integer.parse(String.trim(working_set)) do
          %{
            pid: pid_int,
            name: String.trim(name),
            command: String.trim(command),
            memory_kb: div(memory_kb, 1024),
            cpu_percent: nil
          }
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp get_windows_process_metrics(pid) do
    {output, 0} =
      System.cmd("wmic", [
        "process",
        "where",
        "ProcessId=#{pid}",
        "get",
        "WorkingSetSize,PageFileUsage,PercentProcessorTime",
        "/format:csv"
      ])

    case parse_windows_metrics(output) do
      nil -> {:error, :not_found}
      metrics -> {:ok, metrics}
    end
  rescue
    error ->
      Logger.error("Failed to get Windows process metrics for PID #{pid}: #{inspect(error)}")
      {:error, :command_failed}
  end

  defp parse_windows_metrics(output) do
    output
    |> String.split("\r\n")
    |> Enum.drop(2)
    |> Enum.filter(&(String.trim(&1) != ""))
    |> List.first()
    |> case do
      nil ->
        nil

      line ->
        case String.split(line, ",") do
          [_node, _page_file, _cpu_time, working_set] ->
            with {memory_kb, ""} <- Integer.parse(String.trim(working_set)) do
              %{
                memory_mb: memory_kb / 1024 / 1024,
                cpu_percent: 0.0
              }
            else
              _ -> nil
            end

          _ ->
            nil
        end
    end
  end

  ## Private Functions - macOS/Darwin

  defp get_darwin_processes do
    {output, 0} = System.cmd("ps", ["aux"])

    processes =
      output
      |> String.split("\n")
      |> Enum.drop(1)
      |> Enum.filter(&(String.trim(&1) != ""))
      |> Enum.map(&parse_darwin_process_line/1)
      |> Enum.filter(& &1)

    {:ok, processes}
  rescue
    error ->
      Logger.error("Failed to get Darwin processes: #{inspect(error)}")
      {:error, :command_failed}
  end

  defp parse_darwin_process_line(line) do
    case String.split(line, ~r/\s+/, parts: 11) do
      [_user, pid, cpu, mem, _vsz, _rss, _tty, _stat, _start, _time | command] ->
        with {pid_int, ""} <- Integer.parse(pid),
             {cpu_float, ""} <- Float.parse(cpu),
             {_mem_float, ""} <- Float.parse(mem) do
          command_str = Enum.join(command, " ")

          # Extract process name from command
          process_name =
            command_str
            |> String.split(" ")
            |> List.first()
            |> Path.basename()

          %{
            pid: pid_int,
            name: process_name,
            command: command_str,
            memory_kb: nil,
            cpu_percent: cpu_float
          }
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp get_darwin_process_metrics(pid) do
    {output, 0} = System.cmd("ps", ["-p", to_string(pid), "-o", "pid,pcpu,rss"])

    case parse_darwin_metrics(output) do
      nil -> {:error, :not_found}
      metrics -> {:ok, metrics}
    end
  rescue
    error ->
      Logger.error("Failed to get Darwin process metrics for PID #{pid}: #{inspect(error)}")
      {:error, :command_failed}
  end

  defp parse_darwin_metrics(output) do
    output
    |> String.split("\n")
    |> Enum.drop(1)
    |> Enum.filter(&(String.trim(&1) != ""))
    |> List.first()
    |> parse_darwin_metrics_line()
  end

  defp parse_darwin_metrics_line(nil), do: nil

  defp parse_darwin_metrics_line(line) do
    case String.split(String.trim(line), ~r/\s+/) do
      [_pid, cpu, rss] -> parse_darwin_cpu_memory(cpu, rss)
      _ -> nil
    end
  end

  defp parse_darwin_cpu_memory(cpu, rss) do
    with {cpu_float, ""} <- Float.parse(cpu),
         {rss_int, ""} <- Integer.parse(rss) do
      %{
        cpu_percent: cpu_float,
        memory_mb: rss_int / 1024
      }
    else
      _ -> nil
    end
  end

  ## Private Functions - Linux

  defp get_linux_processes do
    {output, 0} = System.cmd("ps", ["aux"])

    processes =
      output
      |> String.split("\n")
      |> Enum.drop(1)
      |> Enum.filter(&(String.trim(&1) != ""))
      |> Enum.map(&parse_linux_process_line/1)
      |> Enum.filter(& &1)

    {:ok, processes}
  rescue
    error ->
      Logger.error("Failed to get Linux processes: #{inspect(error)}")
      {:error, :command_failed}
  end

  defp parse_linux_process_line(line) do
    # Linux ps aux output is similar to Darwin
    parse_darwin_process_line(line)
  end

  defp get_linux_process_metrics(pid) do
    # Linux process metrics are similar to Darwin
    get_darwin_process_metrics(pid)
  end
end

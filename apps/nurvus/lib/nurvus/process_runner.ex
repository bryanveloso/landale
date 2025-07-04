defmodule Nurvus.ProcessRunner do
  @moduledoc """
  GenServer that wraps and manages a single external process.

  This module handles:
  - Starting the external process using System.cmd or Port
  - Monitoring the process health
  - Capturing stdout/stderr
  - Graceful shutdown
  - Resource cleanup
  """

  use GenServer
  require Logger

  @type config :: %{
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

  defstruct [
    :config,
    :port,
    :os_pid,
    :start_time,
    :restart_count,
    :last_restart
  ]

  ## Client API

  @spec start_link(config()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @spec get_info(pid()) :: map()
  def get_info(pid) do
    GenServer.call(pid, :get_info)
  end

  @spec get_logs(pid(), non_neg_integer()) :: [String.t()]
  def get_logs(pid, lines \\ 50) do
    GenServer.call(pid, {:get_logs, lines})
  end

  @spec signal(pid(), atom()) :: :ok | {:error, term()}
  def signal(pid, signal) do
    GenServer.call(pid, {:signal, signal})
  end

  ## GenServer Callbacks

  @impl true
  def init(config) do
    # Trap exits so we can clean up properly
    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      config: config,
      port: nil,
      os_pid: nil,
      start_time: DateTime.utc_now(),
      restart_count: 0,
      last_restart: nil
    }

    {:ok, state, {:continue, :start_process}}
  end

  @impl true
  def handle_continue(:start_process, state) do
    case start_external_process(state.config) do
      {:ok, port, os_pid} ->
        Logger.info("Started external process: #{state.config.name} (OS PID: #{os_pid})")

        new_state = %{state | port: port, os_pid: os_pid, start_time: DateTime.utc_now()}

        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to start process #{state.config.name}: #{inspect(reason)}")
        {:stop, {:shutdown, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    uptime =
      if state.start_time do
        DateTime.diff(DateTime.utc_now(), state.start_time, :second)
      else
        0
      end

    info = %{
      id: state.config.id,
      name: state.config.name,
      command: state.config.command,
      args: state.config.args,
      os_pid: state.os_pid,
      uptime_seconds: uptime,
      restart_count: state.restart_count,
      last_restart: state.last_restart,
      status: if(state.port, do: :running, else: :stopped)
    }

    {:reply, info, state}
  end

  @impl true
  def handle_call({:get_logs, _lines}, _from, state) do
    # For now, return empty logs - in a full implementation,
    # we'd capture and store process output
    logs = []
    {:reply, logs, state}
  end

  @impl true
  def handle_call({:signal, signal}, _from, state) do
    case state.os_pid do
      nil ->
        {:reply, {:error, :not_running}, state}

      os_pid ->
        try do
          # Send signal to the process
          case signal do
            :term -> System.cmd("kill", ["-TERM", to_string(os_pid)])
            :kill -> System.cmd("kill", ["-KILL", to_string(os_pid)])
            :int -> System.cmd("kill", ["-INT", to_string(os_pid)])
            _ -> {:error, :unsupported_signal}
          end

          {:reply, :ok, state}
        rescue
          error ->
            {:reply, {:error, error}, state}
        end
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Log process output
    output = String.trim(data)

    if output != "" do
      Logger.info("[#{state.config.name}] #{output}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("Process #{state.config.name} exited with status: #{status}")

    # Close the port
    if state.port do
      Port.close(state.port)
    end

    new_state = %{state | port: nil, os_pid: nil}

    # Exit this GenServer - the ProcessManager will handle restart logic
    {:stop, {:shutdown, {:exit_status, status}}, new_state}
  end

  @impl true
  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    Logger.warning("Port for #{state.config.name} exited: #{inspect(reason)}")

    new_state = %{state | port: nil, os_pid: nil}
    {:stop, {:shutdown, reason}, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message in ProcessRunner: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Terminating ProcessRunner for #{state.config.name}: #{inspect(reason)}")

    # Clean up the external process
    if state.port do
      Port.close(state.port)
    end

    # If we have an OS PID, try to terminate it gracefully
    if state.os_pid do
      try do
        # Send TERM signal first
        System.cmd("kill", ["-TERM", to_string(state.os_pid)])

        # Use non-blocking approach: check if process is still running
        # If it's still alive after TERM, send KILL immediately
        case System.cmd("kill", ["-0", to_string(state.os_pid)], stderr_to_stdout: true) do
          {_, 0} ->
            # Process still exists, force kill
            System.cmd("kill", ["-KILL", to_string(state.os_pid)])

          _ ->
            # Process already terminated
            :ok
        end
      rescue
        # Process might already be dead
        _ -> :ok
      end
    end

    :ok
  end

  ## Private Functions

  defp start_external_process(config) do
    # Build command options
    opts = build_port_options(config)

    try do
      # Start the process using a Port
      port = Port.open({:spawn_executable, find_executable(config.command)}, opts)

      # Get the OS PID of the spawned process
      case get_os_pid(port) do
        {:ok, os_pid} ->
          {:ok, port, os_pid}

        {:error, reason} ->
          Port.close(port)
          {:error, reason}
      end
    rescue
      error ->
        {:error, error}
    end
  end

  defp build_port_options(config) do
    base_opts = [
      :binary,
      :exit_status,
      {:args, config.args},
      {:line, 1024}
    ]

    # Add working directory if specified
    opts =
      if config.cwd do
        [{:cd, config.cwd} | base_opts]
      else
        base_opts
      end

    # Add environment variables if specified
    if map_size(config.env) > 0 do
      env_list =
        Enum.map(config.env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

      [{:env, env_list} | opts]
    else
      opts
    end
  end

  defp find_executable(command) do
    case System.find_executable(command) do
      nil ->
        # If not found in PATH, assume it's a relative/absolute path
        command

      path ->
        path
    end
  end

  defp get_os_pid(port) do
    # Try to get the OS PID using port_info
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} when is_integer(os_pid) ->
        {:ok, os_pid}

      _ ->
        {:error, :no_os_pid}
    end
  end
end

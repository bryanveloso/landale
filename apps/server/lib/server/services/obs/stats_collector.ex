defmodule Server.Services.OBS.StatsCollector do
  @moduledoc """
  Collects and manages OBS performance statistics.

  Polls OBS for stats at regular intervals and makes them available
  via ETS for fast reads.
  """
  use GenServer
  require Logger

  # Poll every 5 seconds
  @stats_interval 5_000

  defstruct [
    :session_id,
    :ets_table,
    :stats_timer,
    # Performance stats
    active_fps: 0,
    average_frame_time: 0,
    cpu_usage: 0,
    memory_usage: 0,
    available_disk_space: 0,
    render_total_frames: 0,
    render_skipped_frames: 0,
    output_total_frames: 0,
    output_skipped_frames: 0,
    stats_last_updated: nil
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Get cached stats from ETS.
  """
  def get_stats_cached(session_id) do
    table_name = :"obs_stats_#{session_id}"

    try do
      case :ets.lookup(table_name, :stats) do
        [{:stats, stats}] -> {:ok, stats}
        [] -> {:error, :not_found}
      end
    catch
      :error, :badarg -> {:error, :not_found}
    end
  end

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)

    # Create ETS table for stats
    table_name = :"obs_stats_#{session_id}"
    table = :ets.new(table_name, [:set, :protected, :named_table])

    state = %__MODULE__{
      session_id: session_id,
      ets_table: table
    }

    # Start polling timer
    {:ok, schedule_stats_poll(state)}
  end

  @impl true
  def handle_info(:poll_stats, state) do
    # Check if OBS is connected before requesting stats
    case Server.Services.OBS.get_status() do
      {:ok, %{connected: true}} ->
        # OBS is connected, try to get stats
        case get_connection(state.session_id) do
          {:ok, conn} ->
            # Capture the StatsCollector PID before starting the Task
            stats_collector_pid = self()

            Task.start(fn ->
              # Try GetSceneList first - this is a basic OBS v5 request
              # Use a shorter timeout to avoid long waits when OBS is disconnecting
              try do
                case GenServer.call(conn, {:send_request, "GetSceneList", %{}}, 2000) do
                  {:ok, version_data} ->
                    # Got the OBS response - send it to StatsCollector
                    send(stats_collector_pid, {:version_received, version_data})

                  {:error, reason} ->
                    Logger.debug("Failed to get OBS stats: #{inspect(reason)}",
                      service: "obs",
                      session_id: state.session_id
                    )
                end
              catch
                :exit, {:timeout, _} ->
                  Logger.debug("OBS stats request timed out - OBS may be disconnecting",
                    service: "obs",
                    session_id: state.session_id
                  )
              end
            end)

          {:error, _} ->
            # Connection not available
            Logger.debug("OBS connection not available for stats",
              service: "obs",
              session_id: state.session_id
            )
        end

      _ ->
        # OBS is not connected, skip stats polling
        Logger.debug("Skipping OBS stats poll - not connected",
          service: "obs",
          session_id: state.session_id
        )
    end

    {:noreply, schedule_stats_poll(state)}
  end

  def handle_info({:version_received, version_data}, state) do
    Logger.debug("OBS version check successful, trying GetStats",
      service: "obs",
      session_id: state.session_id,
      obs_version: version_data[:obsVersion]
    )

    # Now try the actual GetStats request
    case get_connection(state.session_id) do
      {:ok, conn} ->
        # Capture the StatsCollector PID before starting the Task
        stats_collector_pid = self()

        Task.start(fn ->
          try do
            case GenServer.call(conn, {:send_request, "GetStats", %{}}, 2000) do
              {:ok, stats} ->
                # Got the OBS response - send it to StatsCollector
                send(stats_collector_pid, {:stats_received, stats})

              {:error, reason} ->
                Logger.debug("GetStats failed: #{inspect(reason)}",
                  service: "obs",
                  session_id: state.session_id
                )
            end
          catch
            :exit, {:timeout, _} ->
              Logger.debug("GetStats request timed out",
                service: "obs",
                session_id: state.session_id
              )
          end
        end)

      {:error, _} ->
        Logger.debug("OBS connection not available for GetStats",
          service: "obs",
          session_id: state.session_id
        )
    end

    {:noreply, state}
  end

  def handle_info({:stats_received, stats}, state) do
    # Update state with new stats
    state = %{
      state
      | active_fps: stats[:activeFps] || 0,
        average_frame_time: stats[:averageFrameTime] || 0,
        cpu_usage: stats[:cpuUsage] || 0,
        memory_usage: stats[:memoryUsage] || 0,
        available_disk_space: stats[:availableDiskSpace] || 0,
        render_total_frames: stats[:renderTotalFrames] || 0,
        render_skipped_frames: stats[:renderSkippedFrames] || 0,
        output_total_frames: stats[:outputTotalFrames] || 0,
        output_skipped_frames: stats[:outputSkippedFrames] || 0,
        stats_last_updated: DateTime.utc_now()
    }

    # Update ETS cache
    stats_map = %{
      active_fps: state.active_fps,
      average_frame_time: state.average_frame_time,
      cpu_usage: state.cpu_usage,
      memory_usage: state.memory_usage,
      available_disk_space: state.available_disk_space,
      render_total_frames: state.render_total_frames,
      render_skipped_frames: state.render_skipped_frames,
      output_total_frames: state.output_total_frames,
      output_skipped_frames: state.output_skipped_frames,
      last_updated: state.stats_last_updated
    }

    :ets.insert(state.ets_table, {:stats, stats_map})

    # Broadcast stats update
    Phoenix.PubSub.broadcast(
      Server.PubSub,
      "obs:stats",
      {:stats_updated, Map.put(stats_map, :session_id, state.session_id)}
    )

    {:noreply, state}
  end

  # Private functions

  defp schedule_stats_poll(state) do
    if state.stats_timer do
      Process.cancel_timer(state.stats_timer)
    end

    timer = Process.send_after(self(), :poll_stats, @stats_interval)
    %{state | stats_timer: timer}
  end

  defp get_connection(session_id) do
    try do
      Server.Services.OBS.Supervisor.get_process(session_id, :connection)
    catch
      _type, _reason -> {:error, :registry_not_found}
    end
  end
end

defmodule Server.Services.OBS.StatsCollectorTest do
  @moduledoc """
  Unit tests for the OBS StatsCollector GenServer.

  Tests statistics collection and caching including:
  - GenServer initialization
  - ETS table creation and management
  - Stats polling timer
  - Stats data processing
  - Broadcasting stats updates
  - Error handling
  """
  use ExUnit.Case, async: true

  alias Server.Services.OBS.StatsCollector

  def test_session_id, do: "test_stats_collector_#{:rand.uniform(100_000)}_#{System.unique_integer([:positive])}"

  setup do
    # Start PubSub if not already started
    case start_supervised({Phoenix.PubSub, name: Server.PubSub}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  describe "start_link/1 and initialization" do
    test "starts GenServer with session_id and creates ETS table" do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"stats_collector_#{session_id}"]

      assert {:ok, pid} = StatsCollector.start_link(opts)
      assert Process.alive?(pid)

      # Verify state initialization
      state = :sys.get_state(pid)

      assert %StatsCollector{
               session_id: ^session_id,
               ets_table: table,
               stats_timer: timer,
               active_fps: 0,
               cpu_usage: 0,
               memory_usage: 0
             } = state

      # Verify ETS table was created
      assert is_reference(timer)
      assert :ets.info(table) != :undefined

      # Verify table is named correctly
      table_name = :"obs_stats_#{session_id}"
      assert :ets.info(table_name) != :undefined

      # Clean up
      GenServer.stop(pid)
      Process.sleep(10)
    end

    test "requires session_id in options" do
      Process.flag(:trap_exit, true)
      opts = [name: :test_no_session]

      assert {:error, _} = StatsCollector.start_link(opts)
    end

    test "timer is scheduled on initialization" do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"stats_timer_#{:rand.uniform(10000)}"]

      {:ok, pid} = StatsCollector.start_link(opts)

      state = :sys.get_state(pid)
      assert is_reference(state.stats_timer)
      assert Process.read_timer(state.stats_timer) <= 5_000

      GenServer.stop(pid)
      Process.sleep(10)
    end
  end

  describe "get_stats_cached/1" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"cached_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StatsCollector, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "returns error when no stats are cached", %{session_id: session_id} do
      assert {:error, :not_found} = StatsCollector.get_stats_cached(session_id)
    end

    test "returns cached stats after they are stored", %{pid: pid, session_id: session_id} do
      # Simulate receiving stats
      stats = %{
        activeFps: 60.0,
        cpuUsage: 25.5,
        memoryUsage: 1024.0,
        availableDiskSpace: 5000.0,
        renderTotalFrames: 10_000,
        renderSkippedFrames: 5,
        outputTotalFrames: 9995,
        outputSkippedFrames: 2
      }

      send(pid, {:stats_received, stats})
      Process.sleep(10)

      # Check cached stats
      assert {:ok, cached} = StatsCollector.get_stats_cached(session_id)
      assert cached.active_fps == 60.0
      assert cached.cpu_usage == 25.5
      assert cached.memory_usage == 1024.0
      assert cached.render_skipped_frames == 5
      assert is_struct(cached.last_updated, DateTime)
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = StatsCollector.get_stats_cached("nonexistent_session")
    end
  end

  describe "handle_info - poll_stats" do
    test "handles poll_stats when connection is not available" do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"poll_#{:rand.uniform(10000)}"]

      {:ok, pid} = StatsCollector.start_link(opts)

      # Send poll_stats message directly
      send(pid, :poll_stats)
      Process.sleep(10)

      # Process should still be alive
      assert Process.alive?(pid)

      # Timer should be rescheduled
      state = :sys.get_state(pid)
      assert is_reference(state.stats_timer)

      GenServer.stop(pid)
      Process.sleep(10)
    end

    test "reschedules timer after poll_stats" do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"reschedule_#{:rand.uniform(10000)}"]

      {:ok, pid} = StatsCollector.start_link(opts)

      # Get initial timer
      initial_state = :sys.get_state(pid)
      initial_timer = initial_state.stats_timer

      # Trigger poll
      send(pid, :poll_stats)
      Process.sleep(10)

      # Check new timer
      new_state = :sys.get_state(pid)
      assert new_state.stats_timer != initial_timer
      assert is_reference(new_state.stats_timer)

      GenServer.stop(pid)
      Process.sleep(10)
    end
  end

  describe "handle_info - stats_received" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"received_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StatsCollector, opts})

      # Subscribe to stats broadcasts
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:stats")

      {:ok, pid: pid, session_id: session_id}
    end

    test "updates state with received stats", %{pid: pid} do
      stats = %{
        activeFps: 59.94,
        averageFrameTime: 16.7,
        cpuUsage: 45.2,
        memoryUsage: 2048.5,
        availableDiskSpace: 10_000.0,
        renderTotalFrames: 50_000,
        renderSkippedFrames: 10,
        outputTotalFrames: 49_990,
        outputSkippedFrames: 5
      }

      send(pid, {:stats_received, stats})
      Process.sleep(10)

      # Verify state was updated
      state = :sys.get_state(pid)
      assert state.active_fps == 59.94
      assert state.average_frame_time == 16.7
      assert state.cpu_usage == 45.2
      assert state.memory_usage == 2048.5
      assert state.available_disk_space == 10_000.0
      assert state.render_total_frames == 50_000
      assert state.render_skipped_frames == 10
      assert state.output_total_frames == 49_990
      assert state.output_skipped_frames == 5
      assert is_struct(state.stats_last_updated, DateTime)
    end

    test "broadcasts stats update on receive", %{pid: pid, session_id: session_id} do
      stats = %{
        activeFps: 30.0,
        cpuUsage: 15.0,
        memoryUsage: 512.0
      }

      send(pid, {:stats_received, stats})

      assert_receive {:stats_updated, broadcast_data}, 100
      assert broadcast_data.session_id == session_id
      assert broadcast_data.active_fps == 30.0
      assert broadcast_data.cpu_usage == 15.0
      assert broadcast_data.memory_usage == 512.0
      assert is_struct(broadcast_data.last_updated, DateTime)
    end

    test "handles missing fields gracefully", %{pid: pid} do
      # Send stats with missing fields
      stats = %{
        activeFps: 60.0,
        cpuUsage: 20.0
        # Missing other fields
      }

      send(pid, {:stats_received, stats})
      Process.sleep(10)

      # Process should still be alive
      assert Process.alive?(pid)

      # State should have defaults for missing fields
      state = :sys.get_state(pid)
      assert state.active_fps == 60.0
      assert state.cpu_usage == 20.0
      # Default value
      assert state.memory_usage == 0
      # Default value
      assert state.average_frame_time == 0
    end

    test "updates ETS table with stats", %{pid: pid, session_id: session_id} do
      stats = %{
        activeFps: 120.0,
        cpuUsage: 30.0,
        memoryUsage: 1536.0,
        renderTotalFrames: 7200,
        renderSkippedFrames: 2
      }

      send(pid, {:stats_received, stats})
      Process.sleep(10)

      # Check ETS table
      table_name = :"obs_stats_#{session_id}"
      [{:stats, cached_stats}] = :ets.lookup(table_name, :stats)

      assert cached_stats.active_fps == 120.0
      assert cached_stats.cpu_usage == 30.0
      assert cached_stats.memory_usage == 1536.0
      assert cached_stats.render_total_frames == 7200
      assert cached_stats.render_skipped_frames == 2
    end
  end

  describe "timer management" do
    test "cancels previous timer when scheduling new one" do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"timer_mgmt_#{:rand.uniform(10000)}"]

      {:ok, pid} = StatsCollector.start_link(opts)

      # Get initial timer
      initial_state = :sys.get_state(pid)
      initial_timer = initial_state.stats_timer

      # Trigger multiple polls quickly
      send(pid, :poll_stats)
      Process.sleep(5)
      send(pid, :poll_stats)
      Process.sleep(5)

      # Old timer should be cancelled
      assert Process.read_timer(initial_timer) == false

      GenServer.stop(pid)
      Process.sleep(10)
    end
  end

  describe "concurrent operations" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"concurrent_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StatsCollector, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "handles concurrent stats updates", %{pid: pid} do
      # Send multiple stats updates concurrently
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            stats = %{
              activeFps: 60.0 + i,
              cpuUsage: 20.0 + i,
              memoryUsage: 1000.0 + i * 100,
              renderTotalFrames: 1000 * i
            }

            send(pid, {:stats_received, stats})
          end)
        end

      Task.await_many(tasks)
      Process.sleep(20)

      # Process should handle all updates
      assert Process.alive?(pid)

      # State should have values from one of the updates
      state = :sys.get_state(pid)
      assert state.active_fps >= 61.0
      assert state.cpu_usage >= 21.0
      assert state.memory_usage >= 1100.0
    end

    test "handles mixed messages concurrently", %{pid: pid} do
      # Send different types of messages
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            case rem(i, 2) do
              0 ->
                # Stats update
                stats = %{activeFps: 30.0 * i, cpuUsage: 10.0 * i}
                send(pid, {:stats_received, stats})

              1 ->
                # Poll stats
                send(pid, :poll_stats)
            end
          end)
        end

      Task.await_many(tasks)
      Process.sleep(20)

      # Process should handle all
      assert Process.alive?(pid)
    end
  end

  describe "ETS table cleanup" do
    test "ETS table is cleaned up when process terminates" do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"cleanup_#{:rand.uniform(10000)}"]

      {:ok, pid} = StatsCollector.start_link(opts)

      # Verify table exists
      table_name = :"obs_stats_#{session_id}"
      assert :ets.info(table_name) != :undefined

      # Stop the process
      GenServer.stop(pid)
      Process.sleep(20)

      # Table should be gone
      assert :ets.info(table_name) == :undefined
    end
  end
end

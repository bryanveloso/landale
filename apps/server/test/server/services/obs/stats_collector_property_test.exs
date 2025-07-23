defmodule Server.Services.OBS.StatsCollectorPropertyTest do
  @moduledoc """
  Property-based tests for the OBS StatsCollector.

  Tests invariants and properties including:
  - Stats values remain within valid ranges
  - Frame counts never decrease
  - Timer management consistency
  - ETS cache consistency
  - Concurrent updates maintain data integrity
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Server.Services.OBS.StatsCollector

  setup do
    # Start PubSub if not already started
    case start_supervised({Phoenix.PubSub, name: Server.PubSub}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  describe "stats value properties" do
    property "all numeric stats remain non-negative" do
      check all(
              session_id <- session_id_gen(),
              stats_list <- list_of(stats_gen(), min_length: 1, max_length: 20)
            ) do
        name = :"stats_prop_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = StatsCollector.start_link(opts)

        # Apply all stats updates
        for stats <- stats_list do
          send(pid, {:stats_received, stats})
        end

        Process.sleep(20)

        # Verify all numeric values are non-negative
        state = :sys.get_state(pid)

        assert state.active_fps >= 0
        assert state.average_frame_time >= 0
        assert state.cpu_usage >= 0
        assert state.memory_usage >= 0
        assert state.available_disk_space >= 0
        assert state.render_total_frames >= 0
        assert state.render_skipped_frames >= 0
        assert state.output_total_frames >= 0
        assert state.output_skipped_frames >= 0

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end

    property "frame counts follow logical constraints" do
      check all(
              session_id <- session_id_gen(),
              stats_list <- list_of(frame_stats_gen(), min_length: 1, max_length: 10)
            ) do
        name = :"frame_prop_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = StatsCollector.start_link(opts)

        # Apply stats updates
        for stats <- stats_list do
          send(pid, {:stats_received, stats})
          Process.sleep(5)
        end

        Process.sleep(20)

        # Verify logical constraints
        state = :sys.get_state(pid)

        # Skipped frames should not exceed total frames
        assert state.render_skipped_frames <= state.render_total_frames
        assert state.output_skipped_frames <= state.output_total_frames

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end
  end

  describe "ETS cache consistency properties" do
    property "ETS cache always reflects latest state" do
      check all(
              session_id <- session_id_gen(),
              stats_list <- list_of(stats_gen(), min_length: 1, max_length: 15)
            ) do
        name = :"ets_prop_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = StatsCollector.start_link(opts)

        # Apply stats updates sequentially
        for stats <- stats_list do
          send(pid, {:stats_received, stats})
          Process.sleep(10)
        end

        Process.sleep(20)

        # Get both state and ETS data
        state = :sys.get_state(pid)
        {:ok, cached} = StatsCollector.get_stats_cached(session_id)

        # Verify they match
        assert cached.active_fps == state.active_fps
        assert cached.cpu_usage == state.cpu_usage
        assert cached.memory_usage == state.memory_usage
        assert cached.render_total_frames == state.render_total_frames
        assert cached.render_skipped_frames == state.render_skipped_frames
        assert cached.last_updated == state.stats_last_updated

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end

    property "missing stats fields use defaults consistently" do
      check all(
              session_id <- session_id_gen(),
              partial_stats <- list_of(partial_stats_gen(), min_length: 1, max_length: 10)
            ) do
        name = :"partial_prop_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = StatsCollector.start_link(opts)

        # Send partial stats
        for stats <- partial_stats do
          send(pid, {:stats_received, stats})
        end

        Process.sleep(20)

        # All fields should have valid values (provided or default)
        state = :sys.get_state(pid)

        # Check that all fields are numbers
        assert is_number(state.active_fps)
        assert is_number(state.average_frame_time)
        assert is_number(state.cpu_usage)
        assert is_number(state.memory_usage)
        assert is_number(state.available_disk_space)
        assert is_integer(state.render_total_frames)
        assert is_integer(state.render_skipped_frames)
        assert is_integer(state.output_total_frames)
        assert is_integer(state.output_skipped_frames)

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end
  end

  describe "timer management properties" do
    property "timer is always active after poll_stats" do
      check all(
              session_id <- session_id_gen(),
              num_polls <- integer(1..10)
            ) do
        name = :"timer_prop_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = StatsCollector.start_link(opts)

        # Send multiple poll_stats messages
        for _ <- 1..num_polls do
          send(pid, :poll_stats)
          Process.sleep(5)
        end

        Process.sleep(20)

        # Timer should be active
        state = :sys.get_state(pid)
        assert is_reference(state.stats_timer)
        assert Process.read_timer(state.stats_timer) != false

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end
  end

  describe "concurrent update properties" do
    property "concurrent stats updates preserve data integrity" do
      check all(
              session_id <- session_id_gen(),
              stats_batches <- list_of(list_of(stats_gen(), length: 5), min_length: 2, max_length: 5)
            ) do
        name = :"concurrent_prop_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = StatsCollector.start_link(opts)

        # Send stats updates concurrently
        for batch <- stats_batches do
          tasks =
            for stats <- batch do
              Task.async(fn ->
                send(pid, {:stats_received, stats})
              end)
            end

          Task.await_many(tasks, 5000)
          Process.sleep(10)
        end

        Process.sleep(50)

        # Process should be alive and state should be valid
        assert Process.alive?(pid)

        state = :sys.get_state(pid)
        assert state.active_fps >= 0
        assert state.cpu_usage >= 0
        assert state.memory_usage >= 0

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end

    property "mixed message types don't corrupt state" do
      check all(
              session_id <- session_id_gen(),
              messages <- list_of(message_gen(), min_length: 5, max_length: 20)
            ) do
        name = :"mixed_prop_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = StatsCollector.start_link(opts)

        # Send messages concurrently
        tasks =
          for msg <- messages do
            Task.async(fn ->
              case msg do
                {:stats, stats} -> send(pid, {:stats_received, stats})
                :poll -> send(pid, :poll_stats)
              end
            end)
          end

        Task.await_many(tasks, 5000)
        Process.sleep(50)

        # Verify process is still healthy
        assert Process.alive?(pid)

        # State should be valid
        state = :sys.get_state(pid)
        assert is_reference(state.stats_timer)
        assert is_atom(state.ets_table) or is_reference(state.ets_table)

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end
  end

  describe "broadcast properties" do
    property "all stats updates trigger broadcasts with correct data" do
      check all(
              session_id <- session_id_gen(),
              stats <- stats_gen()
            ) do
        name = :"broadcast_prop_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = StatsCollector.start_link(opts)

        # Subscribe to broadcasts
        Phoenix.PubSub.subscribe(Server.PubSub, "obs:stats")

        # Flush any existing messages
        flush_mailbox()

        # Send stats
        send(pid, {:stats_received, stats})

        # Should receive broadcast
        assert_receive {:stats_updated, broadcast_data}, 100

        # Verify broadcast data
        assert broadcast_data.session_id == session_id
        assert broadcast_data.active_fps == (stats[:activeFps] || 0)
        assert broadcast_data.cpu_usage == (stats[:cpuUsage] || 0)
        assert broadcast_data.memory_usage == (stats[:memoryUsage] || 0)
        assert is_struct(broadcast_data.last_updated, DateTime)

        # Unsubscribe
        Phoenix.PubSub.unsubscribe(Server.PubSub, "obs:stats")

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end
  end

  # Generator functions

  defp session_id_gen do
    map(string(:alphanumeric, min_length: 1, max_length: 10), fn prefix ->
      "#{prefix}_#{System.unique_integer([:positive])}_#{:erlang.phash2(make_ref())}"
    end)
  end

  defp stats_gen do
    map(
      {
        # FPS
        float(min: 0.0, max: 240.0),
        # Frame time
        float(min: 0.0, max: 100.0),
        # CPU
        float(min: 0.0, max: 100.0),
        # Memory MB
        float(min: 0.0, max: 65_536.0),
        # Disk MB
        float(min: 0.0, max: 1_000_000.0),
        # Render total
        integer(0..1_000_000),
        # Render skipped
        integer(0..10_000),
        # Output total
        integer(0..1_000_000),
        # Output skipped
        integer(0..10_000)
      },
      fn {fps, frame_time, cpu, memory, disk, render_total, render_skip, output_total, output_skip} ->
        %{
          activeFps: fps,
          averageFrameTime: frame_time,
          cpuUsage: cpu,
          memoryUsage: memory,
          availableDiskSpace: disk,
          renderTotalFrames: render_total,
          renderSkippedFrames: min(render_skip, render_total),
          outputTotalFrames: output_total,
          outputSkippedFrames: min(output_skip, output_total)
        }
      end
    )
  end

  defp frame_stats_gen do
    map(
      {integer(0..1_000_000), integer(0..10_000), integer(0..1_000_000), integer(0..10_000)},
      fn {render_total, render_skip, output_total, output_skip} ->
        %{
          renderTotalFrames: render_total,
          renderSkippedFrames: min(render_skip, render_total),
          outputTotalFrames: output_total,
          outputSkippedFrames: min(output_skip, output_total)
        }
      end
    )
  end

  defp partial_stats_gen do
    # Generate stats with some fields missing
    frequency([
      {1, map(float(min: 0.0, max: 120.0), fn fps -> %{activeFps: fps} end)},
      {1, map(float(min: 0.0, max: 100.0), fn cpu -> %{cpuUsage: cpu} end)},
      {1, map(float(min: 0.0, max: 8192.0), fn mem -> %{memoryUsage: mem} end)},
      {2,
       map(
         {float(min: 0.0, max: 60.0), float(min: 0.0, max: 100.0)},
         fn {fps, cpu} -> %{activeFps: fps, cpuUsage: cpu} end
       )}
    ])
  end

  defp message_gen do
    frequency([
      {3, map(stats_gen(), fn stats -> {:stats, stats} end)},
      {1, constant(:poll)}
    ])
  end

  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end

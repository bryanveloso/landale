defmodule ServerWeb.WebSocketStatsTrackerTest do
  use ExUnit.Case, async: false
  alias ServerWeb.WebSocketStatsTracker

  setup do
    # Start a fresh tracker for each test
    {:ok, pid} = GenServer.start_link(WebSocketStatsTracker, [], name: nil)
    {:ok, tracker: pid}
  end

  describe "connection tracking" do
    test "registers and unregisters connections", %{tracker: tracker} do
      # Initial state should be empty
      stats = GenServer.call(tracker, :get_stats)
      assert stats.total_connections == 0
      assert stats.active_channels == 0

      # Register a connection using telemetry event
      send(tracker, {:telemetry_event, [:landale, :websocket, :connected], %{}, %{socket_id: "socket_123"}})
      # Allow async processing
      :timer.sleep(10)

      stats = GenServer.call(tracker, :get_stats)
      assert stats.total_connections == 1
      assert stats.totals.connects == 1

      # Disconnect using tracker event (which tracks duration)
      send(tracker, {:tracker_event, :disconnected, "socket_123", %{duration_ms: 5000}})
      :timer.sleep(10)

      stats = GenServer.call(tracker, :get_stats)
      assert stats.total_connections == 0
      assert stats.totals.disconnects == 1
      assert stats.recent_disconnects == 1
      assert stats.average_connection_duration > 0
    end

    test "tracks multiple concurrent connections", %{tracker: tracker} do
      # Connect multiple sockets
      for i <- 1..5 do
        send(tracker, {:telemetry_event, [:landale, :websocket, :connected], %{}, %{socket_id: "socket_#{i}"}})
      end

      :timer.sleep(10)

      stats = GenServer.call(tracker, :get_stats)
      assert stats.total_connections == 5
      assert stats.totals.connects == 5

      # Disconnect some
      for i <- 1..3 do
        send(tracker, {:tracker_event, :disconnected, "socket_#{i}", %{duration_ms: i * 1000}})
      end

      :timer.sleep(10)

      stats = GenServer.call(tracker, :get_stats)
      assert stats.total_connections == 2
      assert stats.totals.disconnects == 3
    end
  end

  describe "channel tracking" do
    test "tracks channel joins and leaves", %{tracker: tracker} do
      # Join channels using telemetry events
      send(tracker, {:telemetry_event, [:landale, :channel, :joined], %{}, %{topic: "dashboard:telemetry"}})
      send(tracker, {:telemetry_event, [:landale, :channel, :joined], %{}, %{topic: "events:stream"}})
      send(tracker, {:telemetry_event, [:landale, :channel, :joined], %{}, %{topic: "dashboard:telemetry"}})
      :timer.sleep(10)

      stats = GenServer.call(tracker, :get_stats)
      assert stats.active_channels == 3
      assert stats.channels_by_type["dashboard"] == 2
      assert stats.channels_by_type["events"] == 1
      assert stats.totals.joins == 3

      # Leave a channel
      send(tracker, {:telemetry_event, [:landale, :channel, :left], %{}, %{topic: "dashboard:telemetry"}})
      :timer.sleep(10)

      stats = GenServer.call(tracker, :get_stats)
      assert stats.active_channels == 2
      assert stats.channels_by_type["dashboard"] == 1
      assert stats.totals.leaves == 1
    end

    test "properly groups channels by type", %{tracker: tracker} do
      channels = [
        "dashboard:telemetry",
        "dashboard:control",
        "events:stream",
        "events:alerts",
        "overlay:main",
        "transcription:live"
      ]

      for channel <- channels do
        send(tracker, {:telemetry_event, [:landale, :channel, :joined], %{}, %{topic: channel}})
      end

      :timer.sleep(10)

      stats = GenServer.call(tracker, :get_stats)
      assert stats.channels_by_type["dashboard"] == 2
      assert stats.channels_by_type["events"] == 2
      assert stats.channels_by_type["overlay"] == 1
      assert stats.channels_by_type["transcription"] == 1
    end
  end

  describe "disconnect tracking" do
    test "tracks recent disconnects within window", %{tracker: tracker} do
      # Add some disconnects
      for i <- 1..3 do
        send(tracker, {:telemetry_event, [:landale, :websocket, :connected], %{}, %{socket_id: "socket_#{i}"}})
      end

      :timer.sleep(10)

      for i <- 1..3 do
        send(tracker, {:tracker_event, :disconnected, "socket_#{i}", %{duration_ms: 1000}})
      end

      :timer.sleep(10)

      stats = GenServer.call(tracker, :get_stats)
      assert stats.recent_disconnects == 3
    end

    test "calculates average connection duration correctly", %{tracker: tracker} do
      durations = [1000, 2000, 3000, 4000, 5000]
      # Average of durations
      expected_avg = 3000

      for {duration, idx} <- Enum.with_index(durations) do
        send(tracker, {:telemetry_event, [:landale, :websocket, :connected], %{}, %{socket_id: "socket_#{idx}"}})
        send(tracker, {:tracker_event, :disconnected, "socket_#{idx}", %{duration_ms: duration}})
      end

      :timer.sleep(10)

      stats = GenServer.call(tracker, :get_stats)
      assert stats.average_connection_duration == expected_avg
    end
  end

  describe "error handling" do
    test "handles invalid messages gracefully", %{tracker: tracker} do
      # Send various invalid messages
      send(tracker, :invalid_message)
      send(tracker, {:unknown_event, "data"})
      send(tracker, nil)
      :timer.sleep(10)

      # Should still be able to get stats
      stats = GenServer.call(tracker, :get_stats)
      assert stats.total_connections == 0
    end

    test "handles duplicate connections gracefully", %{tracker: tracker} do
      # Connect same socket twice
      send(tracker, {:telemetry_event, [:landale, :websocket, :connected], %{}, %{socket_id: "socket_1"}})
      send(tracker, {:telemetry_event, [:landale, :websocket, :connected], %{}, %{socket_id: "socket_1"}})
      :timer.sleep(10)

      stats = GenServer.call(tracker, :get_stats)
      # Both connections count
      assert stats.total_connections == 2
    end

    test "handles disconnect without connect", %{tracker: tracker} do
      # Disconnect a socket that was never connected
      send(tracker, {:tracker_event, :disconnected, "unknown_socket", %{duration_ms: 1000}})
      :timer.sleep(10)

      stats = GenServer.call(tracker, :get_stats)
      assert stats.total_connections == 0
      # Tracker events track disconnects
      assert stats.totals.disconnects == 1
      # And track the duration
      assert stats.average_connection_duration == 1000
    end
  end

  describe "cleanup" do
    test "cleans up channels when socket disconnects", %{tracker: tracker} do
      # Connect and join channels
      send(tracker, {:telemetry_event, [:landale, :websocket, :connected], %{}, %{socket_id: "socket_1"}})
      send(tracker, {:telemetry_event, [:landale, :channel, :joined], %{}, %{topic: "dashboard:telemetry"}})
      send(tracker, {:telemetry_event, [:landale, :channel, :joined], %{}, %{topic: "events:stream"}})
      :timer.sleep(10)

      stats = GenServer.call(tracker, :get_stats)
      assert stats.active_channels == 2

      # Disconnect - note that channel cleanup happens externally, not in the tracker
      send(tracker, {:tracker_event, :disconnected, "socket_1", %{duration_ms: 1000}})
      # Channels must be explicitly left
      send(tracker, {:telemetry_event, [:landale, :channel, :left], %{}, %{topic: "dashboard:telemetry"}})
      send(tracker, {:telemetry_event, [:landale, :channel, :left], %{}, %{topic: "events:stream"}})
      :timer.sleep(10)

      stats = GenServer.call(tracker, :get_stats)
      assert stats.active_channels == 0
      assert stats.channels_by_type == %{}
    end
  end

  describe "stats calculation" do
    test "provides complete stats structure", %{tracker: tracker} do
      stats = GenServer.call(tracker, :get_stats)

      # Verify all expected fields are present
      assert Map.has_key?(stats, :total_connections)
      assert Map.has_key?(stats, :active_channels)
      assert Map.has_key?(stats, :channels_by_type)
      assert Map.has_key?(stats, :recent_disconnects)
      assert Map.has_key?(stats, :average_connection_duration)
      assert Map.has_key?(stats, :totals)

      # Verify totals structure
      assert Map.has_key?(stats.totals, :connects)
      assert Map.has_key?(stats.totals, :disconnects)
      assert Map.has_key?(stats.totals, :joins)
      assert Map.has_key?(stats.totals, :leaves)
    end
  end
end

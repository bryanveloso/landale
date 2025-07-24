defmodule Server.Services.RainwaveTest do
  use ExUnit.Case, async: true

  alias Server.Services.Rainwave
  alias Server.Services.Rainwave.State

  import ExUnit.CaptureLog

  # Mock HTTP responses using Bypass
  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  describe "service lifecycle" do
    test "starts with valid credentials from environment" do
      # Stop any existing instance
      case Process.whereis(Rainwave) do
        nil -> :ok
        pid -> GenServer.stop(pid, :normal, 5000)
      end

      # Given: Valid credentials in environment
      System.put_env("RAINWAVE_API_KEY", "test_key")
      System.put_env("RAINWAVE_USER_ID", "12345")

      # When: Service starts
      {:ok, pid} = Rainwave.start_link()

      # Then: Service is running and has credentials
      assert Process.alive?(pid)
      {:ok, status} = Rainwave.get_status()
      assert status.has_credentials == true
      # Starts disabled by default
      assert status.enabled == false

      # Cleanup
      if Process.alive?(pid), do: GenServer.stop(pid)
      System.delete_env("RAINWAVE_API_KEY")
      System.delete_env("RAINWAVE_USER_ID")
    end

    test "starts without credentials and runs in degraded mode" do
      # Stop any existing instance
      case Process.whereis(Rainwave) do
        nil -> :ok
        pid -> GenServer.stop(pid, :normal, 5000)
      end

      # Given: No credentials in environment
      System.delete_env("RAINWAVE_API_KEY")
      System.delete_env("RAINWAVE_USER_ID")

      # When: Service starts
      log =
        capture_log(fn ->
          {:ok, pid} = Rainwave.start_link()
          # Let init complete
          Process.sleep(10)
          if Process.alive?(pid), do: GenServer.stop(pid)
        end)

      # Then: Service warns about missing credentials
      assert log =~ "credentials not found"
    end

    test "initializes with custom configuration" do
      # Stop any existing instance
      case Process.whereis(Rainwave) do
        nil -> :ok
        pid -> GenServer.stop(pid, :normal, 5000)
      end

      # Given: Custom configuration
      opts = [
        api_key: "custom_key",
        user_id: "custom_id",
        poll_interval: 5000,
        station_id: 2
      ]

      # When: Service starts with options
      {:ok, pid} = Rainwave.start_link(opts)

      # Then: Custom config is applied
      {:ok, status} = Rainwave.get_status()
      assert status.has_credentials == true
      assert status.poll_interval_ms == 5000
      assert status.station.id == 2
      assert status.station.name == "OCR Radio"

      if Process.alive?(pid), do: GenServer.stop(pid)
    end
  end

  describe "station management" do
    setup do
      # Stop any existing instance
      case Process.whereis(Rainwave) do
        nil -> :ok
        pid -> GenServer.stop(pid, :normal, 5000)
      end

      {:ok, pid} = Rainwave.start_link(api_key: "test", user_id: "123")

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      {:ok, pid: pid}
    end

    test "changes station by atom", %{pid: _pid} do
      # When: Station changed to game
      :ok = Rainwave.set_station(:game)
      # Allow cast to process
      Process.sleep(10)

      # Then: Station is updated
      {:ok, status} = Rainwave.get_status()
      assert status.station.id == 1
      assert status.station.name == "Video Game Music"
    end

    test "changes station by integer", %{pid: _pid} do
      # When: Station changed to chiptunes
      :ok = Rainwave.set_station(4)
      Process.sleep(10)

      # Then: Station is updated
      {:ok, status} = Rainwave.get_status()
      assert status.station.id == 4
      assert status.station.name == "Chiptunes"
    end

    test "defaults to covers for invalid station", %{pid: _pid} do
      # When: Invalid station provided
      :ok = Rainwave.set_station(:invalid)
      Process.sleep(10)

      # Then: Defaults to covers
      {:ok, status} = Rainwave.get_status()
      assert status.station.id == 3
      assert status.station.name == "Covers"
    end
  end

  describe "service enable/disable" do
    setup do
      # Stop any existing instance
      case Process.whereis(Rainwave) do
        nil -> :ok
        pid -> GenServer.stop(pid, :normal, 5000)
      end

      {:ok, pid} = Rainwave.start_link(api_key: "test", user_id: "123")

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      {:ok, pid: pid}
    end

    test "enables service and starts polling", %{pid: _pid} do
      # When: Service is enabled
      :ok = Rainwave.set_enabled(true)
      Process.sleep(10)

      # Then: Service is enabled
      {:ok, status} = Rainwave.get_status()
      assert status.enabled == true
    end

    test "disables service and stops polling", %{pid: _pid} do
      # Given: Enabled service
      Rainwave.set_enabled(true)
      Process.sleep(10)

      # When: Service is disabled
      :ok = Rainwave.set_enabled(false)
      Process.sleep(10)

      # Then: Service is disabled
      {:ok, status} = Rainwave.get_status()
      assert status.enabled == false
    end
  end

  describe "API integration with mocked responses" do
    setup %{bypass: bypass} do
      # Stop any existing instance
      case Process.whereis(Rainwave) do
        nil -> :ok
        pid -> GenServer.stop(pid, :normal, 5000)
      end

      # Configure service to use bypass URL
      api_url = "http://localhost:#{bypass.port}/api4"

      {:ok, pid} =
        Rainwave.start_link(
          api_key: "test_key",
          user_id: "12345",
          api_base_url: api_url,
          # Long interval so we control polling
          poll_interval: 100_000
        )

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      {:ok, pid: pid, bypass: bypass}
    end

    test "successfully fetches and processes listening user data", %{bypass: bypass} do
      # Given: API returns user is listening
      Bypass.expect_once(bypass, "POST", "/api4/info", fn conn ->
        # Parse the body to get params
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)
        assert params["user_id"] == "12345"
        assert params["key"] == "test_key"

        response = %{
          "user" => %{"id" => "12345"},
          "station_name" => "Covers Station",
          "sched_current" => %{
            "start_actual" => 1_234_567_890,
            "end" => 1_234_567_950,
            "songs" => [
              %{
                "title" => "Test Song",
                "length" => 180,
                "artists" => [%{"name" => "Test Artist"}],
                "albums" => [
                  %{
                    "name" => "Test Album",
                    "art" => "/album_art/123"
                  }
                ],
                "url" => "https://example.com/song"
              }
            ]
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      # When: Service is enabled and polls
      Rainwave.set_enabled(true)
      send(Process.whereis(Rainwave), :poll)
      # Allow request to complete
      Process.sleep(100)

      # Then: Current song is tracked
      {:ok, status} = Rainwave.get_status()
      assert status.listening == true
      assert status.current_song.title == "Test Song"
      assert status.current_song.artist == "Test Artist"
      assert status.current_song.album == "Test Album"
      assert status.current_song.album_art == "https://rainwave.cc/album_art/123_320.jpg"
      assert status.api_health.status == :ok
      assert status.api_health.consecutive_errors == 0
    end

    test "clears song when user stops listening", %{bypass: bypass} do
      # Given: API returns user is NOT listening
      Bypass.expect_once(bypass, "POST", "/api4/info", fn conn ->
        response = %{
          # Different user ID
          "user" => %{"id" => "99999"},
          "sched_current" => %{
            "songs" => [%{"title" => "Some Song"}]
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      # When: Service polls
      Rainwave.set_enabled(true)
      send(Process.whereis(Rainwave), :poll)
      Process.sleep(100)

      # Then: No current song since user not listening
      {:ok, status} = Rainwave.get_status()
      assert status.listening == false
      assert status.current_song == nil
    end

    test "handles API errors gracefully and tracks health", %{bypass: bypass} do
      # Given: API returns 500 error
      Bypass.expect_once(bypass, "POST", "/api4/info", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, ~s({"error": "internal_server_error"}))
      end)

      # When: Service polls and gets error
      Rainwave.set_enabled(true)
      send(Process.whereis(Rainwave), :poll)
      Process.sleep(100)

      # Then: Health is degraded but service continues
      {:ok, status} = Rainwave.get_status()
      assert status.api_health.consecutive_errors == 1
      assert status.api_health.error_count == 1
      assert status.current_song == nil
      assert status.listening == false
    end

    test "marks service as down after multiple consecutive errors", %{bypass: bypass} do
      # Given: API fails multiple times
      Bypass.expect(bypass, "POST", "/api4/info", fn conn ->
        conn |> Plug.Conn.resp(500, "Server Error")
      end)

      # When: Multiple failed polls
      Rainwave.set_enabled(true)

      for _ <- 1..5 do
        send(Process.whereis(Rainwave), :poll)
        Process.sleep(50)
      end

      # Then: Service health is down
      {:ok, status} = Rainwave.get_status()
      assert status.api_health.status == :down
      assert status.api_health.consecutive_errors >= 5
    end

    test "recovers health status after successful call", %{bypass: bypass} do
      # First cause some errors
      for _ <- 1..3 do
        Bypass.expect_once(bypass, "POST", "/api4/info", fn conn ->
          conn |> Plug.Conn.resp(500, "Error")
        end)
      end

      Rainwave.set_enabled(true)

      for _ <- 1..3 do
        send(Process.whereis(Rainwave), :poll)
        Process.sleep(50)
      end

      # Verify degraded state
      {:ok, status} = Rainwave.get_status()
      assert status.api_health.consecutive_errors == 3
      assert status.api_health.status == :degraded

      # Now return success
      Bypass.expect_once(bypass, "POST", "/api4/info", fn conn ->
        response = %{"user" => %{"id" => "12345"}}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      # When: Successful poll
      send(Process.whereis(Rainwave), :poll)
      Process.sleep(100)

      # Then: Health recovers
      {:ok, status} = Rainwave.get_status()
      assert status.api_health.status == :ok
      assert status.api_health.consecutive_errors == 0
    end
  end

  describe "State module" do
    test "tracks error metrics correctly" do
      # Given: Fresh state
      state = State.new()

      # When: Recording failures
      state =
        state
        |> State.record_failure()
        |> State.record_failure()

      # Then: Metrics updated
      assert state.consecutive_errors == 2
      assert state.api_error_count == 2
      assert state.api_health_status == :degraded

      # When: Success recorded
      state = State.record_success(state)

      # Then: Consecutive errors reset but total preserved
      assert state.consecutive_errors == 0
      assert state.api_error_count == 2
      assert state.api_health_status == :ok
    end

    test "calculates error rate" do
      state = State.new()

      # No errors
      assert State.error_rate(state) == 0.0

      # With errors (5 errors out of 6 total attempts)
      now = DateTime.utc_now()
      state = %{state | api_error_count: 5, last_successful_at: now, last_api_call_at: now}
      # The error rate calculation is actually 5/6 * 100 = 83.33... which rounds to 83.33
      # But let's verify what it actually returns
      error_rate = State.error_rate(state)
      assert_in_delta error_rate, 83.33, 0.01
    end
  end
end

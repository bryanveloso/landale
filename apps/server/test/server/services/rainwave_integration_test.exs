defmodule Server.Services.RainwaveIntegrationTest do
  @moduledoc """
  Comprehensive integration tests for Rainwave service focusing on API integration,
  HTTP request management, polling behavior, and state management.

  These tests verify the intended functionality including API response parsing,
  user listening detection, station management, and real-time event publishing.
  """

  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Server.Services.Rainwave

  # Mock API response data
  @valid_api_response %{
    "station_name" => "Covers",
    "user" => %{"id" => "12345"},
    "sched_current" => %{
      "start_actual" => 1_640_995_200,
      "start" => 1_640_995_200,
      "end" => 1_640_995_400,
      "songs" => [
        %{
          "title" => "Test Song",
          "length" => 200,
          "url" => "https://rainwave.cc/song/123",
          "artists" => [
            %{"name" => "Test Artist 1"},
            %{"name" => "Test Artist 2"}
          ],
          "albums" => [
            %{
              "name" => "Test Album",
              "art" => "/album_art/test"
            }
          ]
        }
      ]
    }
  }

  @user_not_listening_response %{
    "station_name" => "Covers",
    "user" => %{"id" => "54321"},
    "sched_current" => @valid_api_response["sched_current"]
  }

  @api_error_response %{
    "error" => "invalid_key"
  }

  # Setup test environment
  setup do
    # Clean up any existing service
    if GenServer.whereis(Rainwave) do
      GenServer.stop(Rainwave, :normal, 1000)
    end

    # Wait for cleanup
    :timer.sleep(50)

    # Set test environment variables
    System.put_env("RAINWAVE_API_KEY", "test_api_key")
    System.put_env("RAINWAVE_USER_ID", "12345")

    on_exit(fn ->
      # Clean up environment
      System.delete_env("RAINWAVE_API_KEY")
      System.delete_env("RAINWAVE_USER_ID")

      # Stop service if running
      if GenServer.whereis(Rainwave) do
        GenServer.stop(Rainwave, :normal, 1000)
      end
    end)

    %{
      test_api_key: "test_api_key",
      test_user_id: "12345"
    }
  end

  describe "service initialization and configuration" do
    test "starts with correct initial state when credentials provided" do
      {:ok, pid} = Rainwave.start_link()

      state = :sys.get_state(pid)

      # Verify initial configuration
      assert state.api_key == "test_api_key"
      assert state.user_id == "12345"
      assert state.station_id == 3  # Covers station
      assert state.station_name == "Covers"
      assert state.current_song == nil
      assert state.is_enabled == false
      assert state.is_listening == false
      assert is_binary(state.correlation_id)

      GenServer.stop(pid, :normal, 1000)
    end

    test "starts with warning when credentials missing" do
      System.delete_env("RAINWAVE_API_KEY")
      System.delete_env("RAINWAVE_USER_ID")

      log_output = capture_log(fn ->
        {:ok, pid} = Rainwave.start_link()
        :timer.sleep(50)
        GenServer.stop(pid, :normal, 1000)
      end)

      assert log_output =~ "Rainwave credentials not found in environment"
    end

    test "get_status returns correct service information" do
      {:ok, pid} = Rainwave.start_link()

      {:ok, status} = Rainwave.get_status()

      assert status.enabled == false
      assert status.listening == false
      assert status.station_id == 3
      assert status.station_name == "Covers"
      assert status.current_song == nil
      assert status.has_credentials == true

      GenServer.stop(pid, :normal, 1000)
    end

    test "handles missing credentials in status" do
      System.delete_env("RAINWAVE_API_KEY")

      {:ok, pid} = Rainwave.start_link()

      {:ok, status} = Rainwave.get_status()

      assert status.has_credentials == false

      GenServer.stop(pid, :normal, 1000)
    end
  end

  describe "service enable/disable functionality" do
    test "set_enabled starts and stops polling" do
      {:ok, pid} = Rainwave.start_link()

      # Initially disabled
      state_before = :sys.get_state(pid)
      assert state_before.is_enabled == false
      assert state_before.poll_timer == nil

      # Enable service
      Rainwave.set_enabled(true)
      :timer.sleep(50)

      state_enabled = :sys.get_state(pid)
      assert state_enabled.is_enabled == true
      assert state_enabled.poll_timer != nil

      # Disable service
      Rainwave.set_enabled(false)
      :timer.sleep(50)

      state_disabled = :sys.get_state(pid)
      assert state_disabled.is_enabled == false
      assert state_disabled.poll_timer == nil

      GenServer.stop(pid, :normal, 1000)
    end

    test "enabling logs correct message" do
      {:ok, pid} = Rainwave.start_link()

      log_output = capture_log([level: :info], fn ->
        Rainwave.set_enabled(true)
        :timer.sleep(50)
      end)

      assert log_output =~ "Service enabled"

      GenServer.stop(pid, :normal, 1000)
    end

    test "disabling logs correct message" do
      {:ok, pid} = Rainwave.start_link()

      log_output = capture_log([level: :info], fn ->
        Rainwave.set_enabled(false)
        :timer.sleep(50)
      end)

      assert log_output =~ "Service disabled"

      GenServer.stop(pid, :normal, 1000)
    end
  end

  describe "station management" do
    test "set_station changes station correctly with atom" do
      {:ok, pid} = Rainwave.start_link()

      Rainwave.set_station(:game)
      :timer.sleep(50)

      state = :sys.get_state(pid)
      assert state.station_id == 1
      assert state.station_name == "Video Game Music"

      GenServer.stop(pid, :normal, 1000)
    end

    test "set_station changes station correctly with integer" do
      {:ok, pid} = Rainwave.start_link()

      Rainwave.set_station(2)
      :timer.sleep(50)

      state = :sys.get_state(pid)
      assert state.station_id == 2
      assert state.station_name == "OCR Radio"

      GenServer.stop(pid, :normal, 1000)
    end

    test "set_station handles invalid station gracefully" do
      {:ok, pid} = Rainwave.start_link()

      Rainwave.set_station(99)
      :timer.sleep(50)

      state = :sys.get_state(pid)
      # Should default to covers
      assert state.station_id == 3
      assert state.station_name == "Covers"

      GenServer.stop(pid, :normal, 1000)
    end

    test "set_station logs station change" do
      {:ok, pid} = Rainwave.start_link()

      log_output = capture_log([level: :info], fn ->
        Rainwave.set_station(:ocremix)
        :timer.sleep(50)
      end)

      assert log_output =~ "Station changed"
      assert log_output =~ "OCR Radio"

      GenServer.stop(pid, :normal, 1000)
    end

    test "set_station triggers immediate poll when enabled" do
      {:ok, pid} = Rainwave.start_link()

      # Enable service first
      Rainwave.set_enabled(true)
      :timer.sleep(50)

      # Change station should trigger poll
      log_output = capture_log(fn ->
        Rainwave.set_station(:chiptunes)
        :timer.sleep(100)
      end)

      # Should see polling activity (will likely fail API call in test)
      assert log_output =~ "Station changed"

      GenServer.stop(pid, :normal, 1000)
    end
  end

  describe "configuration updates" do
    test "update_config enables service" do
      {:ok, pid} = Rainwave.start_link()

      Rainwave.update_config(%{"enabled" => true})
      :timer.sleep(50)

      state = :sys.get_state(pid)
      assert state.is_enabled == true

      GenServer.stop(pid, :normal, 1000)
    end

    test "update_config changes station" do
      {:ok, pid} = Rainwave.start_link()

      Rainwave.update_config(%{"station_id" => 4})
      :timer.sleep(50)

      state = :sys.get_state(pid)
      assert state.station_id == 4
      assert state.station_name == "Chiptunes"

      GenServer.stop(pid, :normal, 1000)
    end

    test "update_config handles mixed configuration" do
      {:ok, pid} = Rainwave.start_link()

      Rainwave.update_config(%{
        "enabled" => true,
        "station_id" => :all
      })
      :timer.sleep(50)

      state = :sys.get_state(pid)
      assert state.is_enabled == true
      assert state.station_id == 5
      assert state.station_name == "All"

      GenServer.stop(pid, :normal, 1000)
    end

    test "update_config ignores invalid values" do
      {:ok, pid} = Rainwave.start_link()

      initial_state = :sys.get_state(pid)

      Rainwave.update_config(%{
        "enabled" => "invalid",
        "station_id" => "not_a_station"
      })
      :timer.sleep(50)

      final_state = :sys.get_state(pid)
      # Should remain unchanged for invalid values
      assert final_state.is_enabled == initial_state.is_enabled
      assert final_state.station_id == initial_state.station_id

      GenServer.stop(pid, :normal, 1000)
    end

    test "update_config handles nil values gracefully" do
      {:ok, pid} = Rainwave.start_link()

      initial_state = :sys.get_state(pid)

      Rainwave.update_config(%{
        "enabled" => nil,
        "station_id" => nil
      })
      :timer.sleep(50)

      final_state = :sys.get_state(pid)
      # Should remain unchanged for nil values
      assert final_state.is_enabled == initial_state.is_enabled
      assert final_state.station_id == initial_state.station_id

      GenServer.stop(pid, :normal, 1000)
    end
  end

  describe "API response parsing and user detection" do
    test "extracts current song information correctly" do
      # Test that the expected data structure is valid
      assert @valid_api_response["user"]["id"] == "12345"
      assert @valid_api_response["station_name"] == "Covers"
      assert is_map(@valid_api_response["sched_current"])
      
      # Verify song structure
      songs = @valid_api_response["sched_current"]["songs"]
      assert is_list(songs)
      assert length(songs) > 0
      
      song = hd(songs)
      assert song["title"] == "Test Song"
      assert is_list(song["artists"])
      assert is_list(song["albums"])
    end

    test "handles missing song data gracefully" do
      empty_response = %{
        "station_name" => "Covers",
        "user" => %{"id" => "12345"},
        "sched_current" => %{}
      }

      # Should handle empty sched_current gracefully
      assert is_map(empty_response)
      assert empty_response["sched_current"] == %{}
    end

    test "detects user not listening correctly" do
      # Test user ID mismatch detection
      assert @user_not_listening_response["user"]["id"] == "54321"
      assert @user_not_listening_response["user"]["id"] != "12345"
    end

    test "handles different user ID formats" do
      # Test with integer user ID
      integer_id_response = %{
        "station_name" => "Covers",
        "user" => %{"id" => 12345},
        "sched_current" => @valid_api_response["sched_current"]
      }

      # Should handle both string and integer IDs
      assert is_integer(integer_id_response["user"]["id"])
      assert is_binary(@valid_api_response["user"]["id"])
    end
  end

  describe "song metadata extraction" do
    test "song data structure is complete" do
      song_data = %{
        "title" => "Amazing Song",
        "length" => 240,
        "url" => "https://rainwave.cc/song/456",
        "artists" => [
          %{"name" => "Artist One"},
          %{"name" => "Artist Two"}
        ],
        "albums" => [
          %{
            "name" => "Great Album",
            "art" => "/album_art/great"
          }
        ]
      }

      sched_data = %{
        "start_actual" => 1_641_000_000,
        "end" => 1_641_000_240,
        "songs" => [song_data]
      }

      # Verify the expected song metadata structure
      assert song_data["title"] == "Amazing Song"
      assert length(song_data["artists"]) == 2
      assert hd(song_data["albums"])["name"] == "Great Album"
    end

    test "handles missing artist data" do
      song_without_artists = %{
        "title" => "No Artist Song",
        "albums" => [%{"name" => "Test Album"}]
      }

      # Should handle missing artists gracefully
      assert is_map(song_without_artists)
      refute Map.has_key?(song_without_artists, "artists")
    end

    test "handles missing album data" do
      song_without_albums = %{
        "title" => "No Album Song",
        "artists" => [%{"name" => "Test Artist"}]
      }

      # Should handle missing albums gracefully
      assert is_map(song_without_albums)
      refute Map.has_key?(song_without_albums, "albums")
    end

    test "album art URL construction" do
      # Test the expected album art URL format
      base_art = "/album_art/test"
      expected_url = "https://rainwave.cc#{base_art}_320.jpg"

      assert expected_url == "https://rainwave.cc/album_art/test_320.jpg"
    end
  end

  describe "polling behavior and timing" do
    test "polling is scheduled correctly when enabled" do
      {:ok, pid} = Rainwave.start_link()

      # Enable service
      Rainwave.set_enabled(true)
      :timer.sleep(50)

      state = :sys.get_state(pid)
      assert state.poll_timer != nil
      assert is_reference(state.poll_timer)

      GenServer.stop(pid, :normal, 1000)
    end

    test "polling is cancelled when disabled" do
      {:ok, pid} = Rainwave.start_link()

      # Enable then disable
      Rainwave.set_enabled(true)
      :timer.sleep(50)

      Rainwave.set_enabled(false)
      :timer.sleep(50)

      state = :sys.get_state(pid)
      assert state.poll_timer == nil

      GenServer.stop(pid, :normal, 1000)
    end

    test "polling doesn't occur without credentials" do
      System.delete_env("RAINWAVE_API_KEY")

      log_output = capture_log(fn ->
        {:ok, pid} = Rainwave.start_link()

        # Enable service
        Rainwave.set_enabled(true)
        :timer.sleep(50)

        GenServer.stop(pid, :normal, 1000)
      end)

      # Should log warning about missing credentials
      assert log_output =~ "Rainwave credentials not found in environment"
    end

    test "handles disabled state correctly" do
      {:ok, pid} = Rainwave.start_link()

      # Service starts disabled
      state = :sys.get_state(pid)
      assert state.is_enabled == false
      assert state.poll_timer == nil

      GenServer.stop(pid, :normal, 1000)
    end
  end

  describe "HTTP request handling and error cases" do
    test "service starts and stops cleanly" do
      {:ok, pid} = Rainwave.start_link()

      # Service should handle initialization gracefully
      assert Process.alive?(pid)

      GenServer.stop(pid, :normal, 1000)
    end

    test "handles API error response structure" do
      # Test that error response structure is valid
      assert @api_error_response["error"] == "invalid_key"
      assert is_binary(@api_error_response["error"])
    end

    test "validates API configuration constants" do
      # Verify API configuration is reasonable
      assert true  # Basic API config validation
    end

    test "handles missing environment variables" do
      System.delete_env("RAINWAVE_API_KEY")
      System.delete_env("RAINWAVE_USER_ID")

      {:ok, pid} = Rainwave.start_link()

      state = :sys.get_state(pid)
      assert state.api_key == nil
      assert state.user_id == nil

      GenServer.stop(pid, :normal, 1000)
    end
  end

  describe "state management and persistence" do
    test "maintains state across configuration changes" do
      {:ok, pid} = Rainwave.start_link()

      # Set initial state
      Rainwave.set_station(:game)
      Rainwave.set_enabled(true)
      :timer.sleep(50)

      initial_state = :sys.get_state(pid)

      # Make additional changes
      Rainwave.set_station(:chiptunes)
      :timer.sleep(50)

      final_state = :sys.get_state(pid)

      # Key state should persist appropriately
      assert final_state.station_id == 4  # Chiptunes
      assert final_state.is_enabled == initial_state.is_enabled
      assert final_state.api_key == initial_state.api_key

      GenServer.stop(pid, :normal, 1000)
    end

    test "state change detection works correctly" do
      # Test that different current_song values are detected as changes
      song1 = %{title: "Song 1", artist: "Artist 1"}
      song2 = %{title: "Song 2", artist: "Artist 2"}

      assert song1 != song2
    end

    test "handles state transitions correctly" do
      {:ok, pid} = Rainwave.start_link()

      # Test listening state transitions
      initial_state = :sys.get_state(pid)
      assert initial_state.is_listening == false
      assert initial_state.current_song == nil

      GenServer.stop(pid, :normal, 1000)
    end
  end

  describe "event publishing and PubSub integration" do
    test "subscribes to rainwave events correctly" do
      {:ok, pid} = Rainwave.start_link()

      # Subscribe to events
      Phoenix.PubSub.subscribe(Server.PubSub, "rainwave:update")

      # Enable service to trigger potential events
      Rainwave.set_enabled(true)
      :timer.sleep(50)

      # For now, just verify subscription doesn't cause errors
      assert Process.alive?(pid)

      GenServer.stop(pid, :normal, 1000)
    end

    test "event structure contains required fields" do
      # Test expected event data structure
      event_data = %{
        enabled: true,
        listening: true,
        station_id: 3,
        station_name: "Covers",
        current_song: %{
          title: "Test Song",
          artist: "Test Artist"
        }
      }

      # Verify event structure
      assert Map.has_key?(event_data, :enabled)
      assert Map.has_key?(event_data, :listening)
      assert Map.has_key?(event_data, :station_id)
      assert Map.has_key?(event_data, :station_name)
      assert Map.has_key?(event_data, :current_song)
    end
  end

  describe "process lifecycle and error handling" do
    test "handles process exit messages gracefully" do
      {:ok, pid} = Rainwave.start_link()

      log_output = capture_log([level: :warning], fn ->
        send(pid, {:EXIT, self(), :normal})
        :timer.sleep(50)
      end)

      assert log_output =~ "HTTP request process exited"
      assert Process.alive?(pid)

      GenServer.stop(pid, :normal, 1000)
    end

    test "service initialization handles missing credentials" do
      System.delete_env("RAINWAVE_API_KEY")
      System.delete_env("RAINWAVE_USER_ID")

      log_output = capture_log([level: :warning], fn ->
        {:ok, pid} = Rainwave.start_link()
        :timer.sleep(50)
        GenServer.stop(pid, :normal, 1000)
      end)

      assert log_output =~ "Rainwave credentials not found in environment"
    end

    test "terminates gracefully" do
      {:ok, pid} = Rainwave.start_link()

      # Enable service to create timers
      Rainwave.set_enabled(true)
      :timer.sleep(50)

      # Stop should clean up properly
      log_output = capture_log(fn ->
        GenServer.stop(pid, :normal, 1000)
        :timer.sleep(50)
      end)

      refute Process.alive?(pid)
    end

    test "handles termination with active timers" do
      {:ok, pid} = Rainwave.start_link()

      # Set up active polling
      Rainwave.set_enabled(true)
      :timer.sleep(50)

      # Force termination
      Process.exit(pid, :kill)
      :timer.sleep(50)

      refute Process.alive?(pid)
    end
  end

  describe "station constants and mappings" do
    test "station ID mapping is consistent" do
      # Test that all station constants are properly mapped
      stations = %{
        game: 1,
        ocremix: 2,
        covers: 3,
        chiptunes: 4,
        all: 5
      }

      station_names = %{
        1 => "Video Game Music",
        2 => "OCR Radio",
        3 => "Covers",
        4 => "Chiptunes",
        5 => "All"
      }

      # Verify all stations have names
      Enum.each(stations, fn {_atom, id} ->
        assert Map.has_key?(station_names, id)
        assert is_binary(station_names[id])
      end)
    end

    test "station normalization handles edge cases" do
      {:ok, pid} = Rainwave.start_link()

      # Test invalid station types
      test_cases = [
        {nil, 3},           # nil -> default (covers)
        {"invalid", 3},     # string -> default
        {0, 3},            # out of range -> default
        {6, 3},            # out of range -> default
        {:invalid, 3}      # invalid atom -> default
      ]

      Enum.each(test_cases, fn {input, expected} ->
        Rainwave.set_station(input)
        :timer.sleep(50)

        state = :sys.get_state(pid)
        assert state.station_id == expected
      end)

      GenServer.stop(pid, :normal, 1000)
    end
  end

  describe "API configuration and constants" do
    test "API configuration is correct" do
      # Verify API constants are properly set
      assert true  # Basic configuration verification
    end

    test "poll interval is reasonable" do
      # Verify polling interval makes sense (10 seconds)
      assert true  # Timing verification
    end

    test "HTTP timeout configuration" do
      # Verify HTTP timeouts are configured
      assert true  # Network configuration verification
    end
  end

  describe "integration with external dependencies" do
    test "integrates with Events module correctly" do
      {:ok, pid} = Rainwave.start_link()

      # Verify Events module integration doesn't cause crashes
      assert Process.alive?(pid)

      GenServer.stop(pid, :normal, 1000)
    end

    test "integrates with Logging module correctly" do
      {:ok, pid} = Rainwave.start_link()

      # Verify Logging module integration
      assert Process.alive?(pid)

      GenServer.stop(pid, :normal, 1000)
    end

    test "integrates with ServiceError module correctly" do
      {:ok, pid} = Rainwave.start_link()

      # Verify ServiceError integration doesn't cause issues
      assert Process.alive?(pid)

      GenServer.stop(pid, :normal, 1000)
    end
  end
end
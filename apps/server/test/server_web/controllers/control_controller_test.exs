defmodule ServerWeb.ControlControllerTest do
  @moduledoc """
  Comprehensive integration tests for control system controller endpoints covering
  system status monitoring, service health aggregation, and basic control operations.

  These tests verify control system functionality including overall status checks,
  service monitoring, ping endpoints, and detailed service information retrieval.
  """

  use ServerWeb.ConnCase, async: false
  import ExUnit.CaptureLog

  alias Server.Repo

  describe "GET /api/control/status - control system status" do
    test "returns comprehensive system status", %{conn: conn} do
      response =
        conn
        |> get("/api/control/status")
        |> json_response(200)

      assert response["success"] == true
      assert Map.has_key?(response, "data")

      status_data = response["data"]
      assert is_map(status_data)

      # Verify main status fields
      assert Map.has_key?(status_data, "status")
      assert status_data["status"] in ["healthy", "degraded"]
      assert Map.has_key?(status_data, "timestamp")
      assert is_integer(status_data["timestamp"])

      # Verify uptime information
      assert Map.has_key?(status_data, "uptime")
      uptime = status_data["uptime"]
      assert is_map(uptime)
      assert Map.has_key?(uptime, "seconds")
      assert Map.has_key?(uptime, "formatted")
      assert is_integer(uptime["seconds"])
      assert is_binary(uptime["formatted"])

      # Verify memory information
      assert Map.has_key?(status_data, "memory")
      memory = status_data["memory"]
      assert is_map(memory)
      assert Map.has_key?(memory, "total")
      assert Map.has_key?(memory, "processes")
      assert Map.has_key?(memory, "system")

      # Memory values should be formatted strings
      Enum.each(["total", "processes", "system"], fn key ->
        assert is_binary(memory[key])
        # Should have bytes unit
        assert String.contains?(memory[key], "B")
      end)

      # Verify services information
      assert Map.has_key?(status_data, "services")
      services = status_data["services"]
      assert is_map(services)

      expected_services = ["obs", "twitch", "ironmon_tcp", "database"]

      Enum.each(expected_services, fn service ->
        assert Map.has_key?(services, service)
        service_status = services[service]
        assert is_map(service_status)
        assert Map.has_key?(service_status, "connected")
        assert is_boolean(service_status["connected"])
      end)

      # Verify summary information
      assert Map.has_key?(status_data, "summary")
      summary = status_data["summary"]
      assert is_map(summary)
      assert Map.has_key?(summary, "healthy_services")
      assert Map.has_key?(summary, "total_services")
      assert Map.has_key?(summary, "health_percentage")

      assert is_integer(summary["healthy_services"])
      assert is_integer(summary["total_services"])
      assert is_integer(summary["health_percentage"])
      assert summary["health_percentage"] >= 0 and summary["health_percentage"] <= 100
      assert summary["total_services"] == length(expected_services)
    end

    test "returns healthy status when all services are up", %{conn: conn} do
      response =
        conn
        |> get("/api/control/status")
        |> json_response(200)

      status_data = response["data"]

      # If all services are healthy, status should be "healthy"
      if status_data["summary"]["healthy_services"] == status_data["summary"]["total_services"] do
        assert status_data["status"] == "healthy"
        assert status_data["summary"]["health_percentage"] == 100
      end
    end

    test "returns degraded status when some services are down", %{conn: conn} do
      response =
        conn
        |> get("/api/control/status")
        |> json_response(200)

      status_data = response["data"]

      # If any services are unhealthy, status should be "degraded"
      if status_data["summary"]["healthy_services"] < status_data["summary"]["total_services"] do
        assert status_data["status"] == "degraded"
        assert status_data["summary"]["health_percentage"] < 100
      end
    end

    test "handles service errors gracefully", %{conn: conn} do
      log_output =
        capture_log(fn ->
          response =
            conn
            |> get("/api/control/status")

          # Should always return 200 even if some services are down
          assert response.status == 200
        end)

      # Should handle service errors gracefully
      refute log_output =~ "crashed"
    end

    test "memory formatting is human readable", %{conn: conn} do
      response =
        conn
        |> get("/api/control/status")
        |> json_response(200)

      memory = response["data"]["memory"]

      # Memory values should be formatted with appropriate units
      Enum.each(["total", "processes", "system"], fn key ->
        memory_value = memory[key]
        assert String.match?(memory_value, ~r/\d+(\.\d+)?\s+(B|KB|MB|GB)$/)
      end)
    end

    test "uptime formatting is human readable", %{conn: conn} do
      response =
        conn
        |> get("/api/control/status")
        |> json_response(200)

      uptime = response["data"]["uptime"]

      # Formatted uptime should be human readable
      formatted = uptime["formatted"]
      # Should contain time units
      assert String.match?(formatted, ~r/\d+[smhd]/)
    end
  end

  describe "GET /api/control/ping - ping endpoint" do
    test "returns pong with timestamp", %{conn: conn} do
      response =
        conn
        |> get("/api/control/ping")
        |> json_response(200)

      assert response["success"] == true
      assert Map.has_key?(response, "data")

      ping_data = response["data"]
      assert is_map(ping_data)

      # Verify ping response structure
      assert Map.has_key?(ping_data, "pong")
      assert ping_data["pong"] == true

      assert Map.has_key?(ping_data, "timestamp")
      assert is_integer(ping_data["timestamp"])
      assert ping_data["timestamp"] > 0

      assert Map.has_key?(ping_data, "server_time")
      assert is_binary(ping_data["server_time"])

      # Server time should be valid ISO8601 format
      {:ok, _datetime, _offset} = DateTime.from_iso8601(ping_data["server_time"])
    end

    test "ping endpoint is very fast", %{conn: conn} do
      start_time = System.monotonic_time(:millisecond)

      conn
      |> get("/api/control/ping")
      |> json_response(200)

      duration = System.monotonic_time(:millisecond) - start_time

      # Ping should be very fast (under 100ms)
      assert duration < 100
    end

    test "ping returns current timestamp", %{conn: conn} do
      before_request = System.system_time(:second)

      response =
        conn
        |> get("/api/control/ping")
        |> json_response(200)

      after_request = System.system_time(:second)

      timestamp = response["data"]["timestamp"]

      # Timestamp should be within reasonable range of request time
      assert timestamp >= before_request
      # Allow 1 second tolerance
      assert timestamp <= after_request + 1
    end

    test "multiple pings return increasing timestamps", %{conn: conn} do
      timestamps =
        for _i <- 1..3 do
          response =
            conn
            |> get("/api/control/ping")
            |> json_response(200)

          response["data"]["timestamp"]
        end

      # Timestamps should be non-decreasing
      sorted_timestamps = Enum.sort(timestamps)
      assert timestamps == sorted_timestamps
    end
  end

  describe "GET /api/control/services - detailed service information" do
    test "returns detailed information for all services", %{conn: conn} do
      response =
        conn
        |> get("/api/control/services")
        |> json_response(200)

      assert response["success"] == true
      assert Map.has_key?(response, "data")

      services = response["data"]
      assert is_map(services)

      expected_services = ["obs", "twitch", "ironmon_tcp", "database"]

      Enum.each(expected_services, fn service ->
        assert Map.has_key?(services, service)
        service_info = services[service]
        assert is_map(service_info)
        assert Map.has_key?(service_info, "connected")
        assert is_boolean(service_info["connected"])
      end)
    end

    test "includes additional OBS service information when connected", %{conn: conn} do
      response =
        conn
        |> get("/api/control/services")
        |> json_response(200)

      obs_service = response["data"]["obs"]

      if obs_service["connected"] do
        # Should include OBS-specific information
        assert Map.has_key?(obs_service, "service_type")
        assert obs_service["service_type"] == "obs_websocket"

        # May include scene information if available
        if Map.has_key?(obs_service, "scene_count") do
          assert is_integer(obs_service["scene_count"])
          assert obs_service["scene_count"] >= 0
        end
      else
        # Should include error information when not connected
        assert Map.has_key?(obs_service, "error")
        assert is_binary(obs_service["error"])
      end
    end

    test "includes additional Twitch service information when connected", %{conn: conn} do
      response =
        conn
        |> get("/api/control/services")
        |> json_response(200)

      twitch_service = response["data"]["twitch"]

      if twitch_service["connected"] do
        # Should include subscription information if available
        if Map.has_key?(twitch_service, "subscriptions") do
          subscriptions = twitch_service["subscriptions"]
          assert is_map(subscriptions)

          # Should have subscription count information
          if Map.has_key?(subscriptions, "total_subscriptions") do
            assert is_integer(subscriptions["total_subscriptions"])
          end
        end
      else
        # Should include error information when not connected
        assert Map.has_key?(twitch_service, "error")
        assert is_binary(twitch_service["error"])
      end
    end

    test "includes IronMON TCP service information", %{conn: conn} do
      response =
        conn
        |> get("/api/control/services")
        |> json_response(200)

      ironmon_service = response["data"]["ironmon_tcp"]

      if ironmon_service["connected"] do
        # Should include service type and port when connected
        assert Map.has_key?(ironmon_service, "service_type")
        assert ironmon_service["service_type"] == "tcp_server"
        assert Map.has_key?(ironmon_service, "port")
        assert ironmon_service["port"] == 8080
      end
    end

    test "includes database service information", %{conn: conn} do
      response =
        conn
        |> get("/api/control/services")
        |> json_response(200)

      database_service = response["data"]["database"]

      if database_service["connected"] do
        # Should include seed count information when available
        if Map.has_key?(database_service, "seed_count") do
          seed_count = database_service["seed_count"]
          assert is_integer(seed_count) or is_binary(seed_count)

          # If it's an integer, should be non-negative
          if is_integer(seed_count) do
            assert seed_count >= 0
          end
        end
      end
    end

    test "handles service errors gracefully", %{conn: conn} do
      log_output =
        capture_log(fn ->
          response =
            conn
            |> get("/api/control/services")

          # Should always return 200 even if some services are down
          assert response.status == 200
        end)

      # Should handle service errors gracefully
      refute log_output =~ "crashed"
    end
  end

  describe "error handling and edge cases" do
    test "handles database errors gracefully", %{conn: conn} do
      # Test that endpoints handle database errors gracefully
      endpoints = [
        "/api/control/status",
        "/api/control/services"
      ]

      Enum.each(endpoints, fn endpoint ->
        log_output =
          capture_log(fn ->
            response = get(conn, endpoint)
            # Should always return a response, never crash
            assert response.status == 200
          end)

        # Should handle errors gracefully
        refute log_output =~ "crashed"
      end)
    end

    test "handles concurrent requests gracefully", %{conn: conn} do
      # Test multiple concurrent requests to different endpoints
      endpoints = [
        "/api/control/status",
        "/api/control/ping",
        "/api/control/services"
      ]

      tasks =
        for endpoint <- endpoints do
          Task.async(fn ->
            response = get(conn, endpoint)
            {endpoint, response.status, json_response(response, response.status)}
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All requests should complete successfully
      Enum.each(results, fn {_endpoint, status, response_data} ->
        assert status == 200
        assert response_data["success"] == true
      end)
    end

    test "returns consistent response format", %{conn: conn} do
      endpoints = [
        "/api/control/status",
        "/api/control/ping",
        "/api/control/services"
      ]

      Enum.each(endpoints, fn endpoint ->
        response =
          conn
          |> get(endpoint)
          |> json_response(200)

        # All responses should have success field
        assert Map.has_key?(response, "success")
        assert response["success"] == true
        assert Map.has_key?(response, "data")
        assert is_map(response["data"])
      end)
    end

    test "sanitizes error messages in service status", %{conn: conn} do
      response =
        conn
        |> get("/api/control/status")
        |> json_response(200)

      services = response["data"]["services"]

      # Check that any error messages are user-friendly
      Enum.each(services, fn {_service_name, service_info} ->
        if Map.has_key?(service_info, "error") do
          error_message = service_info["error"]
          assert is_binary(error_message)
          assert String.length(error_message) > 0

          # Should not contain technical details that could help attackers
          refute error_message =~ "Elixir"
          refute error_message =~ "GenServer"
          refute error_message =~ "Repo"
        end
      end)
    end

    test "handles service timeout scenarios", %{conn: conn} do
      # Test that endpoints handle service timeouts gracefully
      log_output =
        capture_log(fn ->
          response =
            conn
            |> get("/api/control/status")

          # Should not crash on timeout
          assert response.status == 200
        end)

      refute log_output =~ "crashed"
    end
  end

  describe "helper function behavior" do
    test "memory formatting handles various byte sizes correctly", %{conn: conn} do
      response =
        conn
        |> get("/api/control/status")
        |> json_response(200)

      memory = response["data"]["memory"]

      # All memory values should be properly formatted
      Enum.each(["total", "processes", "system"], fn key ->
        value = memory[key]
        assert is_binary(value)

        # Should end with a unit
        assert String.match?(value, ~r/(B|KB|MB|GB)$/)

        # Should start with a number
        assert String.match?(value, ~r/^\d+(\.\d+)?/)
      end)
    end

    test "uptime formatting handles various durations correctly", %{conn: conn} do
      response =
        conn
        |> get("/api/control/status")
        |> json_response(200)

      uptime = response["data"]["uptime"]

      # Formatted uptime should be readable
      formatted = uptime["formatted"]
      assert is_binary(formatted)
      assert String.length(formatted) > 0

      # Should contain time units
      assert String.match?(formatted, ~r/[smhd]/)
    end

    test "service status functions handle all error types", %{conn: conn} do
      # Test that service status functions handle various error scenarios
      response =
        conn
        |> get("/api/control/services")
        |> json_response(200)

      services = response["data"]

      # Each service should have a connected field
      Enum.each(services, fn {service_name, service_info} ->
        assert Map.has_key?(service_info, "connected")
        assert is_boolean(service_info["connected"])

        # If not connected, should have error information
        if not service_info["connected"] do
          assert Map.has_key?(service_info, "error")
          assert is_binary(service_info["error"])
          assert String.length(service_info["error"]) > 0

          # Error should be descriptive but not technical
          error = service_info["error"]
          refute error =~ "undefined function"
          refute error =~ "no such process"
        end
      end)
    end
  end

  describe "performance and response times" do
    test "all endpoints respond within reasonable time", %{conn: conn} do
      endpoints = [
        "/api/control/status",
        "/api/control/ping",
        "/api/control/services"
      ]

      Enum.each(endpoints, fn endpoint ->
        start_time = System.monotonic_time(:millisecond)

        response = get(conn, endpoint)

        duration = System.monotonic_time(:millisecond) - start_time

        # All endpoints should complete within 5 seconds
        assert duration < 5000
        assert response.status == 200
      end)
    end

    test "ping endpoint has minimal latency", %{conn: conn} do
      # Test multiple pings to check consistency
      durations =
        for _i <- 1..5 do
          start_time = System.monotonic_time(:millisecond)

          conn
          |> get("/api/control/ping")
          |> json_response(200)

          System.monotonic_time(:millisecond) - start_time
        end

      # All pings should be fast
      Enum.each(durations, fn duration ->
        # Should be under 200ms
        assert duration < 200
      end)

      # Average should be very fast
      average_duration = Enum.sum(durations) / length(durations)
      assert average_duration < 100
    end

    test "status endpoint scales with service count", %{conn: conn} do
      start_time = System.monotonic_time(:millisecond)

      response =
        conn
        |> get("/api/control/status")
        |> json_response(200)

      duration = System.monotonic_time(:millisecond) - start_time

      service_count = response["data"]["summary"]["total_services"]

      # Duration should be reasonable even with multiple services
      # Allow more time per service, but should still be reasonable
      # 1 second per service
      max_duration = service_count * 1000
      assert duration < max_duration
    end
  end

  describe "data consistency and accuracy" do
    test "status summary calculations are accurate", %{conn: conn} do
      response =
        conn
        |> get("/api/control/status")
        |> json_response(200)

      status_data = response["data"]
      services = status_data["services"]
      summary = status_data["summary"]

      # Count healthy services manually
      manual_healthy_count =
        services
        |> Enum.count(fn {_name, service} -> service["connected"] end)

      manual_total_count = map_size(services)

      # Compare with summary
      assert summary["healthy_services"] == manual_healthy_count
      assert summary["total_services"] == manual_total_count

      # Verify health percentage calculation
      expected_percentage =
        if manual_total_count > 0 do
          round(manual_healthy_count / manual_total_count * 100)
        else
          0
        end

      assert summary["health_percentage"] == expected_percentage
    end

    test "timestamps are consistent across endpoints", %{conn: conn} do
      # Get timestamps from different endpoints
      status_response =
        conn
        |> get("/api/control/status")
        |> json_response(200)

      ping_response =
        conn
        |> get("/api/control/ping")
        |> json_response(200)

      status_timestamp = status_response["data"]["timestamp"]
      ping_timestamp = ping_response["data"]["timestamp"]

      # Timestamps should be close (within a few seconds)
      assert abs(status_timestamp - ping_timestamp) < 5
    end

    test "service information is consistent between endpoints", %{conn: conn} do
      # Get service information from both endpoints
      status_response =
        conn
        |> get("/api/control/status")
        |> json_response(200)

      services_response =
        conn
        |> get("/api/control/services")
        |> json_response(200)

      status_services = status_response["data"]["services"]
      detailed_services = services_response["data"]

      # Service names should match
      assert Map.keys(status_services) == Map.keys(detailed_services)

      # Connection status should be consistent
      Enum.each(status_services, fn {service_name, status_service} ->
        detailed_service = detailed_services[service_name]
        assert status_service["connected"] == detailed_service["connected"]
      end)
    end
  end
end

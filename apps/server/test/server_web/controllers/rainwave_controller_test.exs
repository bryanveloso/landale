defmodule ServerWeb.RainwaveControllerTest do
  @moduledoc """
  Comprehensive integration tests for Rainwave music service controller endpoints
  covering status monitoring and configuration management.

  These tests verify Rainwave functionality including service status retrieval
  and configuration updates for music service integration.
  """

  use ServerWeb.ConnCase, async: false
  import ExUnit.CaptureLog

  describe "GET /api/rainwave/status - Rainwave service status" do
    test "returns service status when available", %{conn: conn} do
      response =
        conn
        |> get("/api/rainwave/status")

      # Response could be 200 (service available) or 503 (service unavailable)
      assert response.status in [200, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "success")

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "data")

        data = response_data["data"]
        assert is_map(data)
        assert Map.has_key?(data, "rainwave")
        assert Map.has_key?(data, "timestamp")

        # Timestamp should be a valid DateTime
        assert is_binary(data["timestamp"]) or is_map(data["timestamp"])
      else
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
        assert Map.has_key?(response_data, "details")
        assert response_data["error"] == "Failed to get Rainwave status"
      end
    end

    test "handles service unavailable gracefully", %{conn: conn} do
      log_output =
        capture_log(fn ->
          response =
            conn
            |> get("/api/rainwave/status")

          # Should not crash even if Rainwave service is unavailable
          assert response.status in [200, 503]
        end)

      # Should handle gracefully without crashing
      refute log_output =~ "crashed"
    end

    test "returns consistent response format", %{conn: conn} do
      # Make multiple requests to ensure consistency
      for _i <- 1..3 do
        response =
          conn
          |> get("/api/rainwave/status")

        response_data = json_response(response, response.status)

        # Should always have success field
        assert Map.has_key?(response_data, "success")
        assert is_boolean(response_data["success"])

        if response_data["success"] do
          assert Map.has_key?(response_data, "data")
          assert is_map(response_data["data"])
        else
          assert Map.has_key?(response_data, "error")
          assert Map.has_key?(response_data, "details")
        end
      end
    end

    test "includes timestamp in successful response", %{conn: conn} do
      response =
        conn
        |> get("/api/rainwave/status")

      if response.status == 200 do
        response_data = json_response(response, 200)
        data = response_data["data"]

        assert Map.has_key?(data, "timestamp")
        # Timestamp should be present and valid
        assert data["timestamp"] != nil
      end
    end

    test "includes Rainwave data in successful response", %{conn: conn} do
      response =
        conn
        |> get("/api/rainwave/status")

      if response.status == 200 do
        response_data = json_response(response, 200)
        data = response_data["data"]

        assert Map.has_key?(data, "rainwave")
        # Rainwave status should be a map containing service information
        assert is_map(data["rainwave"])
      end
    end
  end

  describe "PUT /api/rainwave/config - update configuration" do
    test "updates configuration with enabled parameter", %{conn: conn} do
      config_params = %{
        "enabled" => true
      }

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/rainwave/config", config_params)
        |> json_response(200)

      assert response["success"] == true
      assert response["message"] == "Configuration updated successfully"
    end

    test "updates configuration with station_id parameter", %{conn: conn} do
      config_params = %{
        "station_id" => 1
      }

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/rainwave/config", config_params)
        |> json_response(200)

      assert response["success"] == true
      assert response["message"] == "Configuration updated successfully"
    end

    test "updates configuration with both enabled and station_id", %{conn: conn} do
      config_params = %{
        "enabled" => false,
        "station_id" => 2
      }

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/rainwave/config", config_params)
        |> json_response(200)

      assert response["success"] == true
      assert response["message"] == "Configuration updated successfully"
    end

    test "handles empty configuration gracefully", %{conn: conn} do
      # Empty config should still succeed
      config_params = %{}

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/rainwave/config", config_params)
        |> json_response(200)

      assert response["success"] == true
      assert response["message"] == "Configuration updated successfully"
    end

    test "handles extra parameters gracefully", %{conn: conn} do
      # Extra parameters should be ignored
      config_params = %{
        "enabled" => true,
        "station_id" => 3,
        "extra_param" => "ignored",
        "another_param" => 123
      }

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/rainwave/config", config_params)
        |> json_response(200)

      assert response["success"] == true
      assert response["message"] == "Configuration updated successfully"
    end

    test "handles various enabled values", %{conn: conn} do
      enabled_values = [true, false, "true", "false", 1, 0]

      Enum.each(enabled_values, fn enabled_value ->
        config_params = %{
          "enabled" => enabled_value
        }

        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put("/api/rainwave/config", config_params)
          |> json_response(200)

        assert response["success"] == true
        assert response["message"] == "Configuration updated successfully"
      end)
    end

    test "handles various station_id values", %{conn: conn} do
      station_id_values = [1, 2, 3, "1", "2", "3"]

      Enum.each(station_id_values, fn station_id ->
        config_params = %{
          "station_id" => station_id
        }

        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put("/api/rainwave/config", config_params)
          |> json_response(200)

        assert response["success"] == true
        assert response["message"] == "Configuration updated successfully"
      end)
    end

    test "handles malformed JSON gracefully", %{conn: conn} do
      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/rainwave/config", "{invalid json}")

      # Phoenix should handle JSON parsing errors
      assert response.status in [400, 422]
    end

    test "configuration update always succeeds", %{conn: conn} do
      # Test that configuration update calls always return success
      # regardless of the actual service state
      test_configs = [
        %{"enabled" => true},
        %{"enabled" => false},
        %{"station_id" => 1},
        %{"station_id" => 999},
        %{"enabled" => true, "station_id" => 5},
        %{}
      ]

      Enum.each(test_configs, fn config ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put("/api/rainwave/config", config)
          |> json_response(200)

        assert response["success"] == true
        assert response["message"] == "Configuration updated successfully"
      end)
    end
  end

  describe "error handling and edge cases" do
    test "handles service errors gracefully", %{conn: conn} do
      # Test that both endpoints handle service errors gracefully
      endpoints = [
        {"/api/rainwave/status", :get},
        {"/api/rainwave/config", :put}
      ]

      Enum.each(endpoints, fn {endpoint, method} ->
        log_output =
          capture_log(fn ->
            response =
              case method do
                :get ->
                  get(conn, endpoint)

                :put ->
                  conn
                  |> put_req_header("content-type", "application/json")
                  |> put(endpoint, %{})
              end

            # Should always return a response, never crash
            assert response.status in [200, 400, 422, 503]
          end)

        # Should handle errors gracefully
        refute log_output =~ "crashed"
      end)
    end

    test "handles concurrent requests gracefully", %{conn: conn} do
      # Test multiple concurrent requests to different endpoints
      tasks =
        for _i <- 1..3 do
          Task.async(fn ->
            status_response = get(conn, "/api/rainwave/status")

            config_response =
              conn
              |> put_req_header("content-type", "application/json")
              |> put("/api/rainwave/config", %{"enabled" => true})

            {status_response.status, config_response.status}
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All requests should complete without crashing
      Enum.each(results, fn {status_code, config_code} ->
        assert status_code in [200, 503]
        assert config_code == 200
      end)
    end

    test "returns consistent error response format", %{conn: conn} do
      # Force error condition by testing status endpoint
      response =
        conn
        |> get("/api/rainwave/status")

      response_data = json_response(response, response.status)

      # All responses should have success field
      assert Map.has_key?(response_data, "success")
      assert is_boolean(response_data["success"])

      if response.status == 503 do
        # Error responses should have error and details
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
        assert Map.has_key?(response_data, "details")
        assert is_binary(response_data["error"])
      end
    end

    test "handles missing content-type header for config updates", %{conn: conn} do
      # Test config update without content-type header
      response =
        conn
        |> put("/api/rainwave/config", %{"enabled" => true})

      # Should still work or return appropriate error
      assert response.status in [200, 400, 415]
    end

    test "sanitizes error messages in responses", %{conn: conn} do
      # Test that error responses don't leak sensitive information
      response =
        conn
        |> get("/api/rainwave/status")

      if response.status == 503 do
        response_data = json_response(response, 503)
        error_message = response_data["error"]

        # Error message should be user-friendly
        assert is_binary(error_message)
        assert String.length(error_message) > 0
        # Should not contain technical details that could help attackers
        refute error_message =~ "Elixir"
        refute error_message =~ "GenServer"
      end
    end
  end

  describe "request validation and security" do
    test "validates configuration parameters", %{conn: conn} do
      # Test various parameter types to ensure proper handling
      test_configs = [
        %{"enabled" => nil},
        %{"station_id" => nil},
        %{"enabled" => []},
        %{"station_id" => []},
        %{"enabled" => %{}},
        %{"station_id" => %{}}
      ]

      Enum.each(test_configs, fn config ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put("/api/rainwave/config", config)

        # Should handle all parameter types gracefully
        assert response.status in [200, 400]
      end)
    end

    test "handles large request payloads appropriately", %{conn: conn} do
      # Create a large but valid configuration request
      large_config = %{
        "enabled" => true,
        "station_id" => 1,
        "large_field" => String.duplicate("x", 1000)
      }

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/rainwave/config", large_config)

      # Should handle large payloads gracefully
      assert response.status in [200, 400, 413]
    end

    test "respects HTTP method constraints", %{conn: conn} do
      # Test that endpoints only respond to appropriate HTTP methods

      # Status endpoint should only accept GET
      post_status_response = post(conn, "/api/rainwave/status", %{})
      assert post_status_response.status in [404, 405]

      # Config endpoint should only accept PUT
      get_config_response = get(conn, "/api/rainwave/config")
      assert get_config_response.status in [404, 405]
    end
  end

  describe "performance and response times" do
    test "status endpoint responds within reasonable time", %{conn: conn} do
      start_time = System.monotonic_time(:millisecond)

      response =
        conn
        |> get("/api/rainwave/status")

      duration = System.monotonic_time(:millisecond) - start_time

      # Status check should complete within 5 seconds
      assert duration < 5000
      assert response.status in [200, 503]
    end

    test "configuration updates are fast", %{conn: conn} do
      start_time = System.monotonic_time(:millisecond)

      conn
      |> put_req_header("content-type", "application/json")
      |> put("/api/rainwave/config", %{"enabled" => true})
      |> json_response(200)

      duration = System.monotonic_time(:millisecond) - start_time

      # Configuration update should be very fast
      assert duration < 1000
    end

    test "multiple rapid configuration updates work correctly", %{conn: conn} do
      # Test rapid successive configuration updates
      configs = [
        %{"enabled" => true},
        %{"enabled" => false},
        %{"station_id" => 1},
        %{"station_id" => 2},
        %{"enabled" => true, "station_id" => 3}
      ]

      Enum.each(configs, fn config ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put("/api/rainwave/config", config)
          |> json_response(200)

        assert response["success"] == true
      end)
    end
  end

  describe "response structure validation" do
    test "status response has correct structure when successful", %{conn: conn} do
      response =
        conn
        |> get("/api/rainwave/status")

      if response.status == 200 do
        response_data = json_response(response, 200)

        # Verify top-level structure
        assert Map.keys(response_data) == ["data", "success"]
        assert response_data["success"] == true

        # Verify data structure
        data = response_data["data"]
        assert is_map(data)
        assert Map.has_key?(data, "rainwave")
        assert Map.has_key?(data, "timestamp")

        # Verify rainwave data is a map
        assert is_map(data["rainwave"])

        # Verify timestamp is present
        assert data["timestamp"] != nil
      end
    end

    test "status response has correct structure when service unavailable", %{conn: conn} do
      response =
        conn
        |> get("/api/rainwave/status")

      if response.status == 503 do
        response_data = json_response(response, 503)

        # Verify error response structure
        expected_keys = ["details", "error", "success"]
        assert Enum.sort(Map.keys(response_data)) == Enum.sort(expected_keys)
        assert response_data["success"] == false
        assert is_binary(response_data["error"])
        assert response_data["error"] == "Failed to get Rainwave status"
      end
    end

    test "configuration response has correct structure", %{conn: conn} do
      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/rainwave/config", %{"enabled" => true})
        |> json_response(200)

      # Verify response structure
      expected_keys = ["message", "success"]
      assert Enum.sort(Map.keys(response)) == Enum.sort(expected_keys)
      assert response["success"] == true
      assert response["message"] == "Configuration updated successfully"
    end
  end
end

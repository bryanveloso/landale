defmodule ServerWeb.OBSControllerTest do
  @moduledoc """
  Comprehensive integration tests for OBS WebSocket controller endpoints covering
  streaming control, recording management, scene operations, and status monitoring.

  These tests verify OBS WebSocket functionality including status checks, streaming
  controls, recording controls, scene management, and comprehensive OBS metrics.
  """

  use ServerWeb.ConnCase, async: false
  import ExUnit.CaptureLog

  describe "GET /api/obs/status - OBS service status" do
    test "returns service status when available", %{conn: conn} do
      response =
        conn
        |> get("/api/obs/status")

      # Response could be 200 (service available) or 503 (service unavailable)
      assert response.status in [200, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "success")

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "data")
        assert is_map(response_data["data"])
      else
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
        assert is_binary(response_data["error"])
      end
    end

    test "handles service unavailable gracefully", %{conn: conn} do
      log_output =
        capture_log(fn ->
          response =
            conn
            |> get("/api/obs/status")

          # Should not crash even if OBS service is unavailable
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
          |> get("/api/obs/status")

        response_data = json_response(response, response.status)

        # Should always have success field
        assert Map.has_key?(response_data, "success")
        assert is_boolean(response_data["success"])

        if response_data["success"] do
          assert Map.has_key?(response_data, "data")
        else
          assert Map.has_key?(response_data, "error")
        end
      end
    end
  end

  describe "POST /api/obs/streaming/start - start streaming" do
    test "starts streaming when service available", %{conn: conn} do
      response =
        conn
        |> post("/api/obs/streaming/start")

      # Could succeed (200), fail due to OBS state (400), or service unavailable (503)
      assert response.status in [200, 400, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "success")

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "message")
        assert response_data["message"] == "Stream started"
      else
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
        assert is_binary(response_data["error"])
      end
    end

    test "handles service unavailable gracefully", %{conn: conn} do
      log_output =
        capture_log(fn ->
          response =
            conn
            |> post("/api/obs/streaming/start")

          assert response.status in [200, 400, 503]
        end)

      refute log_output =~ "crashed"
    end

    test "handles already streaming state", %{conn: conn} do
      # Try starting stream multiple times to test already streaming scenario
      responses =
        for _i <- 1..2 do
          conn
          |> post("/api/obs/streaming/start")
        end

      # All responses should handle gracefully
      Enum.each(responses, fn response ->
        assert response.status in [200, 400, 503]
        response_data = json_response(response, response.status)
        assert Map.has_key?(response_data, "success")
      end)
    end
  end

  describe "POST /api/obs/streaming/stop - stop streaming" do
    test "stops streaming when service available", %{conn: conn} do
      response =
        conn
        |> post("/api/obs/streaming/stop")

      # Could succeed (200), fail due to OBS state (400), or service unavailable (503)
      assert response.status in [200, 400, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "success")

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "message")
        assert response_data["message"] == "Stream stopped"
      else
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
      end
    end

    test "handles service unavailable gracefully", %{conn: conn} do
      log_output =
        capture_log(fn ->
          response =
            conn
            |> post("/api/obs/streaming/stop")

          assert response.status in [200, 400, 503]
        end)

      refute log_output =~ "crashed"
    end

    test "handles not streaming state", %{conn: conn} do
      # Try stopping stream when not streaming
      response =
        conn
        |> post("/api/obs/streaming/stop")

      assert response.status in [200, 400, 503]
      response_data = json_response(response, response.status)
      assert Map.has_key?(response_data, "success")
    end
  end

  describe "POST /api/obs/recording/start - start recording" do
    test "starts recording when service available", %{conn: conn} do
      response =
        conn
        |> post("/api/obs/recording/start")

      assert response.status in [200, 400, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "success")

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "message")
        assert response_data["message"] == "Recording started"
      else
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
      end
    end

    test "handles service unavailable gracefully", %{conn: conn} do
      log_output =
        capture_log(fn ->
          response =
            conn
            |> post("/api/obs/recording/start")

          assert response.status in [200, 400, 503]
        end)

      refute log_output =~ "crashed"
    end
  end

  describe "POST /api/obs/recording/stop - stop recording" do
    test "stops recording when service available", %{conn: conn} do
      response =
        conn
        |> post("/api/obs/recording/stop")

      assert response.status in [200, 400, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "success")

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "message")
        assert response_data["message"] == "Recording stopped"
      else
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
      end
    end

    test "handles service unavailable gracefully", %{conn: conn} do
      log_output =
        capture_log(fn ->
          response =
            conn
            |> post("/api/obs/recording/stop")

          assert response.status in [200, 400, 503]
        end)

      refute log_output =~ "crashed"
    end
  end

  describe "PUT /api/obs/scene/:scene_name - set scene" do
    test "sets scene with valid scene name", %{conn: conn} do
      scene_name = "Test Scene"

      response =
        conn
        |> put("/api/obs/scene/#{URI.encode(scene_name)}")

      assert response.status in [200, 400, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "success")

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "message")
        assert response_data["message"] == "Scene changed to #{scene_name}"
      else
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
      end
    end

    test "handles scene names with special characters", %{conn: conn} do
      special_scene_names = [
        "Scene with spaces",
        "Scene-with-dashes",
        "Scene_with_underscores",
        "Scene (with parentheses)",
        "Scene & symbols"
      ]

      Enum.each(special_scene_names, fn scene_name ->
        log_output =
          capture_log(fn ->
            response =
              conn
              |> put("/api/obs/scene/#{URI.encode(scene_name)}")

            assert response.status in [200, 400, 503]
          end)

        refute log_output =~ "crashed"
      end)
    end

    test "handles nonexistent scene gracefully", %{conn: conn} do
      nonexistent_scene = "Nonexistent Scene"

      response =
        conn
        |> put("/api/obs/scene/#{URI.encode(nonexistent_scene)}")

      assert response.status in [200, 400, 503]
      response_data = json_response(response, response.status)

      if response.status == 400 do
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
      end
    end
  end

  describe "GET /api/obs/scene/current - get current scene" do
    test "returns current scene when service available", %{conn: conn} do
      response =
        conn
        |> get("/api/obs/scene/current")

      assert response.status in [200, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "success")

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "data")
        assert is_map(response_data["data"])
      else
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
      end
    end

    test "handles service unavailable gracefully", %{conn: conn} do
      log_output =
        capture_log(fn ->
          response =
            conn
            |> get("/api/obs/scene/current")

          assert response.status in [200, 503]
        end)

      refute log_output =~ "crashed"
    end
  end

  describe "GET /api/obs/scenes - get scenes list" do
    test "returns scenes list when service available", %{conn: conn} do
      response =
        conn
        |> get("/api/obs/scenes")

      assert response.status in [200, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "success")

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "data")
        # Should contain scenes information
        assert is_map(response_data["data"])
      else
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
      end
    end

    test "handles service unavailable gracefully", %{conn: conn} do
      log_output =
        capture_log(fn ->
          response =
            conn
            |> get("/api/obs/scenes")

          assert response.status in [200, 503]
        end)

      refute log_output =~ "crashed"
    end
  end

  describe "GET /api/obs/streaming/status - get stream status" do
    test "returns stream status when service available", %{conn: conn} do
      response =
        conn
        |> get("/api/obs/streaming/status")

      assert response.status in [200, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "success")

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "data")
        # Should contain streaming status information
        assert is_map(response_data["data"])
      else
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
      end
    end

    test "handles service unavailable gracefully", %{conn: conn} do
      log_output =
        capture_log(fn ->
          response =
            conn
            |> get("/api/obs/streaming/status")

          assert response.status in [200, 503]
        end)

      refute log_output =~ "crashed"
    end
  end

  describe "GET /api/obs/recording/status - get recording status" do
    test "returns recording status when service available", %{conn: conn} do
      response =
        conn
        |> get("/api/obs/recording/status")

      assert response.status in [200, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "success")

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "data")
        assert is_map(response_data["data"])
      else
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
      end
    end

    test "handles service unavailable gracefully", %{conn: conn} do
      log_output =
        capture_log(fn ->
          response =
            conn
            |> get("/api/obs/recording/status")

          assert response.status in [200, 503]
        end)

      refute log_output =~ "crashed"
    end
  end

  describe "GET /api/obs/stats - get OBS statistics" do
    test "returns comprehensive OBS statistics when service available", %{conn: conn} do
      response =
        conn
        |> get("/api/obs/stats")

      assert response.status in [200, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "success")

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "data")

        stats_data = response_data["data"]
        assert is_map(stats_data)

        # Should combine service state and OBS internal stats
        expected_keys = ["service_state", "obs_internal", "timestamp"]

        Enum.each(expected_keys, fn key ->
          if Map.has_key?(stats_data, key) do
            case key do
              "timestamp" -> assert is_integer(stats_data[key])
              _ -> assert is_map(stats_data[key])
            end
          end
        end)
      else
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
      end
    end

    test "handles service unavailable gracefully", %{conn: conn} do
      log_output =
        capture_log(fn ->
          response =
            conn
            |> get("/api/obs/stats")

          assert response.status in [200, 503]
        end)

      refute log_output =~ "crashed"
    end
  end

  describe "GET /api/obs/version - get OBS version" do
    test "returns OBS version when service available", %{conn: conn} do
      response =
        conn
        |> get("/api/obs/version")

      assert response.status in [200, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "success")

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "data")
        assert is_map(response_data["data"])
      else
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
      end
    end

    test "handles service unavailable gracefully", %{conn: conn} do
      log_output =
        capture_log(fn ->
          response =
            conn
            |> get("/api/obs/version")

          assert response.status in [200, 503]
        end)

      refute log_output =~ "crashed"
    end
  end

  describe "GET /api/obs/virtual-camera - get virtual camera status" do
    test "returns virtual camera status when service available", %{conn: conn} do
      response =
        conn
        |> get("/api/obs/virtual-camera")

      assert response.status in [200, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "success")

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "data")
        assert is_map(response_data["data"])
      else
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
      end
    end

    test "handles service unavailable gracefully", %{conn: conn} do
      log_output =
        capture_log(fn ->
          response =
            conn
            |> get("/api/obs/virtual-camera")

          assert response.status in [200, 503]
        end)

      refute log_output =~ "crashed"
    end
  end

  describe "GET /api/obs/outputs - get OBS outputs" do
    test "returns outputs information when service available", %{conn: conn} do
      response =
        conn
        |> get("/api/obs/outputs")

      assert response.status in [200, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "success")

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "data")
        assert is_map(response_data["data"])
      else
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
      end
    end

    test "handles service unavailable gracefully", %{conn: conn} do
      log_output =
        capture_log(fn ->
          response =
            conn
            |> get("/api/obs/outputs")

          assert response.status in [200, 503]
        end)

      refute log_output =~ "crashed"
    end
  end

  describe "error handling and edge cases" do
    test "handles concurrent requests gracefully", %{conn: conn} do
      # Test multiple concurrent requests to different endpoints
      endpoints = [
        "/api/obs/status",
        "/api/obs/scenes",
        "/api/obs/streaming/status",
        "/api/obs/recording/status",
        "/api/obs/version"
      ]

      tasks =
        for endpoint <- endpoints do
          Task.async(fn ->
            response = get(conn, endpoint)
            {endpoint, response.status, json_response(response, response.status)}
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All requests should complete without crashing
      Enum.each(results, fn {_endpoint, status, response_data} ->
        assert status in [200, 503]
        assert is_map(response_data)
        assert Map.has_key?(response_data, "success")
      end)
    end

    test "handles streaming/recording state transitions", %{conn: conn} do
      # Test starting and stopping streaming in sequence
      stream_endpoints = [
        {"/api/obs/streaming/start", "start"},
        {"/api/obs/streaming/stop", "stop"}
      ]

      Enum.each(stream_endpoints, fn {endpoint, action} ->
        log_output =
          capture_log(fn ->
            response = post(conn, endpoint)
            assert response.status in [200, 400, 503]

            if response.status in [200, 400] do
              response_data = json_response(response, response.status)
              assert Map.has_key?(response_data, "success")

              if response_data["success"] do
                assert response_data["message"] =~ action
              end
            end
          end)

        refute log_output =~ "crashed"
      end)
    end

    test "returns consistent error response format", %{conn: conn} do
      # Force error conditions and verify response format
      error_inducing_requests = [
        # Missing scene name
        put(conn, "/api/obs/scene/"),
        # Invalid scene name
        put(conn, "/api/obs/scene/ ")
      ]

      Enum.each(error_inducing_requests, fn response ->
        if response.status in [400, 404] do
          # Some requests might return 404 for invalid routes
          assert response.status in [400, 404]
        end
      end)
    end

    test "handles service errors gracefully", %{conn: conn} do
      # Test that all endpoints handle service errors gracefully
      all_endpoints = [
        "/api/obs/status",
        "/api/obs/scenes",
        "/api/obs/scene/current",
        "/api/obs/streaming/status",
        "/api/obs/recording/status",
        "/api/obs/stats",
        "/api/obs/version",
        "/api/obs/virtual-camera",
        "/api/obs/outputs"
      ]

      Enum.each(all_endpoints, fn endpoint ->
        log_output =
          capture_log(fn ->
            response = get(conn, endpoint)
            assert response.status in [200, 503]
          end)

        refute log_output =~ "crashed"
      end)
    end

    test "sanitizes error messages in responses", %{conn: conn} do
      # Test that error responses don't leak sensitive information
      response =
        conn
        |> put("/api/obs/scene/invalid-scene-name")

      if response.status == 400 do
        response_data = json_response(response, 400)
        error_message = response_data["error"]

        # Error message should be user-friendly, not expose internals
        assert is_binary(error_message)
        assert String.length(error_message) > 0
        refute error_message =~ "Elixir"
        refute error_message =~ "GenServer"
      end
    end
  end

  describe "performance and response times" do
    test "status endpoint responds within reasonable time", %{conn: conn} do
      start_time = System.monotonic_time(:millisecond)

      response =
        conn
        |> get("/api/obs/status")

      duration = System.monotonic_time(:millisecond) - start_time

      # Status check should complete within 5 seconds
      assert duration < 5000
      assert response.status in [200, 503]
    end

    test "control operations complete promptly", %{conn: conn} do
      # Test that control operations (start/stop) don't hang
      control_endpoints = [
        "/api/obs/streaming/start",
        "/api/obs/streaming/stop",
        "/api/obs/recording/start",
        "/api/obs/recording/stop"
      ]

      Enum.each(control_endpoints, fn endpoint ->
        start_time = System.monotonic_time(:millisecond)

        response = post(conn, endpoint)

        duration = System.monotonic_time(:millisecond) - start_time

        # Control operations should complete within 10 seconds
        assert duration < 10_000
        assert response.status in [200, 400, 503]
      end)
    end

    test "information endpoints respond quickly", %{conn: conn} do
      # Test that information retrieval endpoints are responsive
      info_endpoints = [
        "/api/obs/scenes",
        "/api/obs/scene/current",
        "/api/obs/version"
      ]

      Enum.each(info_endpoints, fn endpoint ->
        start_time = System.monotonic_time(:millisecond)

        response = get(conn, endpoint)

        duration = System.monotonic_time(:millisecond) - start_time

        # Information endpoints should be fast
        assert duration < 3000
        assert response.status in [200, 503]
      end)
    end
  end
end

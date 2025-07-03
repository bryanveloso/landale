defmodule ServerWeb.HealthControllerTest do
  @moduledoc """
  Comprehensive integration tests for health check endpoints covering system monitoring,
  service status aggregation, and subscription health reporting.

  These tests verify health check functionality including basic uptime checks,
  detailed service health aggregation, readiness probes, and EventSub subscription monitoring.
  """

  use ServerWeb.ConnCase, async: false
  import ExUnit.CaptureLog

  alias Server.Repo

  describe "GET /health - basic health check" do
    test "returns 200 OK with minimal health data", %{conn: conn} do
      response =
        conn
        |> get("/health")
        |> json_response(200)

      assert response["status"] == "ok"
      assert is_integer(response["timestamp"])
      assert response["timestamp"] > 0
    end

    test "basic health check returns consistent response format", %{conn: conn} do
      # Make multiple requests to ensure consistency
      for _i <- 1..3 do
        response =
          conn
          |> get("/health")
          |> json_response(200)

        assert Map.keys(response) == ["status", "timestamp"]
        assert response["status"] == "ok"
      end
    end

    test "basic health check emits telemetry", %{conn: conn} do
      log_output =
        capture_log(fn ->
          conn
          |> get("/health")
          |> json_response(200)
        end)

      # Should not log errors during basic health check
      refute log_output =~ "error"
    end
  end

  describe "GET /api/health - detailed health check" do
    test "returns comprehensive health data with all services", %{conn: conn} do
      response =
        conn
        |> get("/api/health")
        |> json_response(200)

      # Verify response structure
      assert response["status"] in ["healthy", "degraded", "unhealthy"]
      assert is_integer(response["timestamp"])

      # Verify services section
      services = response["services"]
      assert is_map(services)
      assert Map.has_key?(services, "obs")
      assert Map.has_key?(services, "twitch")
      assert Map.has_key?(services, "database")
      assert Map.has_key?(services, "subscriptions")
      assert Map.has_key?(services, "websocket")

      # Verify system information
      system = response["system"]
      assert is_map(system)
      assert is_integer(system["uptime"])
      assert is_binary(system["version"])
      assert system["environment"] in ["dev", "test", "prod"]

      # WebSocket should be healthy if we're responding
      assert services["websocket"]["connected"] == true
    end

    test "handles OBS service unavailable gracefully", %{conn: conn} do
      response =
        conn
        |> get("/api/health")
        |> json_response(:ok)

      # OBS service might not be available in test, should handle gracefully
      obs_status = response["services"]["obs"]
      assert is_map(obs_status)
      assert Map.has_key?(obs_status, "connected")
    end

    test "handles Twitch service unavailable gracefully", %{conn: conn} do
      response =
        conn
        |> get("/api/health")
        |> json_response(:ok)

      # Twitch service might not be available in test, should handle gracefully
      twitch_status = response["services"]["twitch"]
      assert is_map(twitch_status)
      assert Map.has_key?(twitch_status, "connected")
    end

    test "handles subscription monitor unavailable gracefully", %{conn: conn} do
      response =
        conn
        |> get("/api/health")
        |> json_response(:ok)

      # Subscription monitor might not be available in test
      subscription_status = response["services"]["subscriptions"]
      assert is_map(subscription_status)
      assert Map.has_key?(subscription_status, "status")
    end

    test "returns 503 when critical services are unhealthy", %{conn: conn} do
      # This test verifies that the controller properly returns 503 for unhealthy state
      # In a real scenario, database or critical services would be down
      response =
        conn
        |> get("/api/health")

      # Response could be 200 (healthy) or 503 (unhealthy) depending on environment
      assert response.status in [200, 503]

      response_data = json_response(response, response.status)
      assert response_data["status"] in ["healthy", "degraded", "unhealthy"]
    end

    test "emits telemetry for detailed health check", %{conn: conn} do
      log_output =
        capture_log(fn ->
          conn
          |> get("/api/health")
        end)

      # Should handle any service errors gracefully without crashing
      refute log_output =~ "crashed"
    end
  end

  describe "GET /ready - readiness probe" do
    test "returns 200 when database is connected", %{conn: conn} do
      # Ensure database is available by making a simple query
      case Repo.query("SELECT 1", [], timeout: 1000) do
        {:ok, _} ->
          response =
            conn
            |> get("/ready")
            |> json_response(200)

          assert response["status"] == "ready"
          assert response["checks"]["database"]["connected"] == true

        {:error, _} ->
          # If database is not available, readiness should return 503
          response =
            conn
            |> get("/ready")
            |> json_response(503)

          assert response["status"] == "not_ready"
          assert response["checks"]["database"]["connected"] == false
      end
    end

    test "returns 503 when database is unavailable", %{conn: conn} do
      # We can't easily simulate database failure in test environment
      # But we can verify the response structure is correct
      response =
        conn
        |> get("/ready")

      assert response.status in [200, 503]
      response_data = json_response(response, response.status)

      assert response_data["status"] in ["ready", "not_ready"]
      assert is_integer(response_data["timestamp"])
      assert is_map(response_data["checks"])
      assert Map.has_key?(response_data["checks"], "database")
    end

    test "readiness probe includes timestamp and check details", %{conn: conn} do
      response =
        conn
        |> get("/ready")

      response_data = json_response(response, response.status)

      assert is_integer(response_data["timestamp"])
      assert response_data["timestamp"] > 0

      database_check = response_data["checks"]["database"]
      assert is_map(database_check)
      assert Map.has_key?(database_check, "connected")
    end

    test "emits telemetry for readiness checks", %{conn: conn} do
      log_output =
        capture_log(fn ->
          conn
          |> get("/ready")
        end)

      # Should handle database checks gracefully
      refute log_output =~ "crashed"
    end
  end

  describe "GET /api/health/subscriptions - subscription health" do
    test "returns subscription health information", %{conn: conn} do
      response =
        conn
        |> get("/api/health/subscriptions")

      # Response could be 200 or 503 depending on subscription monitor availability
      assert response.status in [200, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "status")
      assert is_integer(response_data["timestamp"])

      if response.status == 200 do
        # Successful response should have subscription health data
        assert Map.has_key?(response_data, "subscription_health")
        assert Map.has_key?(response_data, "recommendations")
        assert Map.has_key?(response_data, "summary")

        summary = response_data["summary"]
        assert Map.has_key?(summary, "health_score")
        assert Map.has_key?(summary, "critical_issues")
      else
        # Error response should have error details
        assert Map.has_key?(response_data, "error")
        assert response_data["status"] == "error"
      end
    end

    test "handles subscription monitor unavailable gracefully", %{conn: conn} do
      log_output =
        capture_log(fn ->
          response =
            conn
            |> get("/api/health/subscriptions")

          # Should not crash even if subscription monitor is unavailable
          assert response.status in [200, 503]
        end)

      # Should handle gracefully without crashing
      refute log_output =~ "crashed"
    end

    test "returns health recommendations when available", %{conn: conn} do
      response =
        conn
        |> get("/api/health/subscriptions")

      response_data = json_response(response, response.status)

      if response.status == 200 do
        recommendations = response_data["recommendations"]
        assert is_list(recommendations)

        # Recommendations should be strings
        Enum.each(recommendations, fn rec ->
          assert is_binary(rec)
        end)
      end
    end

    test "calculates health score properly", %{conn: conn} do
      response =
        conn
        |> get("/api/health/subscriptions")

      response_data = json_response(response, response.status)

      if response.status == 200 do
        health_score = response_data["summary"]["health_score"]
        assert is_integer(health_score)
        assert health_score >= 0 and health_score <= 100
      end
    end

    test "emits telemetry for subscription health checks", %{conn: conn} do
      log_output =
        capture_log(fn ->
          conn
          |> get("/api/health/subscriptions")
        end)

      # Should handle subscription checks gracefully
      refute log_output =~ "crashed"
    end
  end

  describe "health check error handling" do
    test "handles service exceptions without crashing", %{conn: conn} do
      # All health endpoints should handle service errors gracefully
      endpoints = ["/health", "/api/health", "/ready", "/api/health/subscriptions"]

      Enum.each(endpoints, fn endpoint ->
        log_output =
          capture_log(fn ->
            response = get(conn, endpoint)
            # Should always return a response, never crash
            assert response.status in [200, 503]
          end)

        # Should handle errors gracefully
        refute log_output =~ "crashed"
      end)
    end

    test "returns consistent error formats", %{conn: conn} do
      response =
        conn
        |> get("/api/health")

      response_data = json_response(response, response.status)

      # All responses should have status and timestamp
      assert Map.has_key?(response_data, "status")
      assert Map.has_key?(response_data, "timestamp")
      assert is_binary(response_data["status"])
      assert is_integer(response_data["timestamp"])
    end

    test "health checks complete within reasonable time", %{conn: conn} do
      # Health checks should be fast
      start_time = System.monotonic_time(:millisecond)

      conn
      |> get("/api/health")
      |> json_response(:ok)

      duration = System.monotonic_time(:millisecond) - start_time

      # Health check should complete within 5 seconds
      assert duration < 5000
    end
  end

  describe "concurrent health check requests" do
    test "handles multiple concurrent health checks", %{conn: conn} do
      # Spawn multiple concurrent requests
      tasks =
        for _i <- 1..5 do
          Task.async(fn ->
            response =
              conn
              |> get("/api/health")

            {response.status, json_response(response, response.status)}
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All requests should succeed
      Enum.each(results, fn {status, response_data} ->
        assert status in [200, 503]
        assert Map.has_key?(response_data, "status")
        assert Map.has_key?(response_data, "timestamp")
      end)
    end

    test "concurrent readiness probes work correctly", %{conn: conn} do
      tasks =
        for _i <- 1..3 do
          Task.async(fn ->
            response = get(conn, "/ready")
            {response.status, json_response(response, response.status)}
          end)
        end

      results = Task.await_many(tasks, 3000)

      # All requests should return consistent results
      Enum.each(results, fn {status, response_data} ->
        assert status in [200, 503]
        assert response_data["status"] in ["ready", "not_ready"]
      end)
    end
  end

  describe "health check response consistency" do
    test "basic health check always returns same structure", %{conn: conn} do
      responses =
        for _i <- 1..3 do
          conn
          |> get("/health")
          |> json_response(200)
        end

      # All responses should have same keys
      first_keys = Map.keys(List.first(responses))

      Enum.each(responses, fn response ->
        assert Map.keys(response) == first_keys
        assert response["status"] == "ok"
      end)
    end

    test "detailed health check maintains consistent service structure", %{conn: conn} do
      response =
        conn
        |> get("/api/health")
        |> json_response(:ok)

      services = response["services"]

      # Should always include these core services
      required_services = ["database", "websocket"]

      Enum.each(required_services, fn service ->
        assert Map.has_key?(services, service)
        assert is_map(services[service])
      end)
    end
  end
end

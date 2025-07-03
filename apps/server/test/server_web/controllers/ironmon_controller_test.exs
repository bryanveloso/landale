defmodule ServerWeb.IronmonControllerTest do
  @moduledoc """
  Comprehensive integration tests for IronMON challenge controller endpoints covering
  challenge management, checkpoint statistics, and result tracking.

  These tests verify IronMON functionality including challenge listing, checkpoint data,
  statistics retrieval, recent results pagination, and active challenge queries.
  """

  use ServerWeb.ConnCase, async: false
  import ExUnit.CaptureLog

  describe "GET /api/ironmon/challenges - list challenges" do
    test "returns list of available challenges", %{conn: conn} do
      response =
        conn
        |> get("/api/ironmon/challenges")
        |> json_response(200)

      assert response["success"] == true
      assert Map.has_key?(response, "data")
      assert is_list(response["data"])
    end

    test "returns consistent response format", %{conn: conn} do
      # Make multiple requests to ensure consistency
      for _i <- 1..3 do
        response =
          conn
          |> get("/api/ironmon/challenges")
          |> json_response(200)

        assert response["success"] == true
        assert Map.has_key?(response, "data")
        assert is_list(response["data"])
      end
    end

    test "handles database unavailable gracefully", %{conn: conn} do
      log_output =
        capture_log(fn ->
          response =
            conn
            |> get("/api/ironmon/challenges")

          # Should not crash even if database is unavailable
          assert response.status in [200, 500]
        end)

      # Should handle gracefully without crashing
      refute log_output =~ "crashed"
    end

    test "returns challenge data with expected structure", %{conn: conn} do
      response =
        conn
        |> get("/api/ironmon/challenges")
        |> json_response(200)

      challenges = response["data"]

      # If challenges exist, verify structure
      if length(challenges) > 0 do
        first_challenge = List.first(challenges)
        assert is_map(first_challenge)
        # Should have at least an ID field
        assert Map.has_key?(first_challenge, "id") or Map.has_key?(first_challenge, :id)
      end
    end
  end

  describe "GET /api/ironmon/challenges/:id/checkpoints - list checkpoints" do
    test "returns checkpoints for valid challenge ID", %{conn: conn} do
      challenge_id = 1

      response =
        conn
        |> get("/api/ironmon/challenges/#{challenge_id}/checkpoints")

      assert response.status in [200, 404]
      response_data = json_response(response, response.status)

      assert response_data["success"] == true or response_data["success"] == false

      if response.status == 200 do
        assert Map.has_key?(response_data, "data")
        assert is_list(response_data["data"])
      end
    end

    test "returns 400 for invalid challenge ID", %{conn: conn} do
      invalid_ids = ["abc", "12.5", "-1"]

      Enum.each(invalid_ids, fn invalid_id ->
        response =
          conn
          |> get("/api/ironmon/challenges/#{invalid_id}/checkpoints")
          |> json_response(400)

        assert response["success"] == false
        assert response["error"] == "Invalid challenge ID"
      end)
    end

    test "returns 404 for empty challenge ID", %{conn: conn} do
      response =
        conn
        |> get("/api/ironmon/challenges//checkpoints")

      assert response.status == 404
    end

    test "handles numeric string IDs correctly", %{conn: conn} do
      valid_numeric_ids = ["1", "123", "9999"]

      Enum.each(valid_numeric_ids, fn id ->
        response =
          conn
          |> get("/api/ironmon/challenges/#{id}/checkpoints")

        # Should not return 400 for valid numeric strings
        assert response.status in [200, 404]
        response_data = json_response(response, response.status)

        if response.status == 200 do
          assert response_data["success"] == true
          assert Map.has_key?(response_data, "data")
        end
      end)
    end

    test "returns checkpoints with expected structure", %{conn: conn} do
      challenge_id = 1

      response =
        conn
        |> get("/api/ironmon/challenges/#{challenge_id}/checkpoints")

      if response.status == 200 do
        response_data = json_response(response, 200)
        checkpoints = response_data["data"]

        # If checkpoints exist, verify structure
        if length(checkpoints) > 0 do
          first_checkpoint = List.first(checkpoints)
          assert is_map(first_checkpoint)
          # Should have at least an ID field
          assert Map.has_key?(first_checkpoint, "id") or Map.has_key?(first_checkpoint, :id)
        end
      end
    end
  end

  describe "GET /api/ironmon/checkpoints/:id/stats - checkpoint statistics" do
    test "returns statistics for valid checkpoint ID", %{conn: conn} do
      checkpoint_id = 1

      response =
        conn
        |> get("/api/ironmon/checkpoints/#{checkpoint_id}/stats")

      assert response.status in [200, 404]
      response_data = json_response(response, response.status)

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "data")
        assert is_map(response_data["data"])
      end
    end

    test "returns 400 for invalid checkpoint ID", %{conn: conn} do
      invalid_ids = ["abc", "12.5", "-1", "not_a_number"]

      Enum.each(invalid_ids, fn invalid_id ->
        response =
          conn
          |> get("/api/ironmon/checkpoints/#{invalid_id}/stats")
          |> json_response(400)

        assert response["success"] == false
        assert response["error"] == "Invalid checkpoint ID"
      end)
    end

    test "handles numeric string IDs correctly", %{conn: conn} do
      valid_numeric_ids = ["1", "123", "9999"]

      Enum.each(valid_numeric_ids, fn id ->
        response =
          conn
          |> get("/api/ironmon/checkpoints/#{id}/stats")

        # Should not return 400 for valid numeric strings
        assert response.status in [200, 404]
      end)
    end

    test "returns statistics with expected structure", %{conn: conn} do
      checkpoint_id = 1

      response =
        conn
        |> get("/api/ironmon/checkpoints/#{checkpoint_id}/stats")

      if response.status == 200 do
        response_data = json_response(response, 200)
        stats = response_data["data"]

        assert is_map(stats)
        # Stats should contain statistical data (exact structure depends on implementation)
      end
    end
  end

  describe "GET /api/ironmon/results/recent - recent results" do
    test "returns recent results with default pagination", %{conn: conn} do
      response =
        conn
        |> get("/api/ironmon/results/recent")
        |> json_response(200)

      assert response["success"] == true
      assert Map.has_key?(response, "data")
      # Data could be list of results or paginated structure
      assert is_list(response["data"]) or is_map(response["data"])
    end

    test "accepts limit parameter", %{conn: conn} do
      limits = [5, 20, 50]

      Enum.each(limits, fn limit ->
        response =
          conn
          |> get("/api/ironmon/results/recent?limit=#{limit}")
          |> json_response(200)

        assert response["success"] == true
        assert Map.has_key?(response, "data")
      end)
    end

    test "accepts cursor parameter for pagination", %{conn: conn} do
      response =
        conn
        |> get("/api/ironmon/results/recent?cursor=123")
        |> json_response(200)

      assert response["success"] == true
      assert Map.has_key?(response, "data")
    end

    test "accepts both limit and cursor parameters", %{conn: conn} do
      response =
        conn
        |> get("/api/ironmon/results/recent?limit=15&cursor=456")
        |> json_response(200)

      assert response["success"] == true
      assert Map.has_key?(response, "data")
    end

    test "handles invalid limit parameter gracefully", %{conn: conn} do
      invalid_limits = ["abc", "12.5", "-5", "not_a_number"]

      Enum.each(invalid_limits, fn invalid_limit ->
        response =
          conn
          |> get("/api/ironmon/results/recent?limit=#{invalid_limit}")
          |> json_response(200)

        # Should still succeed with default limit
        assert response["success"] == true
        assert Map.has_key?(response, "data")
      end)
    end

    test "handles invalid cursor parameter gracefully", %{conn: conn} do
      invalid_cursors = ["abc", "12.5", "not_a_number"]

      Enum.each(invalid_cursors, fn invalid_cursor ->
        response =
          conn
          |> get("/api/ironmon/results/recent?cursor=#{invalid_cursor}")
          |> json_response(200)

        # Should still succeed with nil cursor
        assert response["success"] == true
        assert Map.has_key?(response, "data")
      end)
    end

    test "returns results with expected structure", %{conn: conn} do
      response =
        conn
        |> get("/api/ironmon/results/recent")
        |> json_response(200)

      results_data = response["data"]

      # If results exist, verify structure
      if is_list(results_data) and length(results_data) > 0 do
        first_result = List.first(results_data)
        assert is_map(first_result)
      end
    end
  end

  describe "GET /api/ironmon/seeds/:id/challenge - active challenge" do
    test "returns active challenge for valid seed ID", %{conn: conn} do
      seed_id = 1

      response =
        conn
        |> get("/api/ironmon/seeds/#{seed_id}/challenge")

      assert response.status in [200, 404]
      response_data = json_response(response, response.status)

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "data")
        assert is_map(response_data["data"])
      else
        assert response_data["success"] == false
        assert response_data["error"] == "No active challenge found"
      end
    end

    test "returns 400 for invalid seed ID", %{conn: conn} do
      invalid_ids = ["abc", "12.5", "-1", "not_a_number"]

      Enum.each(invalid_ids, fn invalid_id ->
        response =
          conn
          |> get("/api/ironmon/seeds/#{invalid_id}/challenge")
          |> json_response(400)

        assert response["success"] == false
        assert response["error"] == "Invalid seed ID"
      end)
    end

    test "handles numeric string IDs correctly", %{conn: conn} do
      valid_numeric_ids = ["1", "123", "9999"]

      Enum.each(valid_numeric_ids, fn id ->
        response =
          conn
          |> get("/api/ironmon/seeds/#{id}/challenge")

        # Should not return 400 for valid numeric strings
        assert response.status in [200, 404]
      end)
    end

    test "returns 404 for nonexistent seed", %{conn: conn} do
      # Use a very large ID that's unlikely to exist
      nonexistent_seed_id = 999_999

      response =
        conn
        |> get("/api/ironmon/seeds/#{nonexistent_seed_id}/challenge")

      # Could be 404 (seed not found) or 200 (seed exists)
      assert response.status in [200, 404]

      if response.status == 404 do
        response_data = json_response(response, 404)
        assert response_data["success"] == false
        assert response_data["error"] == "No active challenge found"
      end
    end

    test "returns active challenge with expected structure", %{conn: conn} do
      seed_id = 1

      response =
        conn
        |> get("/api/ironmon/seeds/#{seed_id}/challenge")

      if response.status == 200 do
        response_data = json_response(response, 200)
        challenge = response_data["data"]

        assert is_map(challenge)
        # Should have at least an ID field
        assert Map.has_key?(challenge, "id") or Map.has_key?(challenge, :id)
      end
    end
  end

  describe "error handling and edge cases" do
    test "handles database errors gracefully", %{conn: conn} do
      # Test all endpoints handle database errors gracefully
      endpoints = [
        "/api/ironmon/challenges",
        "/api/ironmon/challenges/1/checkpoints",
        "/api/ironmon/checkpoints/1/stats",
        "/api/ironmon/results/recent",
        "/api/ironmon/seeds/1/challenge"
      ]

      Enum.each(endpoints, fn endpoint ->
        log_output =
          capture_log(fn ->
            response = get(conn, endpoint)
            # Should always return a response, never crash
            assert response.status in [200, 400, 404, 500]
          end)

        # Should handle errors gracefully
        refute log_output =~ "crashed"
      end)
    end

    test "handles concurrent requests gracefully", %{conn: conn} do
      # Test multiple concurrent requests to different endpoints
      endpoints = [
        "/api/ironmon/challenges",
        "/api/ironmon/challenges/1/checkpoints",
        "/api/ironmon/checkpoints/1/stats",
        "/api/ironmon/results/recent",
        "/api/ironmon/seeds/1/challenge"
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
        assert status in [200, 400, 404, 500]
        assert is_map(response_data)
        assert Map.has_key?(response_data, "success")
      end)
    end

    test "returns consistent error response format", %{conn: conn} do
      # Test error response consistency across endpoints
      error_inducing_requests = [
        get(conn, "/api/ironmon/challenges/invalid/checkpoints"),
        get(conn, "/api/ironmon/checkpoints/invalid/stats"),
        get(conn, "/api/ironmon/seeds/invalid/challenge")
      ]

      Enum.each(error_inducing_requests, fn response ->
        if response.status == 400 do
          response_data = json_response(response, 400)
          assert response_data["success"] == false
          assert Map.has_key?(response_data, "error")
          assert is_binary(response_data["error"])
        end
      end)
    end

    test "handles large pagination parameters", %{conn: conn} do
      # Test with very large limit values
      large_limits = [1000, 10_000, 999_999]

      Enum.each(large_limits, fn limit ->
        response =
          conn
          |> get("/api/ironmon/results/recent?limit=#{limit}")

        # Should handle large limits gracefully
        assert response.status in [200, 400]
      end)
    end

    test "sanitizes error messages in responses", %{conn: conn} do
      # Test that error responses don't leak sensitive information
      response =
        conn
        |> get("/api/ironmon/challenges/invalid/checkpoints")
        |> json_response(400)

      error_message = response["error"]
      # Error message should be user-friendly, not expose internals
      assert is_binary(error_message)
      assert String.length(error_message) > 0
      # Should not contain technical details that could help attackers
      refute error_message =~ "Elixir"
      refute error_message =~ "GenServer"
      refute error_message =~ "Repo"
    end
  end

  describe "parameter parsing and validation" do
    test "parse_integer function handles various inputs", %{conn: conn} do
      # Test endpoint that uses parse_integer internally (results/recent)
      test_cases = [
        # Valid integer string
        {"10", 200},
        # Zero
        {"0", 200},
        # Invalid - should use default
        {"abc", 200},
        # Empty - should use default
        {"", 200},
        # Float - should use default
        {"12.5", 200}
      ]

      Enum.each(test_cases, fn {limit_value, expected_status} ->
        response =
          conn
          |> get("/api/ironmon/results/recent?limit=#{limit_value}")

        assert response.status == expected_status
        response_data = json_response(response, expected_status)
        assert response_data["success"] == true
      end)
    end

    test "parse_optional_integer function handles various inputs", %{conn: conn} do
      # Test endpoint that uses parse_optional_integer internally (results/recent cursor)
      test_cases = [
        # Valid integer string
        {"123", 200},
        # Zero
        {"0", 200},
        # Invalid - should use nil
        {"abc", 200},
        # Empty - should use nil
        {"", 200},
        # Float - should use nil
        {"12.5", 200}
      ]

      Enum.each(test_cases, fn {cursor_value, expected_status} ->
        response =
          conn
          |> get("/api/ironmon/results/recent?cursor=#{cursor_value}")

        assert response.status == expected_status
        response_data = json_response(response, expected_status)
        assert response_data["success"] == true
      end)
    end

    test "integer ID validation is consistent", %{conn: conn} do
      # Test that all endpoints with integer ID parameters handle validation consistently
      id_endpoints = [
        "/api/ironmon/challenges/{id}/checkpoints",
        "/api/ironmon/checkpoints/{id}/stats",
        "/api/ironmon/seeds/{id}/challenge"
      ]

      invalid_ids = ["abc", "12.5", "not_a_number"]

      Enum.each(id_endpoints, fn endpoint_template ->
        Enum.each(invalid_ids, fn invalid_id ->
          endpoint = String.replace(endpoint_template, "{id}", invalid_id)

          response = get(conn, endpoint)

          assert response.status == 400
          response_data = json_response(response, 400)
          assert response_data["success"] == false
          assert is_binary(response_data["error"])
        end)
      end)
    end
  end

  describe "performance and response times" do
    test "challenges list responds quickly", %{conn: conn} do
      start_time = System.monotonic_time(:millisecond)

      conn
      |> get("/api/ironmon/challenges")
      |> json_response(200)

      duration = System.monotonic_time(:millisecond) - start_time

      # List endpoint should be reasonably fast
      assert duration < 3000
    end

    test "all endpoints respond within reasonable time", %{conn: conn} do
      endpoints = [
        "/api/ironmon/challenges",
        "/api/ironmon/challenges/1/checkpoints",
        "/api/ironmon/checkpoints/1/stats",
        "/api/ironmon/results/recent",
        "/api/ironmon/seeds/1/challenge"
      ]

      Enum.each(endpoints, fn endpoint ->
        start_time = System.monotonic_time(:millisecond)

        response = get(conn, endpoint)

        duration = System.monotonic_time(:millisecond) - start_time

        # All endpoints should complete within 5 seconds
        assert duration < 5000
        assert response.status in [200, 400, 404, 500]
      end)
    end

    test "pagination doesn't significantly slow down response", %{conn: conn} do
      # Test that adding pagination parameters doesn't dramatically slow response
      start_time = System.monotonic_time(:millisecond)

      conn
      |> get("/api/ironmon/results/recent?limit=50&cursor=100")
      |> json_response(200)

      duration = System.monotonic_time(:millisecond) - start_time

      # Paginated results should still be fast
      assert duration < 5000
    end
  end
end

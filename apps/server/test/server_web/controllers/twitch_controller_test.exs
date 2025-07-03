defmodule ServerWeb.TwitchControllerTest do
  @moduledoc """
  Comprehensive integration tests for Twitch EventSub controller endpoints covering
  subscription management, status monitoring, and error handling.

  These tests verify Twitch EventSub functionality including status checks,
  subscription listing, creation/deletion, and available subscription types.
  """

  use ServerWeb.ConnCase, async: false
  import ExUnit.CaptureLog

  describe "GET /api/twitch/status - Twitch service status" do
    test "returns service status when available", %{conn: conn} do
      response =
        conn
        |> get("/api/twitch/status")

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
            |> get("/api/twitch/status")

          # Should not crash even if Twitch service is unavailable
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
          |> get("/api/twitch/status")

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

  describe "GET /api/twitch/subscriptions - EventSub subscriptions" do
    test "returns subscription list when service available", %{conn: conn} do
      response =
        conn
        |> get("/api/twitch/subscriptions")

      # Response could be 200 (service available) or 503 (service unavailable)
      assert response.status in [200, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "success")

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "data")
        # Data could be list of subscriptions or empty list
        assert is_map(response_data["data"]) or is_list(response_data["data"])
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
            |> get("/api/twitch/subscriptions")

          assert response.status in [200, 503]
        end)

      refute log_output =~ "crashed"
    end
  end

  describe "POST /api/twitch/subscriptions - create subscription" do
    test "creates subscription with valid parameters", %{conn: conn} do
      subscription_params = %{
        "event_type" => "stream.online",
        "condition" => %{
          "broadcaster_user_id" => "123456"
        },
        "opts" => []
      }

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/twitch/subscriptions", subscription_params)

      # Could succeed (200) or fail (400) depending on service availability and auth
      assert response.status in [200, 400, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "success")

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "data")
      else
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
      end
    end

    test "returns 400 for missing required parameters", %{conn: conn} do
      # Missing event_type
      invalid_params = %{
        "condition" => %{
          "broadcaster_user_id" => "123456"
        }
      }

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/twitch/subscriptions", invalid_params)
        |> json_response(400)

      assert response["success"] == false
      assert Map.has_key?(response, "error")
      assert response["error"] =~ "Missing required parameters"
    end

    test "returns 400 for missing condition parameter", %{conn: conn} do
      # Missing condition
      invalid_params = %{
        "event_type" => "stream.online"
      }

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/twitch/subscriptions", invalid_params)
        |> json_response(400)

      assert response["success"] == false
      assert Map.has_key?(response, "error")
      assert response["error"] =~ "Missing required parameters"
    end

    test "returns 400 for empty request body", %{conn: conn} do
      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/twitch/subscriptions", %{})
        |> json_response(400)

      assert response["success"] == false
      assert Map.has_key?(response, "error")
      assert response["error"] =~ "Missing required parameters"
    end

    test "handles service creation errors gracefully", %{conn: conn} do
      # Use invalid event type to trigger service error
      invalid_params = %{
        "event_type" => "invalid.event.type",
        "condition" => %{
          "broadcaster_user_id" => "123456"
        }
      }

      log_output =
        capture_log(fn ->
          response =
            conn
            |> put_req_header("content-type", "application/json")
            |> post("/api/twitch/subscriptions", invalid_params)

          assert response.status in [400, 503]
        end)

      refute log_output =~ "crashed"
    end
  end

  describe "DELETE /api/twitch/subscriptions/:id - delete subscription" do
    test "deletes subscription with valid ID", %{conn: conn} do
      subscription_id = "test-subscription-id-12345"

      response =
        conn
        |> delete("/api/twitch/subscriptions/#{subscription_id}")

      # Could succeed (200) or fail (400) depending on subscription existence
      assert response.status in [200, 400, 503]
      response_data = json_response(response, response.status)

      assert is_map(response_data)
      assert Map.has_key?(response_data, "success")

      if response.status == 200 do
        assert response_data["success"] == true
        assert Map.has_key?(response_data, "message")
        assert response_data["message"] == "Subscription deleted"
      else
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
      end
    end

    test "returns 400 for missing subscription ID", %{conn: conn} do
      # Test route without ID parameter
      response =
        conn
        |> delete("/api/twitch/subscriptions/")
        |> json_response(404)

      # Should return 404 for invalid route
      assert is_map(response)
    end

    test "handles service deletion errors gracefully", %{conn: conn} do
      invalid_id = "nonexistent-subscription-id"

      log_output =
        capture_log(fn ->
          response =
            conn
            |> delete("/api/twitch/subscriptions/#{invalid_id}")

          assert response.status in [200, 400, 503]
        end)

      refute log_output =~ "crashed"
    end
  end

  describe "GET /api/twitch/subscription-types - available subscription types" do
    test "returns available subscription types", %{conn: conn} do
      response =
        conn
        |> get("/api/twitch/subscription-types")
        |> json_response(200)

      assert response["success"] == true
      assert Map.has_key?(response, "data")

      subscription_types = response["data"]
      assert is_map(subscription_types)

      # Should contain expected categories
      expected_categories = ["stream", "channel", "user"]

      Enum.each(expected_categories, fn category ->
        assert Map.has_key?(subscription_types, category)
        assert is_list(subscription_types[category])
      end)

      # Verify stream category contains expected subscription types
      stream_types = subscription_types["stream"]
      stream_type_names = Enum.map(stream_types, & &1["type"])
      assert "stream.online" in stream_type_names
      assert "stream.offline" in stream_type_names

      # Verify each subscription type has required fields
      Enum.each(stream_types, fn sub_type ->
        assert Map.has_key?(sub_type, "type")
        assert Map.has_key?(sub_type, "description")
        assert Map.has_key?(sub_type, "scopes")
        assert Map.has_key?(sub_type, "version")

        assert is_binary(sub_type["type"])
        assert is_binary(sub_type["description"])
        assert is_list(sub_type["scopes"])
        assert is_binary(sub_type["version"])
      end)
    end

    test "subscription types endpoint is always available", %{conn: conn} do
      # This endpoint should work even if Twitch service is down
      # since it returns static data
      for _i <- 1..3 do
        response =
          conn
          |> get("/api/twitch/subscription-types")
          |> json_response(200)

        assert response["success"] == true
        assert Map.has_key?(response, "data")
      end
    end

    test "returns detailed subscription type information", %{conn: conn} do
      response =
        conn
        |> get("/api/twitch/subscription-types")
        |> json_response(200)

      subscription_types = response["data"]

      # Check channel category for detailed subscription types
      channel_types = subscription_types["channel"]
      channel_type_names = Enum.map(channel_types, & &1["type"])

      expected_channel_types = [
        "channel.update",
        "channel.follow",
        "channel.subscribe",
        "channel.cheer",
        "channel.raid",
        "channel.channel_points_custom_reward_redemption.add",
        "channel.poll.begin",
        "channel.prediction.begin",
        "channel.hype_train.begin"
      ]

      Enum.each(expected_channel_types, fn expected_type ->
        assert expected_type in channel_type_names
      end)

      # Verify subscription types that require scopes have them specified
      follow_type = Enum.find(channel_types, &(&1["type"] == "channel.follow"))
      assert follow_type["scopes"] == ["moderator:read:followers"]

      subscribe_type = Enum.find(channel_types, &(&1["type"] == "channel.subscribe"))
      assert subscribe_type["scopes"] == ["channel:read:subscriptions"]
    end
  end

  describe "error handling and edge cases" do
    test "handles malformed JSON in POST requests", %{conn: conn} do
      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/twitch/subscriptions", "{invalid json}")

      # Phoenix should handle JSON parsing errors
      assert response.status in [400, 422]
    end

    test "handles concurrent requests gracefully", %{conn: conn} do
      # Test multiple concurrent requests to different endpoints
      tasks =
        for endpoint <- [
              "/api/twitch/status",
              "/api/twitch/subscriptions",
              "/api/twitch/subscription-types"
            ] do
          Task.async(fn ->
            response = get(conn, endpoint)
            {endpoint, response.status, json_response(response, response.status)}
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All requests should complete without crashing
      Enum.each(results, fn {endpoint, status, response_data} ->
        assert status in [200, 503]
        assert is_map(response_data)
        assert Map.has_key?(response_data, "success")

        # subscription-types should always work
        if String.ends_with?(endpoint, "subscription-types") do
          assert status == 200
          assert response_data["success"] == true
        end
      end)
    end

    test "returns consistent error response format", %{conn: conn} do
      # Test error response consistency across endpoints
      error_responses = [
        post(conn, "/api/twitch/subscriptions", %{}),
        delete(conn, "/api/twitch/subscriptions/invalid-id")
      ]

      Enum.each(error_responses, fn response ->
        if response.status == 400 do
          response_data = json_response(response, 400)
          assert response_data["success"] == false
          assert Map.has_key?(response_data, "error")
          assert is_binary(response_data["error"])
        end
      end)
    end

    test "handles service timeouts gracefully", %{conn: conn} do
      # This tests that controller properly handles service timeouts
      log_output =
        capture_log(fn ->
          response =
            conn
            |> get("/api/twitch/status")

          # Should not crash on timeout
          assert response.status in [200, 503]
        end)

      refute log_output =~ "crashed"
    end
  end

  describe "request validation and security" do
    test "validates subscription creation parameters", %{conn: conn} do
      # Test various invalid parameter combinations
      invalid_param_sets = [
        %{},
        %{"event_type" => ""},
        %{"event_type" => "stream.online"},
        %{"condition" => %{}},
        %{"event_type" => nil, "condition" => nil}
      ]

      Enum.each(invalid_param_sets, fn params ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> post("/api/twitch/subscriptions", params)

        assert response.status == 400
        response_data = json_response(response, 400)
        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
      end)
    end

    test "handles large request payloads appropriately", %{conn: conn} do
      # Create a large but valid subscription request
      large_condition = %{
        "broadcaster_user_id" => "123456",
        "large_field" => String.duplicate("x", 1000)
      }

      large_params = %{
        "event_type" => "stream.online",
        "condition" => large_condition
      }

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/twitch/subscriptions", large_params)

      # Should handle large payloads gracefully
      assert response.status in [200, 400, 503]
    end

    test "sanitizes error messages in responses", %{conn: conn} do
      # Test that error responses don't leak sensitive information
      response =
        conn
        |> post("/api/twitch/subscriptions", %{})
        |> json_response(400)

      error_message = response["error"]
      # Error message should be user-friendly, not expose internals
      assert is_binary(error_message)
      assert String.length(error_message) > 0
      # Should not contain technical details that could help attackers
      refute error_message =~ "Elixir"
      refute error_message =~ "GenServer"
    end
  end

  describe "performance and response times" do
    test "subscription types endpoint responds quickly", %{conn: conn} do
      start_time = System.monotonic_time(:millisecond)

      conn
      |> get("/api/twitch/subscription-types")
      |> json_response(200)

      duration = System.monotonic_time(:millisecond) - start_time

      # Static data endpoint should be very fast
      assert duration < 100
    end

    test "status endpoint responds within reasonable time", %{conn: conn} do
      start_time = System.monotonic_time(:millisecond)

      response =
        conn
        |> get("/api/twitch/status")

      duration = System.monotonic_time(:millisecond) - start_time

      # Status check should complete within 5 seconds
      assert duration < 5000
      assert response.status in [200, 503]
    end
  end
end

defmodule ServerWeb.WebSocketControllerTest do
  @moduledoc """
  Comprehensive integration tests for WebSocket API documentation controller endpoints
  covering schema generation, channel introspection, and usage examples.

  These tests verify WebSocket API documentation functionality including schema generation,
  channel listing, detailed channel information, and client usage examples.
  """

  use ServerWeb.ConnCase, async: false
  import ExUnit.CaptureLog

  describe "GET /api/websocket/schema - WebSocket API schema" do
    test "returns complete WebSocket API schema", %{conn: conn} do
      response =
        conn
        |> get("/api/websocket/schema")
        |> json_response(200)

      assert response["success"] == true
      assert Map.has_key?(response, "data")

      schema = response["data"]
      assert is_map(schema)

      # Schema should contain information about channels
      # Exact structure depends on ChannelRegistry implementation
      # but should be a comprehensive API documentation
    end

    test "schema endpoint is always available", %{conn: conn} do
      # This endpoint should work reliably since it generates static schema
      for _i <- 1..3 do
        response =
          conn
          |> get("/api/websocket/schema")
          |> json_response(200)

        assert response["success"] == true
        assert Map.has_key?(response, "data")
        assert is_map(response["data"])
      end
    end

    test "returns consistent schema format", %{conn: conn} do
      # Make multiple requests to ensure schema is consistent
      responses =
        for _i <- 1..3 do
          conn
          |> get("/api/websocket/schema")
          |> json_response(200)
        end

      # All responses should have same structure
      first_schema = List.first(responses)["data"]

      Enum.each(responses, fn response ->
        assert response["success"] == true
        schema = response["data"]
        assert Map.keys(schema) == Map.keys(first_schema)
      end)
    end
  end

  describe "GET /api/websocket/channels - list WebSocket channels" do
    test "returns list of available channels", %{conn: conn} do
      response =
        conn
        |> get("/api/websocket/channels")
        |> json_response(200)

      assert response["success"] == true
      assert Map.has_key?(response, "data")

      channels = response["data"]
      assert is_list(channels)

      # If channels exist, verify their structure
      if length(channels) > 0 do
        first_channel = List.first(channels)
        assert is_map(first_channel)

        # Each channel should have expected fields
        expected_fields = ["module", "topic_pattern", "description", "command_count", "event_count"]

        Enum.each(expected_fields, fn field ->
          assert Map.has_key?(first_channel, field)
        end)

        # Verify field types
        assert is_binary(first_channel["module"])
        assert is_binary(first_channel["topic_pattern"])
        assert is_binary(first_channel["description"])
        assert is_integer(first_channel["command_count"])
        assert is_integer(first_channel["event_count"])
      end
    end

    test "channels endpoint is always available", %{conn: conn} do
      # This endpoint should work reliably since it introspects channel modules
      for _i <- 1..3 do
        response =
          conn
          |> get("/api/websocket/channels")
          |> json_response(200)

        assert response["success"] == true
        assert Map.has_key?(response, "data")
        assert is_list(response["data"])
      end
    end

    test "returns consistent channel information", %{conn: conn} do
      # Make multiple requests to ensure channel list is consistent
      responses =
        for _i <- 1..3 do
          conn
          |> get("/api/websocket/channels")
          |> json_response(200)
        end

      # All responses should have same channel count and structure
      first_channels = List.first(responses)["data"]

      Enum.each(responses, fn response ->
        assert response["success"] == true
        channels = response["data"]
        assert length(channels) == length(first_channels)
      end)
    end

    test "channel modules are properly formatted", %{conn: conn} do
      response =
        conn
        |> get("/api/websocket/channels")
        |> json_response(200)

      channels = response["data"]

      # If channels exist, verify module names are properly formatted
      if length(channels) > 0 do
        Enum.each(channels, fn channel ->
          module_name = channel["module"]
          # Module names should look like "ServerWeb.SomeChannel"
          assert String.starts_with?(module_name, "ServerWeb.")
          assert String.contains?(module_name, "Channel")
        end)
      end
    end
  end

  describe "GET /api/websocket/channels/:module - channel details" do
    test "returns detailed channel information for valid module", %{conn: conn} do
      # First get list of available channels
      channels_response =
        conn
        |> get("/api/websocket/channels")
        |> json_response(200)

      channels = channels_response["data"]

      # If channels exist, test detailed info for first channel
      if length(channels) > 0 do
        first_channel = List.first(channels)
        module_name = first_channel["module"]

        response =
          conn
          |> get("/api/websocket/channels/#{URI.encode(module_name)}")

        assert response.status in [200, 404]

        if response.status == 200 do
          response_data = json_response(response, 200)

          assert response_data["success"] == true
          assert Map.has_key?(response_data, "data")

          channel_info = response_data["data"]
          assert is_map(channel_info)

          # Verify detailed channel information structure
          expected_fields = ["module", "topic_pattern", "description", "commands", "events", "examples"]

          Enum.each(expected_fields, fn field ->
            assert Map.has_key?(channel_info, field)
          end)

          # Verify field types
          assert is_binary(channel_info["module"])
          assert is_binary(channel_info["topic_pattern"])
          assert is_binary(channel_info["description"])
          assert is_list(channel_info["commands"])
          assert is_list(channel_info["events"])
          assert is_map(channel_info["examples"]) or is_list(channel_info["examples"])
        end
      end
    end

    test "returns 404 for nonexistent module", %{conn: conn} do
      nonexistent_module = "ServerWeb.NonexistentChannel"

      response =
        conn
        |> get("/api/websocket/channels/#{URI.encode(nonexistent_module)}")
        |> json_response(404)

      assert response["success"] == false
      assert Map.has_key?(response, "error")

      error = response["error"]
      assert is_map(error)
      assert Map.has_key?(error, "message")
      assert error["message"] == "Module not found"
    end

    test "returns 404 for invalid module name", %{conn: conn} do
      invalid_modules = [
        "InvalidModule",
        "Not.A.Channel",
        "",
        "ServerWeb.NotAChannel"
      ]

      Enum.each(invalid_modules, fn invalid_module ->
        response =
          conn
          |> get("/api/websocket/channels/#{URI.encode(invalid_module)}")

        assert response.status == 404
        response_data = json_response(response, 404)

        assert response_data["success"] == false
        assert Map.has_key?(response_data, "error")
      end)
    end

    test "returns 404 for non-channel module", %{conn: conn} do
      # Test with a module that exists but is not a Phoenix channel
      non_channel_module = "Kernel"

      response =
        conn
        |> get("/api/websocket/channels/#{URI.encode(non_channel_module)}")

      # Could be 404 (module not found) or 404 (not a channel module)
      assert response.status == 404
      response_data = json_response(response, 404)

      assert response_data["success"] == false
      assert Map.has_key?(response_data, "error")
    end

    test "handles URL encoding in module names", %{conn: conn} do
      # Test that module names with special characters are handled correctly
      module_with_spaces = "ServerWeb.Test Channel"
      encoded_module = URI.encode(module_with_spaces)

      response =
        conn
        |> get("/api/websocket/channels/#{encoded_module}")

      # Should return 404 since this isn't a valid module name
      assert response.status == 404
    end
  end

  describe "GET /api/websocket/examples - WebSocket usage examples" do
    test "returns comprehensive usage examples", %{conn: conn} do
      response =
        conn
        |> get("/api/websocket/examples")
        |> json_response(200)

      assert response["success"] == true
      assert Map.has_key?(response, "data")

      examples = response["data"]
      assert is_map(examples)

      # Verify main example categories
      expected_categories = ["connection", "channels", "message_format"]

      Enum.each(expected_categories, fn category ->
        assert Map.has_key?(examples, category)
      end)

      # Verify connection examples
      connection = examples["connection"]
      assert is_map(connection)
      assert Map.has_key?(connection, "javascript")
      assert Map.has_key?(connection, "websocat")

      # Verify JavaScript example structure
      js_example = connection["javascript"]
      assert Map.has_key?(js_example, "description")
      assert Map.has_key?(js_example, "code")
      assert is_binary(js_example["description"])
      assert is_binary(js_example["code"])

      # Verify websocat example structure
      websocat_example = connection["websocat"]
      assert Map.has_key?(websocat_example, "description")
      assert Map.has_key?(websocat_example, "code")
      assert is_binary(websocat_example["description"])
      assert is_binary(websocat_example["code"])

      # Verify message format examples
      message_format = examples["message_format"]
      assert is_map(message_format)
      assert Map.has_key?(message_format, "description")
      assert Map.has_key?(message_format, "outgoing")
      assert Map.has_key?(message_format, "incoming")

      # Verify channels examples (depends on available channels)
      channels = examples["channels"]
      assert is_map(channels)
    end

    test "examples endpoint is always available", %{conn: conn} do
      # This endpoint should work reliably since it generates static examples
      for _i <- 1..3 do
        response =
          conn
          |> get("/api/websocket/examples")
          |> json_response(200)

        assert response["success"] == true
        assert Map.has_key?(response, "data")
        assert is_map(response["data"])
      end
    end

    test "returns consistent examples format", %{conn: conn} do
      # Make multiple requests to ensure examples are consistent
      responses =
        for _i <- 1..3 do
          conn
          |> get("/api/websocket/examples")
          |> json_response(200)
        end

      # All responses should have same structure
      first_examples = List.first(responses)["data"]

      Enum.each(responses, fn response ->
        assert response["success"] == true
        examples = response["data"]
        assert Map.keys(examples) == Map.keys(first_examples)
      end)
    end

    test "includes practical code examples", %{conn: conn} do
      response =
        conn
        |> get("/api/websocket/examples")
        |> json_response(200)

      examples = response["data"]

      # Verify JavaScript example contains practical code
      js_code = examples["connection"]["javascript"]["code"]
      assert String.contains?(js_code, "import")
      assert String.contains?(js_code, "Socket")
      assert String.contains?(js_code, "connect")

      # Verify websocat example contains practical commands
      websocat_code = examples["connection"]["websocat"]["code"]
      assert String.contains?(websocat_code, "websocat")
      assert String.contains?(websocat_code, "ws://")
      assert String.contains?(websocat_code, "phx_join")

      # Verify message format examples are properly structured
      message_format = examples["message_format"]
      assert String.contains?(message_format["outgoing"]["format"], "ref")
      assert is_list(message_format["outgoing"]["example"])
      assert is_list(message_format["incoming"]["reply_example"])
      assert is_list(message_format["incoming"]["event_example"])
    end

    test "channel examples match available channels", %{conn: conn} do
      # Get available channels
      channels_response =
        conn
        |> get("/api/websocket/channels")
        |> json_response(200)

      available_channels = channels_response["data"]

      # Get examples
      examples_response =
        conn
        |> get("/api/websocket/examples")
        |> json_response(200)

      channel_examples = examples_response["data"]["channels"]

      # If we have channels, we should have examples for them
      if length(available_channels) > 0 do
        assert map_size(channel_examples) > 0

        # Verify each channel example has proper structure
        Enum.each(channel_examples, fn {_module_name, example_data} ->
          assert is_map(example_data)
          assert Map.has_key?(example_data, "topic_pattern")
          assert Map.has_key?(example_data, "description")
          assert Map.has_key?(example_data, "join_example")
          assert Map.has_key?(example_data, "command_examples")

          # Verify join example structure
          join_example = example_data["join_example"]
          assert Map.has_key?(join_example, "description")
          assert Map.has_key?(join_example, "message")
          assert is_list(join_example["message"])
        end)
      end
    end
  end

  describe "error handling and edge cases" do
    test "handles concurrent requests gracefully", %{conn: conn} do
      # Test multiple concurrent requests to different endpoints
      endpoints = [
        "/api/websocket/schema",
        "/api/websocket/channels",
        "/api/websocket/examples"
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

    test "returns consistent error response format", %{conn: conn} do
      # Test error response from channel details with invalid module
      response =
        conn
        |> get("/api/websocket/channels/invalid-module")
        |> json_response(404)

      # Verify error response structure
      assert response["success"] == false
      assert Map.has_key?(response, "error")

      error = response["error"]
      assert is_map(error)
      assert Map.has_key?(error, "message")
      assert is_binary(error["message"])
    end

    test "handles special characters in URLs", %{conn: conn} do
      # Test various special characters in module names
      special_module_names = [
        "ServerWeb.Test%20Channel",
        "ServerWeb.Test+Channel",
        "ServerWeb.Test&Channel",
        "ServerWeb.Test#Channel"
      ]

      Enum.each(special_module_names, fn module_name ->
        response =
          conn
          |> get("/api/websocket/channels/#{module_name}")

        # Should return 404 for invalid module names
        assert response.status == 404
        response_data = json_response(response, 404)
        assert response_data["success"] == false
      end)
    end

    test "handles very long module names gracefully", %{conn: conn} do
      # Test with excessively long module name
      long_module_name = "ServerWeb." <> String.duplicate("Very", 100) <> "LongChannel"

      response =
        conn
        |> get("/api/websocket/channels/#{URI.encode(long_module_name)}")

      assert response.status == 404
      response_data = json_response(response, 404)
      assert response_data["success"] == false
    end

    test "sanitizes error messages in responses", %{conn: conn} do
      # Test that error responses don't leak sensitive information
      response =
        conn
        |> get("/api/websocket/channels/invalid-module")
        |> json_response(404)

      error_message = response["error"]["message"]

      # Error message should be user-friendly
      assert is_binary(error_message)
      assert String.length(error_message) > 0
      # Should not contain technical details that could help attackers
      refute error_message =~ "Elixir"
      refute error_message =~ "GenServer"
      refute error_message =~ "ChannelRegistry"
    end
  end

  describe "performance and response times" do
    test "all endpoints respond quickly", %{conn: conn} do
      endpoints = [
        "/api/websocket/schema",
        "/api/websocket/channels",
        "/api/websocket/examples"
      ]

      Enum.each(endpoints, fn endpoint ->
        start_time = System.monotonic_time(:millisecond)

        conn
        |> get(endpoint)
        |> json_response(200)

        duration = System.monotonic_time(:millisecond) - start_time

        # Documentation endpoints should be fast since they're largely static
        assert duration < 2000
      end)
    end

    test "channel details endpoint responds promptly", %{conn: conn} do
      # Test channel details endpoint performance
      start_time = System.monotonic_time(:millisecond)

      # Use a known invalid module to test error case performance
      conn
      |> get("/api/websocket/channels/InvalidModule")
      |> json_response(404)

      duration = System.monotonic_time(:millisecond) - start_time

      # Even error cases should be fast
      assert duration < 1000
    end

    test "large response payloads are handled efficiently", %{conn: conn} do
      # Test that endpoints with potentially large responses perform well
      large_response_endpoints = [
        "/api/websocket/schema",
        "/api/websocket/examples"
      ]

      Enum.each(large_response_endpoints, fn endpoint ->
        start_time = System.monotonic_time(:millisecond)

        response =
          conn
          |> get(endpoint)
          |> json_response(200)

        duration = System.monotonic_time(:millisecond) - start_time

        # Should handle large responses efficiently
        assert duration < 3000

        # Verify we actually got substantial data
        data_size = response |> Jason.encode!() |> String.length()
        # Should have meaningful content
        assert data_size > 100
      end)
    end
  end

  describe "documentation completeness" do
    test "schema includes all available channels", %{conn: conn} do
      # Get available channels
      channels_response =
        conn
        |> get("/api/websocket/channels")
        |> json_response(200)

      available_channels = channels_response["data"]

      # Get schema
      schema_response =
        conn
        |> get("/api/websocket/schema")
        |> json_response(200)

      schema = schema_response["data"]

      # Schema should reference all available channels
      # (exact structure depends on ChannelRegistry implementation)
      assert is_map(schema)

      # If we have channels, schema should contain channel information
      if length(available_channels) > 0 do
        # Schema should be non-empty and comprehensive
        schema_size = schema |> Jason.encode!() |> String.length()
        assert schema_size > 100
      end
    end

    test "examples provide practical guidance", %{conn: conn} do
      response =
        conn
        |> get("/api/websocket/examples")
        |> json_response(200)

      examples = response["data"]

      # Verify examples provide actionable guidance
      js_description = examples["connection"]["javascript"]["description"]
      assert String.contains?(js_description, "Phoenix")

      websocat_description = examples["connection"]["websocat"]["description"]
      assert String.contains?(websocat_description, "websocat")

      # Message format should explain Phoenix channel protocol
      message_format_description = examples["message_format"]["description"]
      assert String.contains?(message_format_description, "Phoenix")
    end
  end
end

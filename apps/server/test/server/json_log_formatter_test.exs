defmodule Server.JsonLogFormatterTest do
  use ExUnit.Case, async: true

  alias Server.JsonLogFormatter

  describe "format/4" do
    setup do
      timestamp = ~N[2025-08-13 23:30:00.123]
      metadata = %{service: "test", correlation_id: "test-123"}

      %{timestamp: timestamp, metadata: metadata}
    end

    test "formats normal string messages", %{timestamp: timestamp, metadata: metadata} do
      result = JsonLogFormatter.format(:info, "normal message", timestamp, metadata)

      assert is_binary(result)
      refute String.contains?(result, "FORMATTER CRASH")

      json = result |> String.trim() |> Jason.decode!()
      assert json["message"] == "normal message"
      assert json["level"] == "info"
      assert json["service"] == "test"
      assert json["correlation_id"] == "test-123"
    end

    test "formats iodata messages", %{timestamp: timestamp, metadata: metadata} do
      result = JsonLogFormatter.format(:info, ["io", "data", " message"], timestamp, metadata)

      assert is_binary(result)
      refute String.contains?(result, "FORMATTER CRASH")

      json = result |> String.trim() |> Jason.decode!()
      assert json["message"] == "iodata message"
    end

    test "formats {:string, binary} messages", %{timestamp: timestamp, metadata: metadata} do
      result = JsonLogFormatter.format(:info, {:string, "tuple message"}, timestamp, metadata)

      assert is_binary(result)
      refute String.contains?(result, "FORMATTER CRASH")

      json = result |> String.trim() |> Jason.decode!()
      assert json["message"] == "tuple message"
    end

    test "formats {:string, iodata} messages", %{timestamp: timestamp, metadata: metadata} do
      result = JsonLogFormatter.format(:info, {:string, ["complex ", "iodata"]}, timestamp, metadata)

      assert is_binary(result)
      refute String.contains?(result, "FORMATTER CRASH")

      json = result |> String.trim() |> Jason.decode!()
      assert json["message"] == "complex iodata"
    end

    test "handles complex tuple formats", %{timestamp: timestamp, metadata: metadata} do
      result = JsonLogFormatter.format(:info, {String, ["nested", " data"]}, timestamp, metadata)

      assert is_binary(result)
      refute String.contains?(result, "FORMATTER CRASH")

      json = result |> String.trim() |> Jason.decode!()
      assert json["message"] == "nested data"
    end

    test "handles unknown message formats with fallback", %{timestamp: timestamp, metadata: metadata} do
      result = JsonLogFormatter.format(:info, %{weird: "format"}, timestamp, metadata)

      assert is_binary(result)
      refute String.contains?(result, "FORMATTER CRASH")

      json = result |> String.trim() |> Jason.decode!()
      assert json["message"] == "%{weird: \"format\"}"
    end

    test "extracts top-level metadata fields", %{timestamp: timestamp} do
      metadata = %{
        service: "test_service",
        correlation_id: "test-123",
        module: "Test.Module",
        function: "test_function",
        line: 42,
        extra: "should_be_nested"
      }

      result = JsonLogFormatter.format(:info, "test", timestamp, metadata)
      json = result |> String.trim() |> Jason.decode!()

      # Top-level fields should be extracted
      assert json["service"] == "test_service"
      assert json["correlation_id"] == "test-123"
      assert json["module"] == "Test.Module"
      assert json["function"] == "test_function"
      assert json["line"] == 42

      # Non-top-level fields should be nested
      assert json["metadata"]["extra"] == "should_be_nested"
    end

    test "handles JSON encoding errors gracefully", %{timestamp: timestamp, metadata: metadata} do
      # Create data that Jason can't encode (a function)
      bad_metadata = Map.put(metadata, :bad_field, fn -> :error end)

      result = JsonLogFormatter.format(:info, "test message", timestamp, bad_metadata)

      assert is_binary(result)
      # Should fall back to safe format, not crash
      assert String.contains?(result, "test message")
    end

    test "produces valid JSON output", %{timestamp: timestamp, metadata: metadata} do
      result = JsonLogFormatter.format(:warning, "test message", timestamp, metadata)

      # Should be valid JSON
      assert {:ok, _} = result |> String.trim() |> Jason.decode()

      # Should end with newline
      assert String.ends_with?(result, "\n")
    end
  end
end

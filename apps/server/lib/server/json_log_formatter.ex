defmodule Server.JsonLogFormatter do
  @moduledoc """
  Custom JSON formatter for structured logging in production.

  Outputs logs in JSON format with standardized top-level fields and nested metadata.
  Uses Elixir's built-in JSON encoding with graceful error handling to prevent logging failures.

  ## JSON Schema

  ```json
  {
    "timestamp": "2025-01-13T10:30:00.123Z",
    "level": "info",
    "message": "Twitch API client started",
    "service": "twitch_api",
    "correlation_id": "abc-123",
    "module": "Server.Services.Twitch.ApiClient",
    "function": "init/1",
    "line": 166,
    "metadata": {
      "user_id": "141981764",
      "stream_id": "live_12345",
      "duration_ms": 42
    }
  }
  ```
  """

  # Top-level JSON fields extracted from metadata
  @top_level_fields [
    :service,
    :correlation_id,
    :request_id,
    :user_id,
    :stream_id,
    :channel_id,
    :overlay_id,
    :session_id,
    :event_type,
    :operation,
    :module,
    :function,
    :line,
    :error,
    :duration_ms
  ]

  # Logger.Formatter callback - used as {Module, :function} tuple in config
  def format(level, message, timestamp, metadata) do
    try do
      # Build the base JSON structure
      json_data = %{
        timestamp: format_iso8601_timestamp(timestamp),
        level: to_string(level),
        message: extract_message_text(message)
      }

      # Extract top-level fields from metadata
      {top_level, remaining_metadata} = extract_top_level_fields(metadata)

      # Merge top-level fields into the base structure
      json_data = Map.merge(json_data, top_level)

      # Add remaining metadata as nested object (if any)
      json_data =
        if map_size(remaining_metadata) > 0 do
          Map.put(json_data, :metadata, remaining_metadata)
        else
          json_data
        end

      # Encode to JSON with error handling
      json_string = JSON.encode!(json_data)
      json_string <> "\n"
    rescue
      error ->
        # Emergency fallback on any formatter error
        safe_fallback(level, message, timestamp, metadata, error)
    end
  end

  # Extract message text from various Logger message formats
  # Logger can send messages in different formats depending on configuration:
  # - Binary strings: "message"
  # - Iodata lists: ["part1", "part2"]
  # - Tuple format: {:string, content} - used internally by Logger
  # - Other complex formats that need string conversion

  defp extract_message_text(message) when is_binary(message), do: message
  defp extract_message_text(message) when is_list(message), do: IO.iodata_to_binary(message)

  # Handle Logger's internal {:string, content} format
  # This format was causing "FORMATTER CRASH" errors before this fix
  defp extract_message_text({:string, content}) when is_binary(content), do: content
  defp extract_message_text({:string, content}) when is_list(content), do: IO.iodata_to_binary(content)

  # Handle other tuple formats by extracting content
  defp extract_message_text({_type, content}) when is_binary(content), do: content
  defp extract_message_text({_type, content}) when is_list(content), do: IO.iodata_to_binary(content)

  # Fallback for any other format - convert to string representation
  defp extract_message_text(message), do: inspect(message)

  # Extract configured top-level fields from metadata
  defp extract_top_level_fields(metadata) do
    top_level =
      @top_level_fields
      |> Enum.reduce(%{}, fn field, acc ->
        case Map.get(metadata, field) do
          nil -> acc
          value -> Map.put(acc, field, sanitize_value(value))
        end
      end)

    # Remove extracted fields from metadata
    remaining = Map.drop(metadata, @top_level_fields)

    # Sanitize remaining metadata values
    sanitized_remaining = Map.new(remaining, fn {k, v} -> {k, sanitize_value(v)} end)

    {top_level, sanitized_remaining}
  end

  # Sanitize values to ensure JSON serializability
  defp sanitize_value(value) when is_binary(value), do: value
  defp sanitize_value(value) when is_number(value), do: value
  defp sanitize_value(value) when is_boolean(value), do: value
  defp sanitize_value(value) when is_atom(value), do: to_string(value)

  defp sanitize_value(value) when is_list(value) do
    Enum.map(value, &sanitize_value/1)
  end

  defp sanitize_value(value) when is_map(value) do
    Map.new(value, fn {k, v} -> {sanitize_value(k), sanitize_value(v)} end)
  end

  defp sanitize_value(value) do
    # Convert complex terms to strings as fallback
    inspect(value)
  end

  # Format timestamp to ISO 8601 standard for machine readability
  defp format_iso8601_timestamp(timestamp) do
    # Logger typically provides NaiveDateTime, convert to ISO 8601 string
    NaiveDateTime.to_iso8601(timestamp)
  end

  # Safe fallback when JSON encoding fails
  defp safe_fallback(level, message, timestamp, metadata, error) do
    # Use default Logger format as emergency fallback
    fallback_msg = "JSON_FORMATTER_ERROR: #{inspect(error)}"

    formatted_time = format_iso8601_timestamp(timestamp)
    formatted_message = extract_message_text(message)
    formatted_metadata = inspect(metadata, limit: 100, printable_limit: 200)

    "#{formatted_time} [#{level}] #{formatted_message} #{formatted_metadata} (#{fallback_msg})\n"
  end
end

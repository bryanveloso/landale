defmodule Server.Schemas.WebSocketSchema do
  @moduledoc """
  Schema definitions for WebSocket message validation.

  Ensures consistent structure for WebSocket payloads, preventing
  crashes from mixed access patterns in channels.

  ## Message Types

  ### Phoenix Channel Message
      %{
        event: "phx_join" | "phx_leave" | "custom_event",
        topic: "room:123",
        payload: %{...},
        ref: "1",
        join_ref: "1"
      }

  ### Custom Event Payload
      %{
        type: "notification" | "update" | "command",
        data: %{...},
        correlation_id: "uuid",
        timestamp: ~U[2024-01-01 00:00:00Z]
      }
  """

  @doc """
  Validates a Phoenix channel message.

  ## Returns
  - `{:ok, normalized_message}` - Valid message with atom keys
  - `{:error, reason}` - Validation failure
  """
  @spec validate_channel_message(any()) :: {:ok, map()} | {:error, term()}
  def validate_channel_message(data) when is_map(data) do
    # Normalize using BoundaryConverter
    with {:ok, normalized} <- Server.BoundaryConverter.from_external(data),
         :ok <- validate_channel_fields(normalized) do
      {:ok, normalized}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_channel_message(data) do
    {:error, {:invalid_type, "Expected map, got #{inspect(data)}"}}
  end

  @doc """
  Validates a custom event payload.

  ## Returns
  - `{:ok, normalized_payload}` - Valid payload with atom keys
  - `{:error, reason}` - Validation failure
  """
  @spec validate_event_payload(any()) :: {:ok, map()} | {:error, term()}
  def validate_event_payload(data) when is_map(data) do
    with {:ok, normalized} <- Server.BoundaryConverter.from_external(data),
         :ok <- validate_event_fields(normalized) do
      {:ok, add_metadata(normalized)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_event_payload(data) do
    {:error, {:invalid_type, "Expected map, got #{inspect(data)}"}}
  end

  @doc """
  Validates any WebSocket data generically.

  Attempts to determine the message type and validate accordingly.
  """
  @spec validate(any()) :: {:ok, map()} | {:error, term()}
  def validate(data) when is_map(data) do
    cond do
      # Phoenix channel message (has event and topic)
      Map.has_key?(data, :event) or Map.has_key?(data, "event") ->
        validate_channel_message(data)

      # Custom event payload (has type)
      Map.has_key?(data, :type) or Map.has_key?(data, "type") ->
        validate_event_payload(data)

      # Generic payload - just normalize
      true ->
        Server.BoundaryConverter.from_external(data)
    end
  end

  def validate(data) do
    {:error, {:invalid_type, "Expected map, got #{inspect(data)}"}}
  end

  # Private validation functions

  defp validate_channel_fields(data) do
    errors = []

    # Check event field
    errors =
      case Map.get(data, :event) do
        nil -> [{:event, "Required field missing"} | errors]
        event when is_binary(event) -> errors
        event -> [{:event, "Expected string, got #{inspect(event)}"} | errors]
      end

    # Check topic field
    errors =
      case Map.get(data, :topic) do
        nil -> [{:topic, "Required field missing"} | errors]
        topic when is_binary(topic) -> errors
        topic -> [{:topic, "Expected string, got #{inspect(topic)}"} | errors]
      end

    # Check payload field (optional but must be a map if present)
    errors =
      case Map.get(data, :payload) do
        nil -> errors
        payload when is_map(payload) -> errors
        payload -> [{:payload, "Expected map, got #{inspect(payload)}"} | errors]
      end

    # Check ref field (optional but must be a string if present)
    errors =
      case Map.get(data, :ref) do
        nil -> errors
        ref when is_binary(ref) -> errors
        # Allow integers, will be converted
        ref when is_integer(ref) -> errors
        ref -> [{:ref, "Expected string or integer, got #{inspect(ref)}"} | errors]
      end

    case errors do
      [] -> :ok
      errors -> {:error, {:validation_errors, Enum.reverse(errors)}}
    end
  end

  defp validate_event_fields(data) do
    errors = []

    # Check type field
    errors =
      case Map.get(data, :type) do
        nil -> [{:type, "Required field missing"} | errors]
        type when is_binary(type) -> errors
        # Allow atoms
        type when is_atom(type) -> errors
        type -> [{:type, "Expected string or atom, got #{inspect(type)}"} | errors]
      end

    # Check data field (optional but must be a map if present)
    errors =
      case Map.get(data, :data) do
        nil -> errors
        data when is_map(data) -> errors
        data -> [{:data, "Expected map, got #{inspect(data)}"} | errors]
      end

    # Check correlation_id (optional but recommended)
    errors =
      case Map.get(data, :correlation_id) do
        nil -> errors
        id when is_binary(id) -> errors
        id -> [{:correlation_id, "Expected string, got #{inspect(id)}"} | errors]
      end

    case errors do
      [] -> :ok
      errors -> {:error, {:validation_errors, Enum.reverse(errors)}}
    end
  end

  defp add_metadata(data) do
    data
    |> ensure_correlation_id()
    |> ensure_timestamp()
  end

  defp ensure_correlation_id(data) do
    if Map.has_key?(data, :correlation_id) do
      data
    else
      # Generate a correlation ID if missing
      Map.put(data, :correlation_id, generate_correlation_id())
    end
  end

  defp ensure_timestamp(data) do
    if Map.has_key?(data, :timestamp) do
      data
    else
      Map.put(data, :timestamp, DateTime.utc_now())
    end
  end

  defp generate_correlation_id do
    # Simple UUID v4 generation
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end

  @doc """
  Creates sample valid messages for testing.
  """
  @spec sample_channel_message() :: map()
  def sample_channel_message do
    %{
      event: "custom_event",
      topic: "room:lobby",
      payload: %{
        message: "Hello, world!",
        user: "test_user"
      },
      ref: "1",
      join_ref: "1"
    }
  end

  @spec sample_event_payload() :: map()
  def sample_event_payload do
    %{
      type: "notification",
      data: %{
        title: "Test Notification",
        body: "This is a test",
        priority: "normal"
      },
      correlation_id: "test-#{:rand.uniform(1000)}",
      timestamp: DateTime.utc_now()
    }
  end
end

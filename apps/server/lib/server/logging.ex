defmodule Server.Logging do
  @moduledoc """
  Standardized logging utilities for the Landale server.

  Provides consistent logging patterns across all services using Elixir's
  native Logger.metadata/1 system for structured logging.

  ## Usage

  Set service context once per process:

      Server.Logging.set_service_context(:twitch, user_id: "12345")
      Logger.info("Connection established")  # Includes service and user_id

  Use standard helpers for common patterns:

      Server.Logging.log_timing("Token validation", start_time)
      Server.Logging.log_error("Operation failed", reason)
  """

  require Logger

  @doc """
  Sets service context metadata for all subsequent log messages in the current process.

  This leverages Elixir's Logger.metadata/1 to set process-level context that will
  be included in all log messages from this process.
  """
  def set_service_context(service, additional_metadata \\ []) do
    base_metadata = [service: service]
    Logger.metadata(base_metadata ++ additional_metadata)
  end

  @doc """
  Generates and sets a correlation ID for the current process.

  Returns the generated correlation ID for use in cross-service calls.
  """
  def set_correlation_id(correlation_id \\ nil) do
    id = correlation_id || generate_correlation_id()
    Logger.metadata(correlation_id: id)
    id
  end

  @doc """
  Logs operation timing following Elixir conventions.

  Uses inline metadata to avoid modifying process-level context.
  """
  def log_timing(operation, start_time, additional_metadata \\ []) do
    duration_ms = System.monotonic_time(:millisecond) - start_time

    # Use inline metadata to avoid process metadata collision
    Logger.info(
      "Operation completed",
      [operation: operation, duration_ms: duration_ms] ++ additional_metadata
    )
  end

  @doc """
  Logs errors with consistent formatting following Elixir patterns.

  Always uses :error metadata key for the reason, following Logger conventions.
  """
  def log_error(message, reason, additional_metadata \\ []) do
    Logger.error(message, [error: reason] ++ additional_metadata)
  end

  @doc """
  Logs connection lifecycle events with standard patterns.
  """
  def log_connection_event(event, status, additional_metadata \\ []) do
    metadata = [event: event, status: status] ++ additional_metadata

    case status do
      :connected -> Logger.info("Connection established", metadata)
      :disconnected -> Logger.warning("Connection lost", metadata)
      :connecting -> Logger.info("Connection attempt started", metadata)
      :failed -> Logger.error("Connection failed", metadata)
      _ -> Logger.info("Connection event", metadata)
    end
  end

  @doc """
  Logs state transitions with clear before/after context.
  """
  def log_state_change(component, from_state, to_state, additional_metadata \\ []) do
    metadata =
      [
        component: component,
        from_state: from_state,
        to_state: to_state
      ] ++ additional_metadata

    Logger.info("State changed", metadata)
  end

  @doc """
  Standardized debug logging for protocol messages.
  """
  def log_protocol_message(direction, message_type, additional_metadata \\ []) do
    metadata =
      [
        direction: direction,
        message_type: message_type
      ] ++ additional_metadata

    Logger.debug("Protocol message", metadata)
  end

  @doc """
  Logs unhandled messages with helpful debugging context.
  """
  def log_unhandled(component, item_type, item, additional_metadata \\ []) do
    metadata =
      [
        component: component,
        item_type: item_type,
        item_summary: summarize_item(item)
      ] ++ additional_metadata

    Logger.debug("Item unhandled", metadata)
  end

  # Private helper to summarize complex data for debugging
  defp summarize_item(item) when is_map(item) do
    keys = Map.keys(item)
    "map(#{length(keys)}): #{inspect(Enum.take(keys, 5))}"
  end

  defp summarize_item(item) when is_tuple(item) do
    "tuple(#{tuple_size(item)}): #{inspect(elem(item, 0))}"
  end

  defp summarize_item(item) when is_list(item) do
    "list(#{length(item)})"
  end

  defp summarize_item(item) when is_atom(item) do
    "atom: #{item}"
  end

  defp summarize_item(item) do
    "#{inspect(item.__struct__ || :unknown)}"
  end

  # Private helper to generate correlation IDs
  defp generate_correlation_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end

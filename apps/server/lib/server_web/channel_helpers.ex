defmodule ServerWeb.ChannelHelpers do
  @moduledoc """
  Helper functions for Phoenix channels.
  
  Provides common functionality for channels including correlation ID setup,
  error handling, and event batching support.
  """

  require Logger
  alias Server.CorrelationId
  alias ServerWeb.ResponseBuilder

  @doc """
  Set up correlation ID for the socket session.
  Should be called in join/3.
  """
  def setup_correlation_id(socket, module) do
    correlation_id = CorrelationId.from_context(assigns: socket.assigns)
    CorrelationId.put_logger_metadata(correlation_id)

    Logger.info("Channel joined",
      channel: module,
      topic: socket.topic,
      correlation_id: correlation_id
    )

    Phoenix.Socket.assign(socket, :correlation_id, correlation_id)
  end

  @doc """
  Subscribe to multiple PubSub topics at once.
  """
  def subscribe_to_topics(topics) when is_list(topics) do
    Enum.each(topics, &Phoenix.PubSub.subscribe(Server.PubSub, &1))
  end

  @doc """
  Send initial state after join with error handling.
  """
  def send_after_join(socket, message \\ :after_join) do
    send(self(), message)
    socket
  end

  @doc """
  Standard ping handler for connection health.
  Include in your handle_in/3 clauses.
  """
  def handle_ping(_payload, socket) do
    {:reply, ResponseBuilder.success(%{pong: true, timestamp: System.system_time(:second)}), socket}
  end

  @doc """
  Log unhandled channel messages.
  Call from your catch-all handle_in/3 clause.
  """
  def log_unhandled_message(event, payload, socket, module) do
    Logger.warning("Unhandled channel message",
      channel: module,
      event: event,
      payload: inspect(payload),
      correlation_id: Map.get(socket.assigns, :correlation_id, "unknown")
    )
  end

  @doc """
  Log and push an error to the client.
  """
  def push_error(socket, event, error_type, message, module) do
    Logger.error("Channel error",
      channel: module,
      event: event,
      error_type: error_type,
      message: message,
      correlation_id: Map.get(socket.assigns, :correlation_id, "unknown")
    )

    Phoenix.Channel.push(socket, event, ResponseBuilder.error(error_type, message))
    socket
  end

  @doc """
  Execute with a fallback on error.
  Useful for handling StreamProducer or other service failures gracefully.
  """
  def with_fallback(socket, event_name, primary_fn, fallback_fn) do
    try do
      primary_fn.()
    rescue
      error ->
        Logger.error("Failed to execute #{event_name}, using fallback",
          error: inspect(error),
          correlation_id: Map.get(socket.assigns, :correlation_id, "unknown")
        )

        fallback_fn.()
    end
  end
end
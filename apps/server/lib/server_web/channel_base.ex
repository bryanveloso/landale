defmodule ServerWeb.ChannelBase do
  @moduledoc """
  Base module for Phoenix channels that provides common WebSocket resilience patterns.

  This module provides helper functions and common patterns for our channel implementations including:
  - Correlation ID management helpers
  - Standard event subscription helpers
  - Common error handling patterns
  - Response building helpers

  ## Usage

      defmodule ServerWeb.MyChannel do
        use ServerWeb.ChannelBase
        
        @impl true
        def join(topic, payload, socket) do
          socket = setup_correlation_id(socket)
          # Channel-specific join logic
          {:ok, socket}
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      use ServerWeb, :channel

      require Logger

      alias Server.CorrelationId
      alias ServerWeb.ResponseBuilder

      # Helper functions for channels

      @doc """
      Set up correlation ID for the socket session.
      Should be called in join/3.
      """
      def setup_correlation_id(socket) do
        correlation_id = CorrelationId.from_context(assigns: socket.assigns)
        CorrelationId.put_logger_metadata(correlation_id)

        Logger.info("Channel joined",
          channel: __MODULE__,
          topic: socket.topic,
          correlation_id: correlation_id
        )

        assign(socket, :correlation_id, correlation_id)
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
      def log_unhandled_message(event, payload, socket) do
        Logger.warning("Unhandled channel message",
          channel: __MODULE__,
          event: event,
          payload: inspect(payload),
          correlation_id: Map.get(socket.assigns, :correlation_id, "unknown")
        )
      end

      @doc """
      Log and push an error to the client.
      """
      def push_error(socket, event, error_type, message) do
        Logger.error("Channel error",
          channel: __MODULE__,
          event: event,
          error_type: error_type,
          message: message,
          correlation_id: Map.get(socket.assigns, :correlation_id, "unknown")
        )

        push(socket, event, ResponseBuilder.error(error_type, message))
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

      @doc """
      Support for event batching pattern.
      Accumulates events and flushes them periodically or when batch is full.
      """
      defmodule EventBatcher do
        @moduledoc """
        GenServer for batching events to reduce message frequency.

        Accumulates events and flushes them when batch size is reached
        or after a timeout period. This improves performance for high-frequency
        event streams by reducing the number of WebSocket messages sent.
        """

        use GenServer

        @default_batch_size 50
        # milliseconds
        @default_flush_interval 100

        def start_link(opts) do
          GenServer.start_link(__MODULE__, opts)
        end

        def add_event(batcher, event) do
          GenServer.cast(batcher, {:add_event, event})
        end

        @impl true
        def init(opts) do
          socket = Keyword.fetch!(opts, :socket)
          event_name = Keyword.get(opts, :event_name, "event_batch")
          batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
          flush_interval = Keyword.get(opts, :flush_interval, @default_flush_interval)

          schedule_flush(flush_interval)

          {:ok,
           %{
             socket: socket,
             event_name: event_name,
             batch_size: batch_size,
             flush_interval: flush_interval,
             events: []
           }}
        end

        @impl true
        def handle_cast({:add_event, event}, state) do
          new_events = [event | state.events]

          if length(new_events) >= state.batch_size do
            flush_events(state.socket, state.event_name, Enum.reverse(new_events))
            {:noreply, %{state | events: []}}
          else
            {:noreply, %{state | events: new_events}}
          end
        end

        @impl true
        def handle_info(:flush, state) do
          if state.events != [] do
            flush_events(state.socket, state.event_name, Enum.reverse(state.events))
          end

          schedule_flush(state.flush_interval)
          {:noreply, %{state | events: []}}
        end

        defp flush_events(socket, event_name, events) do
          push(socket, event_name, %{
            events: events,
            count: length(events),
            timestamp: System.system_time(:millisecond)
          })
        end

        defp schedule_flush(interval) do
          Process.send_after(self(), :flush, interval)
        end
      end
    end
  end
end

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

      import ServerWeb.ChannelHelpers
      alias Server.CorrelationId
      alias ServerWeb.{EventBatcher, ResponseBuilder}

      # Wrapper functions that pass __MODULE__ to the helpers

      def setup_correlation_id(socket) do
        ServerWeb.ChannelHelpers.setup_correlation_id(socket, __MODULE__)
      end

      def log_unhandled_message(event, payload, socket) do
        ServerWeb.ChannelHelpers.log_unhandled_message(event, payload, socket, __MODULE__)
      end

      def push_error(socket, event, error_type, message) do
        ServerWeb.ChannelHelpers.push_error(socket, event, error_type, message, __MODULE__)
      end

      # Helper to emit telemetry after successful join
      def emit_joined_telemetry(topic, socket) do
        :telemetry.execute(
          [:landale, :channel, :joined],
          %{system_time: System.system_time()},
          %{
            topic: topic,
            socket_id: Map.get(socket.assigns, :correlation_id, "unknown")
          }
        )
      end

      # Helper to emit telemetry on channel leave
      def emit_left_telemetry(socket) do
        if Map.has_key?(socket, :topic) do
          :telemetry.execute(
            [:landale, :channel, :left],
            %{system_time: System.system_time()},
            %{
              topic: socket.topic,
              socket_id: Map.get(socket.assigns, :correlation_id, "unknown")
            }
          )
        end
      end

      # Default terminate implementation that emits telemetry
      def terminate(_reason, socket) do
        emit_left_telemetry(socket)
        :ok
      end

      defoverridable terminate: 2
    end
  end
end

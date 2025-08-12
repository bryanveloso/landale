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
      alias ServerWeb.ResponseBuilder

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

      def emit_joined_telemetry(_topic, _socket) do
        :ok
      end

      def emit_left_telemetry(_socket) do
        :ok
      end

      def terminate(_reason, _socket) do
        :ok
      end

      defoverridable terminate: 2
    end
  end
end

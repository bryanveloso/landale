defmodule ServerWeb.TelemetryChannelSimpleTest do
  use ServerWeb.ChannelCase
  alias ServerWeb.TelemetryChannel

  setup do
    {:ok, _, socket} =
      ServerWeb.UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(TelemetryChannel, "dashboard:telemetry")

    %{socket: socket}
  end

  describe "basic channel operations" do
    test "successfully joins the telemetry channel", %{socket: socket} do
      # The join was successful if we have a socket
      assert socket != nil
      assert socket.assigns[:subscribed] == true
      assert socket.assigns[:correlation_id] != nil
    end

    test "responds to ping with pong", %{socket: socket} do
      ref = push(socket, "ping", %{})
      assert_reply ref, :ok, response
      assert response.success == true
      assert response.data.pong == true
    end

    test "returns error for unknown commands", %{socket: socket} do
      ref = push(socket, "unknown_command", %{})
      assert_reply ref, :error, response

      assert response.success == false
      assert response.error.code == "unknown_command"
      assert String.contains?(response.error.message, "Unknown command")
    end
  end

  describe "telemetry broadcasts" do
    test "forwards telemetry events to client", %{socket: socket} do
      send(socket.channel_pid, {:telemetry_event, "test_event", %{data: "test"}})
      assert_push "test_event", %{data: "test"}
    end

    test "forwards health updates", %{socket: socket} do
      send(socket.channel_pid, {:telemetry_health_event, %{status: "healthy"}})
      assert_push "health_update", %{status: "healthy"}
    end

    test "forwards websocket metrics", %{socket: socket} do
      send(socket.channel_pid, {:telemetry_websocket_event, %{connections: 5}})
      assert_push "websocket_metrics", %{connections: 5}
    end

    test "forwards performance metrics", %{socket: socket} do
      send(socket.channel_pid, {:telemetry_metrics_event, %{cpu: 50}})
      assert_push "performance_metrics", %{cpu: 50}
    end

    test "forwards service health updates", %{socket: socket} do
      health_data = %{status: "connected", latency: 10}
      send(socket.channel_pid, {:service_health, "obs", health_data})

      assert_push "service_health_update", payload
      assert payload.service == "obs"
      assert payload.health == health_data
      assert Map.has_key?(payload, :timestamp)
    end
  end

  describe "error handling" do
    test "handles unexpected messages without crashing", %{socket: socket} do
      # Send various unexpected messages
      send(socket.channel_pid, :unexpected_atom)
      send(socket.channel_pid, {:unexpected_tuple, "data"})
      send(socket.channel_pid, "unexpected_string")

      # Channel should still be responsive
      ref = push(socket, "ping", %{})
      assert_reply ref, :ok, response
      assert response.success == true
    end
  end
end

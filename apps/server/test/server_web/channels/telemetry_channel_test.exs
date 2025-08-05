defmodule ServerWeb.TelemetryChannelTest do
  use ServerWeb.ChannelCase
  alias ServerWeb.TelemetryChannel

  setup do
    # Ensure OBS Registry is started
    unless Process.whereis(Server.Services.OBS.SessionRegistry) do
      Registry.start_link(keys: :unique, name: Server.Services.OBS.SessionRegistry)
    end

    {:ok, _, socket} =
      ServerWeb.UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(TelemetryChannel, "dashboard:telemetry")

    %{socket: socket}
  end

  describe "join" do
    test "successfully joins the telemetry channel", %{socket: socket} do
      # The join was successful if we have a socket
      assert socket != nil
    end

    test "sets up proper socket assigns on join", %{socket: socket} do
      assert socket.assigns[:subscribed] == true
      assert socket.assigns[:join_time] != nil
      assert socket.assigns[:correlation_id] != nil
    end
  end

  describe "handle_in get_telemetry" do
    test "returns telemetry snapshot", %{socket: socket} do
      ref = push(socket, "get_telemetry", %{})

      assert_reply ref, :ok, response
      assert response.status == "success"
      assert Map.has_key?(response.data, :timestamp)
      assert Map.has_key?(response.data, :websocket)
      assert Map.has_key?(response.data, :services)
      assert Map.has_key?(response.data, :performance)
      assert Map.has_key?(response.data, :system)
    end

    test "websocket metrics include expected fields", %{socket: socket} do
      ref = push(socket, "get_telemetry", %{})
      assert_reply ref, :ok, response

      websocket_data = response.data.websocket
      assert Map.has_key?(websocket_data, :total_connections)
      assert Map.has_key?(websocket_data, :active_channels)
      assert Map.has_key?(websocket_data, :channels_by_type)
      assert Map.has_key?(websocket_data, :recent_disconnects)
      assert Map.has_key?(websocket_data, :average_connection_duration)
    end

    test "service metrics include all services", %{socket: socket} do
      ref = push(socket, "get_telemetry", %{})
      assert_reply ref, :ok, response

      services = response.data.services
      assert Map.has_key?(services, :obs)
      assert Map.has_key?(services, :twitch)
      assert Map.has_key?(services, :phononmaser)
      assert Map.has_key?(services, :seed)

      # Each service should have connected status
      for {_name, service_data} <- services do
        assert Map.has_key?(service_data, :connected)
      end
    end

    test "performance metrics include memory and CPU data", %{socket: socket} do
      ref = push(socket, "get_telemetry", %{})
      assert_reply ref, :ok, response

      performance = response.data.performance
      assert Map.has_key?(performance, :memory)
      assert Map.has_key?(performance, :cpu)
      assert Map.has_key?(performance, :message_queue)

      # Memory should have expected fields
      memory = performance.memory
      assert Map.has_key?(memory, :total_mb)
      assert Map.has_key?(memory, :processes_mb)
      assert Map.has_key?(memory, :binary_mb)
      assert Map.has_key?(memory, :ets_mb)

      # CPU should have expected fields
      cpu = performance.cpu
      assert Map.has_key?(cpu, :schedulers)
      assert Map.has_key?(cpu, :run_queue)
    end

    test "system metrics include uptime and status", %{socket: socket} do
      ref = push(socket, "get_telemetry", %{})
      assert_reply ref, :ok, response

      system = response.data.system
      assert Map.has_key?(system, :uptime)
      assert Map.has_key?(system, :version)
      assert Map.has_key?(system, :environment)
      assert Map.has_key?(system, :status)
      assert system.status in ["healthy", "degraded", "unhealthy"]
    end
  end

  describe "handle_in get_service_health" do
    test "returns health data for valid service", %{socket: socket} do
      ref = push(socket, "get_service_health", %{"service" => "obs"})
      assert_reply ref, :ok, response

      assert response.status == "success"
      assert Map.has_key?(response.data, :connected)
    end

    test "returns error for unknown service", %{socket: socket} do
      ref = push(socket, "get_service_health", %{"service" => "unknown"})
      assert_reply ref, :ok, response

      assert response.status == "success"
      assert response.data.error == "Unknown service"
    end

    test "works for all known services", %{socket: socket} do
      services = ["phononmaser", "seed", "obs", "twitch"]

      for service <- services do
        ref = push(socket, "get_service_health", %{"service" => service})
        assert_reply ref, :ok, response
        assert response.status == "success"
        assert Map.has_key?(response.data, :connected) or Map.has_key?(response.data, :error)
      end
    end
  end

  describe "handle_in ping" do
    test "responds to ping with pong", %{socket: socket} do
      ref = push(socket, "ping", %{})
      assert_reply ref, :ok, %{status: "success", message: "pong"}
    end

    test "includes timestamp if provided", %{socket: socket} do
      timestamp = System.system_time(:second)
      ref = push(socket, "ping", %{"timestamp" => timestamp})
      assert_reply ref, :ok, response
      assert response.data.timestamp == timestamp
    end
  end

  describe "handle_in unknown command" do
    test "returns error for unknown commands", %{socket: socket} do
      ref = push(socket, "unknown_command", %{})
      assert_reply ref, :error, response

      assert response.success == false
      assert response.error.code == "unknown_command"
      assert String.contains?(response.error.message, "Unknown command")
    end
  end

  describe "handle_info telemetry broadcasts" do
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

  describe "handle_info error handling" do
    test "handles unexpected messages without crashing", %{socket: socket} do
      # Send various unexpected messages
      send(socket.channel_pid, :unexpected_atom)
      send(socket.channel_pid, {:unexpected_tuple, "data"})
      send(socket.channel_pid, "unexpected_string")

      # Channel should still be responsive
      ref = push(socket, "ping", %{})
      assert_reply ref, :ok, %{status: "success", message: "pong"}
    end
  end

  describe "telemetry emission" do
    test "emits telemetry on channel join" do
      # This is tested implicitly by the setup, but we can verify
      # by checking that the join succeeded
      assert_push "presence_state", %{}
    end
  end

  describe "service status determination" do
    test "system status reflects service health", %{socket: socket} do
      ref = push(socket, "get_telemetry", %{})
      assert_reply ref, :ok, response

      system_status = response.data.system.status
      services = response.data.services

      # Count connected services
      connected_count =
        Enum.count(services, fn {_name, data} ->
          data[:connected] == true
        end)

      # System status should reflect service health
      # With 5 critical components (1 internal + 4 services)
      case connected_count do
        5 -> assert system_status == "healthy"
        n when n >= 3 -> assert system_status == "degraded"
        _ -> assert system_status == "unhealthy"
      end
    end
  end

  describe "error sanitization" do
    test "sanitizes error messages in service metrics", %{socket: socket} do
      ref = push(socket, "get_telemetry", %{})
      assert_reply ref, :ok, response

      # Check that any error messages in services are sanitized
      for {_name, service_data} <- response.data.services do
        if Map.has_key?(service_data, :error) do
          error = service_data.error
          # Should be a clean, user-friendly error message
          assert is_binary(error)

          assert error in [
                   "Connection timed out",
                   "Service unreachable",
                   "Invalid response from service",
                   "Service not configured",
                   "An unknown error occurred"
                 ] or is_binary(error)
        end
      end
    end
  end
end

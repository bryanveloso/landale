defmodule ServerWeb.ServicesChannel do
  @moduledoc """
  Phoenix Channel for service management via Nurvus.

  Proxies service control commands to the Nurvus process manager.

  ## Commands
  - `start` - Start a service
  - `stop` - Stop a service
  - `restart` - Restart a service
  - `get_status` - Get service status
  """

  use ServerWeb.ChannelBase
  alias ServerWeb.ResponseBuilder

  @nurvus_port 4001
  # zelan's IP
  @nurvus_host "100.112.39.113"
  @allowed_services ["phononmaser", "seed"]

  @impl true
  def join("dashboard:services", _payload, socket) do
    socket =
      socket
      |> setup_correlation_id()
      |> assign(:subscribed, true)

    # Emit telemetry for this channel join
    emit_joined_telemetry("dashboard:services", socket)

    {:ok, socket}
  end

  @impl true
  def handle_in("start", %{"service" => service_name}, socket) when service_name in @allowed_services do
    # Start async task and store reference
    task = Task.async(fn -> call_nurvus(service_name, "start") end)
    socket = assign(socket, :pending_task, {task, "start", service_name})
    {:noreply, socket}
  end

  @impl true
  def handle_in("stop", %{"service" => service_name}, socket) when service_name in @allowed_services do
    # Start async task and store reference
    task = Task.async(fn -> call_nurvus(service_name, "stop") end)
    socket = assign(socket, :pending_task, {task, "stop", service_name})
    {:noreply, socket}
  end

  @impl true
  def handle_in("restart", %{"service" => service_name}, socket) when service_name in @allowed_services do
    # Start async task and store reference
    task = Task.async(fn -> call_nurvus(service_name, "restart") end)
    socket = assign(socket, :pending_task, {task, "restart", service_name})
    {:noreply, socket}
  end

  @impl true
  def handle_in("get_status", %{"service" => service_name}, socket) when service_name in @allowed_services do
    # Start async task and store reference
    task = Task.async(fn -> get_nurvus_status(service_name) end)
    socket = assign(socket, :pending_task, {task, "get_status", service_name})
    {:noreply, socket}
  end

  @impl true
  def handle_in(event, %{"service" => service_name}, socket) do
    if service_name in @allowed_services do
      log_unhandled_message(event, %{"service" => service_name}, socket)
      {:error, response} = ResponseBuilder.error("unknown_command", "Unknown command: #{event}")
      {:reply, {:error, response}, socket}
    else
      {:error, response} = ResponseBuilder.error("invalid_service", "Service #{service_name} is not controllable")
      {:reply, {:error, response}, socket}
    end
  end

  @impl true
  def handle_in("get_telemetry", _params, socket) do
    # Gather service status data for the dashboard
    telemetry_data = gather_telemetry_data()

    # Push telemetry update to the client
    push(socket, "telemetry_update", telemetry_data)

    {:noreply, socket}
  end

  @impl true
  def handle_in("ping", payload, socket) do
    handle_ping(payload, socket)
  end

  # Catch-all for unhandled client messages
  @impl true
  def handle_in(event, payload, socket) do
    log_unhandled_message(event, payload, socket)
    {:reply, ResponseBuilder.error("unknown_command", "Unknown command: #{event}"), socket}
  end

  # Handle async task results for service commands
  @impl true
  def handle_info({ref, result}, socket) do
    # Check if this is our pending task
    case socket.assigns[:pending_task] do
      {%Task{ref: ^ref}, action, service_name} ->
        # Process task result
        socket = handle_nurvus_result(result, action, service_name, socket)
        # Clean up the task reference
        Process.demonitor(ref, [:flush])
        {:noreply, assign(socket, :pending_task, nil)}

      _ ->
        # Not our task, ignore
        {:noreply, socket}
    end
  end

  # Handle task failures (DOWN messages)
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, socket) do
    case socket.assigns[:pending_task] do
      {%Task{ref: ^ref}, action, service_name} ->
        Logger.error("Nurvus task failed", action: action, service: service_name, reason: inspect(reason))
        {:error, response} = ResponseBuilder.error("task_failed", "Service operation failed")
        push(socket, "error", response)
        {:noreply, assign(socket, :pending_task, nil)}

      _ ->
        {:noreply, socket}
    end
  end

  # Catch-all handler to prevent crashes from unexpected messages
  @impl true
  def handle_info(unhandled_msg, socket) do
    Logger.warning("Unhandled message in #{__MODULE__}",
      message: inspect(unhandled_msg)
    )

    {:noreply, socket}
  end

  # Private functions

  defp call_nurvus(service_name, action) do
    url = "http://#{@nurvus_host}:#{@nurvus_port}/api/processes/#{service_name}/#{action}"

    Logger.info("Calling Nurvus: #{action} #{service_name}")

    headers = [{"Content-Type", "application/json"}]

    case Server.HttpClient.post(url, "", headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, response} ->
            Logger.info("Nurvus #{action} successful for #{service_name}")
            {:ok, response}

          {:error, _} ->
            {:ok, %{"status" => action, "process_id" => service_name}}
        end

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, "Process not found in Nurvus"}

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "Nurvus returned HTTP #{status_code}"}

      {:error, %HTTPoison.Error{reason: :econnrefused}} ->
        {:error, "Nurvus not running on port #{@nurvus_port}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp get_nurvus_status(service_name) do
    url = "http://#{@nurvus_host}:#{@nurvus_port}/api/processes/#{service_name}"

    case Server.HttpClient.get(url, []) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, response} ->
            {:ok, response}

          {:error, _} ->
            {:error, "Invalid JSON response"}
        end

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, "Process not found"}

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "HTTP #{status_code}"}

      {:error, %HTTPoison.Error{reason: :econnrefused}} ->
        {:error, "Nurvus not running"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp broadcast_service_event(socket, service_name, action, response) do
    broadcast!(socket, "service_#{action}", %{
      service: service_name,
      action: action,
      response: response,
      timestamp: System.system_time(:second)
    })
  end

  defp handle_nurvus_result(result, action, service_name, socket) do
    case result do
      {:ok, response} ->
        # Map action to event name
        event_name =
          case action do
            "start" -> "starting"
            "stop" -> "stopping"
            "restart" -> "restarting"
            "get_status" -> "status"
            _ -> action
          end

        # Broadcast event and send response to client
        if action != "get_status" do
          broadcast_service_event(socket, service_name, event_name, response)
        end

        {:ok, success_response} = ResponseBuilder.success(response)
        push(socket, "command_result", success_response)
        socket

      {:error, reason} ->
        {:error, error_response} = ResponseBuilder.error("nurvus_error", reason)
        push(socket, "command_result", error_response)
        socket
    end
  end

  # Gather telemetry data for the dashboard
  defp gather_telemetry_data do
    # Get service metrics from SystemHealth
    services = Server.Health.SystemHealth.gather_service_metrics()

    # Get system info
    system_info = %{
      uptime: System.monotonic_time(:second),
      version: Application.spec(:server, :vsn) |> to_string(),
      environment: Application.get_env(:server, :environment, "development"),
      status: Server.Health.SystemHealth.determine_system_status()
    }

    # Return telemetry snapshot
    %{
      timestamp: System.system_time(:millisecond),
      services: services,
      system: system_info,
      overlays: []
    }
  end
end

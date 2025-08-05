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
  @http_timeout 5_000
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
    case call_nurvus(service_name, "start") do
      {:ok, response} ->
        broadcast_service_event(socket, service_name, "starting", response)
        {:reply, ResponseBuilder.success(response), socket}

      {:error, reason} ->
        {:reply, ResponseBuilder.error("nurvus_error", reason), socket}
    end
  end

  @impl true
  def handle_in("stop", %{"service" => service_name}, socket) when service_name in @allowed_services do
    case call_nurvus(service_name, "stop") do
      {:ok, response} ->
        broadcast_service_event(socket, service_name, "stopping", response)
        {:reply, ResponseBuilder.success(response), socket}

      {:error, reason} ->
        {:reply, ResponseBuilder.error("nurvus_error", reason), socket}
    end
  end

  @impl true
  def handle_in("restart", %{"service" => service_name}, socket) when service_name in @allowed_services do
    case call_nurvus(service_name, "restart") do
      {:ok, response} ->
        broadcast_service_event(socket, service_name, "restarting", response)
        {:reply, ResponseBuilder.success(response), socket}

      {:error, reason} ->
        {:reply, ResponseBuilder.error("nurvus_error", reason), socket}
    end
  end

  @impl true
  def handle_in("get_status", %{"service" => service_name}, socket) when service_name in @allowed_services do
    case get_nurvus_status(service_name) do
      {:ok, response} ->
        {:reply, ResponseBuilder.success(response), socket}

      {:error, reason} ->
        {:reply, ResponseBuilder.error("nurvus_error", reason), socket}
    end
  end

  @impl true
  def handle_in(event, %{"service" => service_name}, socket) do
    if service_name in @allowed_services do
      log_unhandled_message(event, %{"service" => service_name}, socket)
      {:reply, ResponseBuilder.error("unknown_command", "Unknown command: #{event}"), socket}
    else
      {:reply, ResponseBuilder.error("invalid_service", "Service #{service_name} is not controllable"), socket}
    end
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
    url = "http://localhost:#{@nurvus_port}/api/processes/#{service_name}/#{action}"

    Logger.info("Calling Nurvus: #{action} #{service_name}")

    headers = [{"Content-Type", "application/json"}]

    case HTTPoison.post(url, "", headers, timeout: @http_timeout, recv_timeout: @http_timeout) do
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
    url = "http://localhost:#{@nurvus_port}/api/processes/#{service_name}"

    case HTTPoison.get(url, [], timeout: @http_timeout, recv_timeout: @http_timeout) do
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
end

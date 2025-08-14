defmodule ServerWeb.DashboardChannel do
  @moduledoc """
  Phoenix Channel for real-time dashboard communication.

  Handles WebSocket connections from the React dashboard frontend,
  providing real-time updates for OBS status, system health, and
  performance metrics.

  ## Events Subscribed To
  - `dashboard` - Twitch connection and event updates
  - `obs:events` - OBS WebSocket state changes and events
  - `rainwave:events` - Rainwave music service updates
  - `system:health` - System health status updates
  - `system:performance` - Performance metrics updates

  ## Events Sent to Client
  - `initial_state` - Current system state on connection
  - `obs_event` - OBS-related events (streaming, recording, scenes)
  - `rainwave_event` - Rainwave music updates (song changes, station changes)
  - `health_update` - System health status changes
  - `performance_update` - Performance metrics updates
  - `twitch_connected` - Twitch EventSub connection established
  - `twitch_disconnected` - Twitch EventSub connection lost
  - `twitch_connection_changed` - Twitch connection state changes
  - `twitch_event` - General Twitch events (follows, subs, etc.)

  ## Incoming Commands
  - `obs:get_status` - Request current OBS status
  - `obs:start_streaming` - Start OBS streaming
  - `obs:stop_streaming` - Stop OBS streaming
  - `obs:start_recording` - Start OBS recording
  - `obs:stop_recording` - Stop OBS recording
  - `obs:set_current_scene` - Change OBS scene
  - `rainwave:get_status` - Request current Rainwave status
  - `rainwave:set_enabled` - Enable/disable Rainwave service
  - `rainwave:set_station` - Change active Rainwave station
  """

  use ServerWeb.ChannelBase

  # Backpressure and timeout configuration
  # 5 seconds for service calls
  @service_call_timeout 5_000
  # Max concurrent requests per client
  @max_concurrent_requests 10
  # 10 second sliding window
  @request_window_ms 10_000
  # Max 50 requests per 10-second window
  @max_requests_per_window 50

  @impl true
  def join("dashboard:" <> room_id, _payload, socket) do
    socket =
      socket
      |> setup_correlation_id()
      |> assign(:room_id, room_id)
      |> assign(:concurrent_requests, 0)
      |> assign(:request_history, [])
      |> assign(:last_cleanup, System.system_time(:millisecond))

    # Subscribe to relevant PubSub topics for real-time updates
    topics = [
      # For Twitch connection events
      "dashboard",
      "obs:events",
      "rainwave:events",
      "system:health",
      "system:performance"
    ]

    Logger.info("DashboardChannel subscribing to PubSub topics",
      topics: topics,
      room_id: room_id
    )

    subscribe_to_topics(topics)

    # Send initial state after join
    send_after_join(socket, :send_initial_state)

    # Emit telemetry for channel join
    emit_joined_telemetry("dashboard:#{room_id}", socket)

    {:ok, socket}
  end

  @impl true
  def handle_info(:send_initial_state, socket) do
    # Send current system state to the newly connected client
    push(socket, "initial_state", %{
      connected: true,
      timestamp: System.system_time(:second)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:obs_event, event}, socket) do
    push(socket, "obs_event", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:health_update, data}, socket) do
    push(socket, "health_update", data)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:performance_update, data}, socket) do
    push(socket, "performance_update", data)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:rainwave_event, event}, socket) do
    push(socket, "rainwave_event", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:twitch_connected, event}, socket) do
    push(socket, "twitch_connected", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:twitch_disconnected, event}, socket) do
    push(socket, "twitch_disconnected", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:twitch_connection_changed, event}, socket) do
    push(socket, "twitch_connection_changed", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:twitch_event, event}, socket) do
    Logger.info("DashboardChannel received twitch_event from PubSub",
      event_type: event[:type],
      event_id: event[:id],
      correlation_id: event[:correlation_id],
      room_id: socket.assigns[:room_id]
    )

    push(socket, "twitch_event", event)
    {:noreply, socket}
  end

  # Catch-all handler to prevent crashes from unexpected messages
  @impl true
  def handle_info(unhandled_msg, socket) do
    Logger.warning("Unhandled message in #{__MODULE__}",
      message: inspect(unhandled_msg),
      room_id: socket.assigns[:room_id]
    )

    {:noreply, socket}
  end

  # Handle incoming messages from client
  @impl true
  def handle_in("ping", payload, socket) do
    handle_ping(payload, socket)
  end

  @impl true
  def handle_in("obs:get_status", _payload, socket) do
    with {:ok, socket} <- check_backpressure(socket, "obs:get_status"),
         {:ok, socket} <- increment_concurrent_requests(socket) do
      correlation_id = socket.assigns.correlation_id

      CorrelationId.with_context(correlation_id, fn ->
        # Forward request to OBS service with timeout protection
        result =
          call_service_with_timeout(fn ->
            Server.Services.OBS.get_status()
          end)

        socket = decrement_concurrent_requests(socket)

        case result do
          {:ok, status} ->
            {:ok, response} = ResponseBuilder.success(status)
            {:reply, {:ok, response}, socket}

          {:error, :timeout} ->
            Logger.warning("OBS status request timed out",
              timeout_ms: @service_call_timeout
            )

            {:error, response} = ResponseBuilder.error("service_timeout", "Service call timed out")
            {:reply, {:error, response}, socket}

          {:error, %Server.ServiceError{} = error} ->
            Logger.warning("OBS status request failed",
              reason: error.reason,
              message: error.message
            )

            {:error, response} = ResponseBuilder.error("service_error", error.message)
            {:reply, {:error, response}, socket}

          {:error, reason} ->
            Logger.warning("OBS status request failed", reason: inspect(reason))
            {:error, response} = ResponseBuilder.error("service_error", inspect(reason))
            {:reply, {:error, response}, socket}
        end
      end)
    else
      {:error, reason} ->
        {:error, response} = ResponseBuilder.error("backpressure", reason)
        {:reply, {:error, response}, socket}
    end
  end

  @impl true
  def handle_in("obs:start_streaming", _payload, socket) do
    with {:ok, socket} <- check_backpressure(socket, "obs:start_streaming"),
         {:ok, socket} <- increment_concurrent_requests(socket) do
      result =
        call_service_with_timeout(fn ->
          Server.Services.OBS.start_streaming()
        end)

      socket = decrement_concurrent_requests(socket)

      case result do
        :ok ->
          {:ok, response} = ResponseBuilder.success(%{operation: "start_streaming"})
          {:reply, {:ok, response}, socket}

        {:error, :timeout} ->
          Logger.warning("OBS start streaming timed out",
            timeout_ms: @service_call_timeout
          )

          {:error, response} = ResponseBuilder.error("service_timeout", "Service call timed out")
          {:reply, {:error, response}, socket}

        {:error, reason} ->
          Logger.warning("OBS start streaming failed", reason: inspect(reason))
          {:error, response} = ResponseBuilder.error("operation_failed", inspect(reason))
          {:reply, {:error, response}, socket}
      end
    else
      {:error, reason} ->
        {:error, response} = ResponseBuilder.error("backpressure", reason)
        {:reply, {:error, response}, socket}
    end
  end

  @impl true
  def handle_in("obs:stop_streaming", _payload, socket) do
    with {:ok, socket} <- check_backpressure(socket, "obs:stop_streaming"),
         {:ok, socket} <- increment_concurrent_requests(socket) do
      result =
        call_service_with_timeout(fn ->
          Server.Services.OBS.stop_streaming()
        end)

      socket = decrement_concurrent_requests(socket)

      case result do
        :ok ->
          {:ok, response} = ResponseBuilder.success(%{operation: "stop_streaming"})
          {:reply, {:ok, response}, socket}

        {:error, :timeout} ->
          Logger.warning("OBS stop streaming timed out",
            timeout_ms: @service_call_timeout
          )

          {:error, response} = ResponseBuilder.error("service_timeout", "Service call timed out")
          {:reply, {:error, response}, socket}

        {:error, reason} ->
          Logger.warning("OBS stop streaming failed", reason: inspect(reason))
          {:error, response} = ResponseBuilder.error("operation_failed", inspect(reason))
          {:reply, {:error, response}, socket}
      end
    else
      {:error, reason} ->
        {:error, response} = ResponseBuilder.error("backpressure", reason)
        {:reply, {:error, response}, socket}
    end
  end

  @impl true
  def handle_in("obs:start_recording", _payload, socket) do
    with {:ok, socket} <- check_backpressure(socket, "obs:start_recording"),
         {:ok, socket} <- increment_concurrent_requests(socket) do
      result =
        call_service_with_timeout(fn ->
          Server.Services.OBS.start_recording()
        end)

      socket = decrement_concurrent_requests(socket)

      case result do
        :ok ->
          {:ok, response} = ResponseBuilder.success(%{operation: "start_recording"})
          {:reply, {:ok, response}, socket}

        {:error, :timeout} ->
          Logger.warning("OBS start recording timed out",
            timeout_ms: @service_call_timeout
          )

          {:error, response} = ResponseBuilder.error("service_timeout", "Service call timed out")
          {:reply, {:error, response}, socket}

        {:error, reason} ->
          Logger.warning("OBS start recording failed", reason: inspect(reason))
          {:error, response} = ResponseBuilder.error("operation_failed", inspect(reason))
          {:reply, {:error, response}, socket}
      end
    else
      {:error, reason} ->
        {:error, response} = ResponseBuilder.error("backpressure", reason)
        {:reply, {:error, response}, socket}
    end
  end

  @impl true
  def handle_in("obs:stop_recording", _payload, socket) do
    with {:ok, socket} <- check_backpressure(socket, "obs:stop_recording"),
         {:ok, socket} <- increment_concurrent_requests(socket) do
      result =
        call_service_with_timeout(fn ->
          Server.Services.OBS.stop_recording()
        end)

      socket = decrement_concurrent_requests(socket)

      case result do
        :ok ->
          {:ok, response} = ResponseBuilder.success(%{operation: "stop_recording"})
          {:reply, {:ok, response}, socket}

        {:error, :timeout} ->
          Logger.warning("OBS stop recording timed out",
            timeout_ms: @service_call_timeout
          )

          {:error, response} = ResponseBuilder.error("service_timeout", "Service call timed out")
          {:reply, {:error, response}, socket}

        {:error, reason} ->
          Logger.warning("OBS stop recording failed", reason: inspect(reason))
          {:error, response} = ResponseBuilder.error("operation_failed", inspect(reason))
          {:reply, {:error, response}, socket}
      end
    else
      {:error, reason} ->
        {:error, response} = ResponseBuilder.error("backpressure", reason)
        {:reply, {:error, response}, socket}
    end
  end

  @impl true
  def handle_in("obs:set_current_scene", %{"scene_name" => scene_name}, socket) do
    with {:ok, socket} <- check_backpressure(socket, "obs:set_current_scene"),
         {:ok, socket} <- increment_concurrent_requests(socket) do
      result =
        call_service_with_timeout(fn ->
          Server.Services.OBS.set_current_scene(scene_name)
        end)

      socket = decrement_concurrent_requests(socket)

      case result do
        :ok ->
          {:ok, response} = ResponseBuilder.success(%{operation: "set_current_scene"})
          {:reply, {:ok, response}, socket}

        {:error, :timeout} ->
          Logger.warning("OBS set scene timed out",
            timeout_ms: @service_call_timeout,
            scene_name: scene_name
          )

          {:error, response} = ResponseBuilder.error("service_timeout", "Service call timed out")
          {:reply, {:error, response}, socket}

        {:error, reason} ->
          Logger.warning("OBS set scene failed",
            reason: inspect(reason),
            scene_name: scene_name
          )

          {:error, response} = ResponseBuilder.error("operation_failed", inspect(reason))
          {:reply, {:error, response}, socket}
      end
    else
      {:error, reason} ->
        {:error, response} = ResponseBuilder.error("backpressure", reason)
        {:reply, {:error, response}, socket}
    end
  end

  @impl true
  def handle_in("rainwave:get_status", _payload, socket) do
    with {:ok, socket} <- check_backpressure(socket, "rainwave:get_status"),
         {:ok, socket} <- increment_concurrent_requests(socket) do
      correlation_id = socket.assigns.correlation_id

      CorrelationId.with_context(correlation_id, fn ->
        result =
          call_service_with_timeout(fn ->
            Server.Services.Rainwave.get_status()
          end)

        socket = decrement_concurrent_requests(socket)

        case result do
          {:ok, status} ->
            {:ok, response} = ResponseBuilder.success(status)
            {:reply, {:ok, response}, socket}

          {:error, :timeout} ->
            Logger.warning("Rainwave status request timed out",
              timeout_ms: @service_call_timeout
            )

            {:error, response} = ResponseBuilder.error("service_timeout", "Service call timed out")
            {:reply, {:error, response}, socket}

          {:error, reason} ->
            Logger.warning("Rainwave status request failed", reason: inspect(reason))
            {:error, response} = ResponseBuilder.error("service_error", inspect(reason))
            {:reply, {:error, response}, socket}
        end
      end)
    else
      {:error, reason} ->
        {:error, response} = ResponseBuilder.error("backpressure", reason)
        {:reply, {:error, response}, socket}
    end
  end

  @impl true
  def handle_in("rainwave:set_enabled", %{"enabled" => enabled}, socket) do
    with {:ok, socket} <- check_backpressure(socket, "rainwave:set_enabled"),
         {:ok, socket} <- increment_concurrent_requests(socket) do
      result =
        call_service_with_timeout(fn ->
          Server.Services.Rainwave.set_enabled(enabled)
        end)

      socket = decrement_concurrent_requests(socket)

      case result do
        result when result in [:ok, nil] ->
          {:ok, response} = ResponseBuilder.success(%{operation: "set_enabled", enabled: enabled})
          {:reply, {:ok, response}, socket}

        {:error, :timeout} ->
          Logger.warning("Rainwave set_enabled timed out",
            timeout_ms: @service_call_timeout,
            enabled: enabled
          )

          {:error, response} = ResponseBuilder.error("service_timeout", "Service call timed out")
          {:reply, {:error, response}, socket}

        {:error, reason} ->
          Logger.warning("Rainwave set_enabled failed",
            reason: inspect(reason),
            enabled: enabled
          )

          {:error, response} = ResponseBuilder.error("operation_failed", inspect(reason))
          {:reply, {:error, response}, socket}
      end
    else
      {:error, reason} ->
        {:error, response} = ResponseBuilder.error("backpressure", reason)
        {:reply, {:error, response}, socket}
    end
  end

  @impl true
  def handle_in("rainwave:set_station", %{"station_id" => station_id}, socket) do
    with {:ok, socket} <- check_backpressure(socket, "rainwave:set_station"),
         {:ok, socket} <- increment_concurrent_requests(socket) do
      result =
        call_service_with_timeout(fn ->
          Server.Services.Rainwave.set_station(station_id)
        end)

      socket = decrement_concurrent_requests(socket)

      case result do
        result when result in [:ok, nil] ->
          {:ok, response} = ResponseBuilder.success(%{operation: "set_station", station_id: station_id})
          {:reply, {:ok, response}, socket}

        {:error, :timeout} ->
          Logger.warning("Rainwave set_station timed out",
            timeout_ms: @service_call_timeout,
            station_id: station_id
          )

          {:error, response} = ResponseBuilder.error("service_timeout", "Service call timed out")
          {:reply, {:error, response}, socket}

        {:error, reason} ->
          Logger.warning("Rainwave set_station failed",
            reason: inspect(reason),
            station_id: station_id
          )

          {:error, response} = ResponseBuilder.error("operation_failed", inspect(reason))
          {:reply, {:error, response}, socket}
      end
    else
      {:error, reason} ->
        {:error, response} = ResponseBuilder.error("backpressure", reason)
        {:reply, {:error, response}, socket}
    end
  end

  # Test event handlers
  @impl true
  def handle_in("shout", payload, socket) do
    broadcast!(socket, "shout", payload)
    {:noreply, socket}
  end

  # Catch-all for unhandled events
  @impl true
  def handle_in(event, payload, socket) do
    log_unhandled_message(event, payload, socket)
    # DashboardChannel doesn't reply to unknown commands
    {:noreply, socket}
  end

  # Private helper functions for backpressure control

  defp check_backpressure(socket, command) do
    now = System.system_time(:millisecond)
    socket = cleanup_request_history(socket, now)

    # Count requests in the current window
    recent_requests = count_recent_requests(socket, now)

    cond do
      socket.assigns.concurrent_requests >= @max_concurrent_requests ->
        Logger.warning("DashboardChannel backpressure: max concurrent requests",
          concurrent: socket.assigns.concurrent_requests,
          max_concurrent: @max_concurrent_requests,
          command: command,
          room_id: socket.assigns.room_id
        )

        {:error, "too_many_concurrent_requests"}

      recent_requests >= @max_requests_per_window ->
        Logger.warning("DashboardChannel backpressure: rate limit exceeded",
          recent_requests: recent_requests,
          max_requests: @max_requests_per_window,
          window_ms: @request_window_ms,
          command: command,
          room_id: socket.assigns.room_id
        )

        {:error, "rate_limit_exceeded"}

      true ->
        # Add this request to history
        new_history = [now | socket.assigns.request_history]
        updated_socket = assign(socket, :request_history, new_history)
        {:ok, updated_socket}
    end
  end

  defp increment_concurrent_requests(socket) do
    new_count = socket.assigns.concurrent_requests + 1
    {:ok, assign(socket, :concurrent_requests, new_count)}
  end

  defp decrement_concurrent_requests(socket) do
    new_count = max(socket.assigns.concurrent_requests - 1, 0)
    assign(socket, :concurrent_requests, new_count)
  end

  defp cleanup_request_history(socket, now) do
    # Only cleanup every few seconds to avoid overhead
    if now - socket.assigns.last_cleanup > 5_000 do
      cutoff = now - @request_window_ms

      filtered_history =
        socket.assigns.request_history
        |> Enum.filter(fn timestamp -> timestamp > cutoff end)
        # Limit history size
        |> Enum.take(100)

      socket
      |> assign(:request_history, filtered_history)
      |> assign(:last_cleanup, now)
    else
      socket
    end
  end

  defp count_recent_requests(socket, now) do
    cutoff = now - @request_window_ms

    socket.assigns.request_history
    |> Enum.count(fn timestamp -> timestamp > cutoff end)
  end

  defp call_service_with_timeout(service_call_fn) do
    task = Task.async(service_call_fn)

    case Task.yield(task, @service_call_timeout) do
      {:ok, result} ->
        result

      nil ->
        # Task didn't complete in time
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  rescue
    exception ->
      Logger.error("Service call crashed",
        error: inspect(exception),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, :service_crashed}
  end
end

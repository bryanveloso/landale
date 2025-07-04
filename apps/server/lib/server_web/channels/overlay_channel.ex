defmodule ServerWeb.OverlayChannel do
  @moduledoc """
  Phoenix channel for real-time overlay communication with full HTTP API parity.

  Provides WebSocket access to all HTTP endpoints suitable for streaming overlays.
  Overlays are read-only display components that react to server state changes.

  ## Supported Topics

  - `overlay:obs` - OBS status, scenes, stream/recording state, stats
  - `overlay:twitch` - Twitch events and connection status
  - `overlay:ironmon` - IronMON challenges, stats, results, runs
  - `overlay:music` - Rainwave music service status and configuration
  - `overlay:system` - System health, service status, control information

  ## Available Commands

  All commands follow the pattern: `{service}:{endpoint}` matching HTTP API structure.

  ### OBS Commands
  - `obs:status` - Get current OBS status
  - `obs:scenes` - Get scene list and current scene
  - `obs:stream_status` - Get streaming status and stats
  - `obs:record_status` - Get recording status
  - `obs:stats` - Get OBS performance statistics
  - `obs:version` - Get OBS version information
  - `obs:virtual_cam` - Get virtual camera status
  - `obs:outputs` - Get output configurations

  ### Twitch Commands
  - `twitch:status` - Get Twitch EventSub connection status

  ### IronMON Commands
  - `ironmon:challenges` - List available challenges
  - `ironmon:checkpoints` - Get checkpoints for a challenge (requires: challenge_id)
  - `ironmon:checkpoint_stats` - Get statistics for a checkpoint (requires: checkpoint_id)
  - `ironmon:recent_results` - Get recent run results (optional: limit 1-100, default 10)
  - `ironmon:active_challenge` - Get current active challenge (requires: seed_id)

  ### Music Commands
  - `rainwave:status` - Get current music status

  ### System Commands
  - `system:status` - Get overall system status
  - `system:services` - Get detailed service information

  ## Events Received

  All overlays automatically receive relevant real-time events based on their topic.

  ## Usage Example

      // Connect to WebSocket
      const socket = new Phoenix.Socket("/socket")
      socket.connect()

      // Join OBS overlay channel
      const channel = socket.channel("overlay:obs")
      channel.join()

      // Get current OBS status
      channel.push("obs:status", {})
        .receive("ok", (response) => console.log("OBS Status:", response))
        .receive("error", (error) => console.log("Error:", error))

      // Get checkpoints for a challenge (requires challenge_id)
      channel.push("ironmon:checkpoints", {challenge_id: 1})
        .receive("ok", (response) => console.log("Checkpoints:", response))
        .receive("error", (error) => console.log("Error:", error))

      // Listen for OBS events
      channel.on("obs_event", (event) => {
        console.log("OBS Event:", event)
      })
  """

  use ServerWeb, :channel

  require Logger

  alias Server.CorrelationId
  alias ServerWeb.Helpers.SystemHelpers

  # Service module configuration helpers
  defp obs_service, do: Application.get_env(:server, :services, [])[:obs] || Server.Services.OBS
  defp twitch_service, do: Application.get_env(:server, :services, [])[:twitch] || Server.Services.Twitch
  defp ironmon_service, do: Application.get_env(:server, :services, [])[:ironmon_tcp] || Server.Services.IronmonTCP
  defp rainwave_service, do: Application.get_env(:server, :services, [])[:rainwave] || Server.Services.Rainwave

  # Helper function for common service command execution pattern
  defp execute_service_command(service_module, function, args, socket) do
    case apply(service_module, function, args) do
      {:ok, result} ->
        {:reply, {:ok, result}, socket}

      {:error, reason} ->
        {:reply, {:error, %{message: format_error(reason)}}, socket}
    end
  end

  # Channel metadata for self-documentation
  # These are accessed by ChannelRegistry for introspection
  @topic_pattern "overlay:*"
  @channel_examples [
    %{
      command: "obs:status",
      payload: %{},
      description: "Get current OBS connection and streaming status"
    },
    %{
      command: "twitch:status",
      payload: %{},
      description: "Get Twitch EventSub connection health"
    },
    %{
      command: "ironmon:checkpoints",
      payload: %{challenge_id: 1},
      description: "Get checkpoints for challenge ID 1"
    },
    %{
      command: "ironmon:checkpoint_stats",
      payload: %{checkpoint_id: 42},
      description: "Get statistics for checkpoint ID 42"
    },
    %{
      command: "ironmon:recent_results",
      payload: %{limit: 10},
      description: "Get the 10 most recent IronMON run results"
    },
    %{
      command: "ironmon:active_challenge",
      payload: %{seed_id: 123},
      description: "Get active challenge for seed ID 123"
    }
  ]

  # Accessor functions for module attributes (prevents compiler warnings)
  @doc false
  def __topic_pattern__, do: @topic_pattern
  @doc false
  def __channel_examples__, do: @channel_examples

  @impl true
  def join("overlay:" <> overlay_type, _payload, socket) do
    # Generate correlation ID for this overlay connection
    correlation_id = CorrelationId.from_context(assigns: socket.assigns)
    CorrelationId.put_logger_metadata(correlation_id)

    Logger.info("Overlay channel joined",
      overlay_type: overlay_type,
      correlation_id: correlation_id
    )

    socket =
      socket
      |> assign(:overlay_type, overlay_type)
      |> assign(:correlation_id, correlation_id)

    # Subscribe to relevant events based on overlay type
    subscribe_to_events(overlay_type)

    # Send initial state for the overlay
    send(self(), {:send_initial_state, overlay_type})

    {:ok, socket}
  end

  # OBS Commands - Full HTTP endpoint parity

  @impl true
  def handle_in("obs:status", _payload, socket) do
    with_correlation_context(socket, fn ->
      execute_service_command(obs_service(), :get_status, [], socket)
    end)
  end

  @impl true
  def handle_in("obs:scenes", _payload, socket) do
    with_correlation_context(socket, fn ->
      execute_service_command(obs_service(), :get_scene_list, [], socket)
    end)
  end

  @impl true
  def handle_in("obs:stream_status", _payload, socket) do
    with_correlation_context(socket, fn ->
      execute_service_command(obs_service(), :get_stream_status, [], socket)
    end)
  end

  @impl true
  def handle_in("obs:record_status", _payload, socket) do
    with_correlation_context(socket, fn ->
      execute_service_command(obs_service(), :get_record_status, [], socket)
    end)
  end

  @impl true
  def handle_in("obs:stats", _payload, socket) do
    with_correlation_context(socket, fn ->
      execute_service_command(obs_service(), :get_stats, [], socket)
    end)
  end

  @impl true
  def handle_in("obs:version", _payload, socket) do
    with_correlation_context(socket, fn ->
      execute_service_command(obs_service(), :get_version, [], socket)
    end)
  end

  @impl true
  def handle_in("obs:virtual_cam", _payload, socket) do
    with_correlation_context(socket, fn ->
      execute_service_command(obs_service(), :get_virtual_cam_status, [], socket)
    end)
  end

  @impl true
  def handle_in("obs:outputs", _payload, socket) do
    with_correlation_context(socket, fn ->
      execute_service_command(obs_service(), :get_output_list, [], socket)
    end)
  end

  # Twitch Commands

  @impl true
  def handle_in("twitch:status", _payload, socket) do
    with_correlation_context(socket, fn ->
      execute_service_command(twitch_service(), :get_status, [], socket)
    end)
  end

  # IronMON Commands

  @impl true
  def handle_in("ironmon:status", _payload, socket) do
    with_correlation_context(socket, fn ->
      execute_service_command(ironmon_service(), :get_status, [], socket)
    end)
  end

  @impl true
  def handle_in("ironmon:challenges", _payload, socket) do
    with_correlation_context(socket, fn ->
      execute_service_command(ironmon_service(), :list_challenges, [], socket)
    end)
  end

  @impl true
  def handle_in("ironmon:checkpoints", payload, socket) do
    with_correlation_context(socket, fn ->
      with :ok <- validate_params(payload, ["challenge_id"]),
           {:ok, challenge_id} <- validate_integer_param(payload, "challenge_id") do
        case ironmon_service().list_checkpoints(challenge_id) do
          {:ok, checkpoints} ->
            {:reply, {:ok, checkpoints}, socket}

          {:error, reason} ->
            {:reply, {:error, %{message: format_error(reason)}}, socket}
        end
      else
        {:error, message} ->
          {:reply, {:error, %{message: message}}, socket}
      end
    end)
  end

  @impl true
  def handle_in("ironmon:checkpoint_stats", payload, socket) do
    with_correlation_context(socket, fn ->
      with :ok <- validate_params(payload, ["checkpoint_id"]),
           {:ok, checkpoint_id} <- validate_integer_param(payload, "checkpoint_id") do
        case ironmon_service().get_checkpoint_stats(checkpoint_id) do
          {:ok, stats} ->
            {:reply, {:ok, stats}, socket}

          {:error, reason} ->
            {:reply, {:error, %{message: format_error(reason)}}, socket}
        end
      else
        {:error, message} ->
          {:reply, {:error, %{message: message}}, socket}
      end
    end)
  end

  @impl true
  def handle_in("ironmon:recent_results", payload, socket) do
    with_correlation_context(socket, fn ->
      case validate_limit_param(payload) do
        {:ok, limit} ->
          case ironmon_service().get_recent_results(limit) do
            {:ok, results} ->
              {:reply, {:ok, results}, socket}

            {:error, reason} ->
              {:reply, {:error, %{message: format_error(reason)}}, socket}
          end

        {:error, message} ->
          {:reply, {:error, %{message: message}}, socket}
      end
    end)
  end

  @impl true
  def handle_in("ironmon:active_challenge", payload, socket) do
    with_correlation_context(socket, fn ->
      with :ok <- validate_params(payload, ["seed_id"]),
           {:ok, seed_id} <- validate_integer_param(payload, "seed_id") do
        case ironmon_service().get_active_challenge(seed_id) do
          {:ok, challenge} ->
            {:reply, {:ok, challenge}, socket}

          {:error, reason} ->
            {:reply, {:error, %{message: format_error(reason)}}, socket}
        end
      else
        {:error, message} ->
          {:reply, {:error, %{message: message}}, socket}
      end
    end)
  end

  # Music/Rainwave Commands

  @impl true
  def handle_in("rainwave:status", _payload, socket) do
    with_correlation_context(socket, fn ->
      execute_service_command(rainwave_service(), :get_status, [], socket)
    end)
  end

  # System Commands

  @impl true
  def handle_in("system:status", _payload, socket) do
    with_correlation_context(socket, fn ->
      system_status = SystemHelpers.get_system_status()

      services = %{
        obs: get_service_status(:obs),
        twitch: get_service_status(:twitch),
        ironmon_tcp: get_service_status(:ironmon_tcp),
        database: get_service_status(:database)
      }

      healthy_services = services |> Enum.count(fn {_name, status} -> status.connected end)
      total_services = map_size(services)

      status_data = %{
        status: if(healthy_services == total_services, do: "healthy", else: "degraded"),
        timestamp: System.system_time(:second),
        uptime: system_status.uptime,
        memory: system_status.memory,
        services: services,
        summary: %{
          healthy_services: healthy_services,
          total_services: total_services,
          health_percentage: round(healthy_services / total_services * 100)
        }
      }

      {:reply, {:ok, status_data}, socket}
    end)
  end

  @impl true
  def handle_in("system:services", _payload, socket) do
    with_correlation_context(socket, fn ->
      services = %{
        obs: get_detailed_service_info(:obs),
        twitch: get_detailed_service_info(:twitch),
        ironmon_tcp: get_detailed_service_info(:ironmon_tcp),
        database: get_detailed_service_info(:database)
      }

      {:reply, {:ok, services}, socket}
    end)
  end

  # Ping/Pong for connection health
  @impl true
  def handle_in("ping", payload, socket) do
    response =
      Map.merge(payload, %{
        pong: true,
        timestamp: System.system_time(:second),
        overlay_type: socket.assigns.overlay_type
      })

    {:reply, {:ok, response}, socket}
  end

  # Catch-all for unhandled messages
  @impl true
  def handle_in(event, payload, socket) do
    Logger.warning("Unhandled overlay channel message",
      event: event,
      payload: payload,
      overlay_type: socket.assigns.overlay_type,
      correlation_id: socket.assigns.correlation_id
    )

    {:reply, {:error, %{message: "Unknown command: #{event}"}}, socket}
  end

  # Event Handlers - Receive and forward events to overlays

  @impl true
  def handle_info({:send_initial_state, overlay_type}, socket) do
    # Send initial state based on overlay type
    case overlay_type do
      "obs" ->
        case obs_service().get_status() do
          {:ok, status} ->
            push(socket, "initial_state", %{type: "obs", data: status})

          _ ->
            push(socket, "initial_state", %{type: "obs", data: %{connected: false}})
        end

      "twitch" ->
        case twitch_service().get_status() do
          {:ok, status} ->
            push(socket, "initial_state", %{type: "twitch", data: status})

          _ ->
            push(socket, "initial_state", %{type: "twitch", data: %{connected: false}})
        end

      "system" ->
        # Send system status as initial state
        push(socket, "initial_state", %{
          type: "system",
          data: %{connected: true, timestamp: System.system_time(:second)}
        })

      _ ->
        push(socket, "initial_state", %{type: overlay_type, data: %{connected: true}})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:obs_event, event}, socket) do
    push(socket, "obs_event", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:twitch_event, event}, socket) do
    push(socket, "twitch_event", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:ironmon_event, event}, socket) do
    push(socket, "ironmon_event", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:rainwave_event, event}, socket) do
    push(socket, "music_event", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:system_event, event}, socket) do
    push(socket, "system_event", event)
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

  # Private helper functions

  # Parameter validation
  defp validate_params(params, required_keys) when is_non_struct_map(params) and is_list(required_keys) do
    missing_keys =
      required_keys
      |> Enum.reject(&Map.has_key?(params, &1))

    case missing_keys do
      [] -> :ok
      _ -> {:error, "Missing required parameters: #{Enum.join(missing_keys, ", ")}"}
    end
  end

  defp validate_integer_param(params, key) when is_non_struct_map(params) do
    case Map.get(params, key) do
      value when is_integer(value) and value > 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int_value, ""} when int_value > 0 -> {:ok, int_value}
          _ -> {:error, "Parameter '#{key}' must be a positive integer"}
        end

      _ ->
        {:error, "Parameter '#{key}' must be a positive integer"}
    end
  end

  defp validate_limit_param(params) do
    limit = Map.get(params, "limit", 10)

    case limit do
      value when is_integer(value) and value >= 1 and value <= 100 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int_value, ""} when int_value >= 1 and int_value <= 100 -> {:ok, int_value}
          _ -> {:error, "Parameter 'limit' must be an integer between 1 and 100"}
        end

      _ ->
        {:error, "Parameter 'limit' must be an integer between 1 and 100"}
    end
  end

  defp subscribe_to_events(overlay_type) do
    case overlay_type do
      "obs" ->
        Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")

      "twitch" ->
        Phoenix.PubSub.subscribe(Server.PubSub, "twitch:events")

      "ironmon" ->
        Phoenix.PubSub.subscribe(Server.PubSub, "ironmon:events")

      "music" ->
        Phoenix.PubSub.subscribe(Server.PubSub, "rainwave:events")

      "system" ->
        Phoenix.PubSub.subscribe(Server.PubSub, "system:health")
        Phoenix.PubSub.subscribe(Server.PubSub, "system:performance")
        Phoenix.PubSub.subscribe(Server.PubSub, "system:events")

      _ ->
        Logger.warning("Unknown overlay type for event subscription", overlay_type: overlay_type)
    end
  end

  defp with_correlation_context(socket, fun) do
    correlation_id = socket.assigns.correlation_id
    CorrelationId.with_context(correlation_id, fun)
  end

  defp format_error(%Server.ServiceError{message: message}), do: message
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  # Service status helpers (copied from ControlController)

  defp get_service_status(:obs) do
    case obs_service().get_status() do
      {:ok, status} -> %{connected: true, status: status}
      {:error, reason} -> %{connected: false, error: format_error(reason)}
    end
  rescue
    e in ArgumentError -> %{connected: false, error: "Invalid service configuration: #{e.message}"}
    e -> %{connected: false, error: "Service call failed: #{inspect(e)}"}
  end

  defp get_service_status(:twitch) do
    case twitch_service().get_status() do
      {:ok, status} -> %{connected: true, status: status}
      {:error, reason} -> %{connected: false, error: format_error(reason)}
    end
  rescue
    e in ArgumentError -> %{connected: false, error: "Invalid service configuration: #{e.message}"}
    e -> %{connected: false, error: "Service call failed: #{inspect(e)}"}
  end

  defp get_service_status(:ironmon_tcp) do
    case GenServer.whereis(Server.Services.IronmonTCP) do
      pid when is_pid(pid) ->
        %{connected: true, pid: inspect(pid)}

      nil ->
        %{connected: false, error: "Service not running"}
    end
  end

  defp get_service_status(:database) do
    case safe_database_query("SELECT 1", []) do
      {:ok, _} -> %{connected: true, status: "healthy"}
      {:error, reason} -> %{connected: false, error: reason}
    end
  end

  defp get_detailed_service_info(:obs) do
    base_status = get_service_status(:obs)

    additional_info =
      if base_status.connected do
        case obs_service().get_scene_list() do
          {:ok, scenes_data} ->
            %{
              service_type: "obs_websocket",
              scene_count: length(Map.get(scenes_data, "scenes", [])),
              current_scene: Map.get(scenes_data, "currentProgramSceneName")
            }

          {:error, _} ->
            %{service_type: "obs_websocket"}
        end
      else
        %{}
      end

    Map.merge(base_status, additional_info)
  end

  defp get_detailed_service_info(:twitch) do
    base_status = get_service_status(:twitch)

    additional_info =
      if base_status.connected do
        %{
          subscriptions:
            Server.SubscriptionMonitor.get_health_report() |> Map.take([:total_subscriptions, :enabled_subscriptions])
        }
      else
        %{}
      end

    Map.merge(base_status, additional_info)
  end

  defp get_detailed_service_info(:ironmon_tcp) do
    base_status = get_service_status(:ironmon_tcp)

    additional_info =
      if base_status.connected do
        case ironmon_service().get_status() do
          {:ok, status} ->
            %{
              service_type: "tcp_server",
              port: Map.get(status, :port, 8080),
              connection_count: Map.get(status, :connection_count, 0)
            }

          _ ->
            %{service_type: "tcp_server"}
        end
      else
        %{}
      end

    Map.merge(base_status, additional_info)
  end

  defp get_detailed_service_info(:database) do
    base_status = get_service_status(:database)

    additional_info =
      if base_status.connected do
        # Use a safe database query with proper timeout and error handling
        case safe_database_query("SELECT COUNT(*) FROM seeds", []) do
          {:ok, seed_count} -> %{seed_count: seed_count}
          {:error, reason} -> %{seed_count: "unavailable", error: reason}
        end
      else
        %{}
      end

    Map.merge(base_status, additional_info)
  end

  # Safe database query wrapper that handles connection pool issues
  defp safe_database_query(query, params) do
    try do
      # Use a shorter timeout to avoid connection pool conflicts
      case Server.Repo.query(query, params, timeout: 5000) do
        {:ok, %{rows: [[count]]}} when is_integer(count) -> {:ok, count}
        # For health checks like "SELECT 1"
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, inspect(reason)}
      end
    rescue
      e in Postgrex.Error -> {:error, "database_error: #{e.message}"}
      e in DBConnection.ConnectionError -> {:error, "connection_error: #{e.message}"}
      e in DBConnection.OwnershipError -> {:error, "ownership_error: #{e.message}"}
      _other -> {:error, "unknown_error"}
    catch
      :exit, reason -> {:error, "process_exit: #{inspect(reason)}"}
    end
  end
end

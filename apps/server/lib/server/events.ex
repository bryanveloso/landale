defmodule Server.Events do
  @moduledoc """
  ⚠️  DEPRECATED: This module is deprecated as of August 2025.

  ## Migration Path

  Use `Server.Services.Twitch.EventHandler` for all event publishing instead:

  ```elixir
  # OLD (deprecated)
  Server.Events.publish_twitch_event("channel.follow", event_data)

  # NEW (canonical)
  normalized = Server.Services.Twitch.EventHandler.normalize_event("channel.follow", event_data)
  Server.Services.Twitch.EventHandler.publish_event("channel.follow", normalized)
  ```

  ## Why Deprecated

  This module creates nested event structures with `:data` fields, which violates
  the Unified Event Strategy that requires flat canonical events throughout the application.

  The EventHandler provides the canonical flat format defined in UNIFIED_EVENT_STRATEGY.md.

  ## Legacy Support

  This module remains for backward compatibility but should not be used for new code.
  All functions still work but create events in the deprecated nested format.
  """

  require Logger
  alias Server.CorrelationId

  @pubsub Server.PubSub

  # Event topic constants to maintain consistency
  @obs_events "obs:events"
  @twitch_events "twitch:events"
  @ironmon_events "ironmon:events"
  @rainwave_events "rainwave:events"
  @system_events "system:events"
  @health_events "system:health"
  @performance_events "system:performance"

  # OBS Event Publishing

  @doc """
  Publishes an OBS-related event to all subscribers.

  ## Parameters
  - `event_type` - Type of OBS event (e.g. "connection_established", "stream_started")
  - `data` - Event data payload
  - `opts` - Options (kept for compatibility but batching is removed)
  """
  @spec publish_obs_event(binary(), map(), keyword()) :: :ok
  def publish_obs_event(event_type, data, _opts \\ []) do
    event = %{
      type: event_type,
      data: data,
      timestamp: DateTime.utc_now(),
      correlation_id: get_correlation_id()
    }

    # Direct publish - no batching
    Phoenix.PubSub.broadcast(@pubsub, @obs_events, {:obs_event, event})
  end

  # Twitch Event Publishing

  @doc """
  ⚠️  DEPRECATED: Use Server.Services.Twitch.EventHandler instead.

  Publishes a Twitch EventSub event to all subscribers.

  ## Parameters
  - `event_type` - Type of Twitch event (e.g. "channel.update", "stream.online")
  - `data` - Event data payload from EventSub
  - `opts` - Options (kept for compatibility but batching is removed)
  """
  @deprecated "Use Server.Services.Twitch.EventHandler.publish_event/2 instead"
  @spec publish_twitch_event(binary(), map(), keyword()) :: :ok
  def publish_twitch_event(event_type, data, _opts \\ []) do
    Logger.warning(
      "DEPRECATED: Server.Events.publish_twitch_event/3 is deprecated. Use Server.Services.Twitch.EventHandler.publish_event/2 instead.",
      event_type: event_type,
      caller: caller_info()
    )

    event = %{
      type: event_type,
      data: data,
      timestamp: DateTime.utc_now(),
      correlation_id: get_correlation_id()
    }

    # Direct publish - no batching
    Phoenix.PubSub.broadcast(@pubsub, @twitch_events, {:twitch_event, event})
  end

  # IronMON Event Publishing

  @doc """
  Publishes an IronMON-related event to all subscribers.

  ## Parameters
  - `event_type` - Type of IronMON event (e.g. "run_started", "checkpoint_reached")
  - `data` - Event data payload
  - `opts` - Options (kept for compatibility but batching is removed)
  """
  @spec publish_ironmon_event(binary(), map(), keyword()) :: :ok
  def publish_ironmon_event(event_type, data, _opts \\ []) do
    event = %{
      type: event_type,
      data: data,
      timestamp: DateTime.utc_now(),
      correlation_id: get_correlation_id()
    }

    # Direct publish - no batching
    Phoenix.PubSub.broadcast(@pubsub, @ironmon_events, {:ironmon_event, event})
  end

  # Rainwave Event Publishing

  @doc """
  General event emitter function matching the original TypeScript API.

  ## Parameters
  - `event_name` - Event identifier (e.g. "rainwave:update", "obs:status")
  - `data` - Event data payload
  - `correlation_id` - Optional correlation ID for tracking
  """
  @spec emit(binary(), map(), binary() | nil) :: :ok
  def emit(event_name, data, correlation_id \\ nil)

  def emit("rainwave:update", data, correlation_id) do
    opts = if correlation_id, do: [correlation_id: correlation_id], else: []
    publish_rainwave_event("update", data, opts)
  end

  def emit(event_name, data, correlation_id) do
    Logger.warning("Unhandled event emission",
      event_name: event_name,
      data: inspect(data, limit: :infinity),
      correlation_id: correlation_id
    )
  end

  @doc """
  Publishes a Rainwave music event to all subscribers.

  ## Parameters
  - `event_type` - Type of Rainwave event (e.g. "song_change", "station_change")
  - `data` - Event data payload
  - `opts` - Options including :correlation_id (kept for compatibility)
  """
  @spec publish_rainwave_event(binary(), map(), keyword()) :: :ok
  def publish_rainwave_event(event_type, data, opts \\ []) do
    event = %{
      type: event_type,
      data: data,
      timestamp: DateTime.utc_now(),
      correlation_id: Keyword.get(opts, :correlation_id) || get_correlation_id()
    }

    # Direct publish - no batching
    Phoenix.PubSub.broadcast(@pubsub, @rainwave_events, {:rainwave_event, event})
  end

  # System Event Publishing

  @doc """
  Publishes a system-level event to all subscribers.

  ## Parameters
  - `event_type` - Type of system event (e.g. "startup", "shutdown", "error")
  - `data` - Event data payload
  - `opts` - Options (kept for compatibility but batching is removed)
  """
  @spec publish_system_event(binary(), map(), keyword()) :: :ok
  def publish_system_event(event_type, data, _opts \\ []) do
    event = %{
      type: event_type,
      data: data,
      timestamp: DateTime.utc_now(),
      correlation_id: get_correlation_id()
    }

    # Direct publish - no batching
    Phoenix.PubSub.broadcast(@pubsub, @system_events, {:system_event, event})
  end

  # Health Monitoring Events

  @doc """
  Publishes a health status update for a service.

  ## Parameters
  - `service` - Service name (e.g. "obs", "twitch", "database")
  - `status` - Health status (e.g. "healthy", "unhealthy", "degraded")
  - `details` - Additional health details (optional)
  """
  @spec publish_health_update(binary(), binary(), map()) :: :ok
  def publish_health_update(service, status, details \\ %{}) do
    data = %{
      service: service,
      status: status,
      details: details,
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(@pubsub, @health_events, {:health_update, data})
  end

  # Performance Monitoring Events

  @doc """
  Publishes a performance metric update.

  ## Parameters
  - `metric` - Metric name (e.g. "cpu_usage", "memory_usage", "latency")
  - `value` - Metric value
  - `metadata` - Additional metric metadata (optional)
  """
  @spec publish_performance_update(binary(), number(), map()) :: :ok
  def publish_performance_update(metric, value, metadata \\ %{}) do
    data = %{
      metric: metric,
      value: value,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(@pubsub, @performance_events, {:performance_update, data})
  end

  # Subscription helpers

  @doc "Subscribes the current process to OBS events."
  @spec subscribe_to_obs_events() :: :ok
  def subscribe_to_obs_events do
    Phoenix.PubSub.subscribe(@pubsub, @obs_events)
  end

  @doc "Subscribes the current process to Twitch events."
  @spec subscribe_to_twitch_events() :: :ok
  def subscribe_to_twitch_events do
    Phoenix.PubSub.subscribe(@pubsub, @twitch_events)
  end

  @doc "Subscribes the current process to IronMON events."
  @spec subscribe_to_ironmon_events() :: :ok
  def subscribe_to_ironmon_events do
    Phoenix.PubSub.subscribe(@pubsub, @ironmon_events)
  end

  @doc "Subscribes the current process to Rainwave events."
  @spec subscribe_to_rainwave_events() :: :ok
  def subscribe_to_rainwave_events do
    Phoenix.PubSub.subscribe(@pubsub, @rainwave_events)
  end

  @doc "Subscribes the current process to system events."
  @spec subscribe_to_system_events() :: :ok
  def subscribe_to_system_events do
    Phoenix.PubSub.subscribe(@pubsub, @system_events)
  end

  @doc "Subscribes the current process to health monitoring events."
  @spec subscribe_to_health_events() :: :ok
  def subscribe_to_health_events do
    Phoenix.PubSub.subscribe(@pubsub, @health_events)
  end

  @doc "Subscribes the current process to performance monitoring events."
  @spec subscribe_to_performance_events() :: :ok
  def subscribe_to_performance_events do
    Phoenix.PubSub.subscribe(@pubsub, @performance_events)
  end

  # Unsubscribe helpers
  def unsubscribe_from_obs_events do
    Phoenix.PubSub.unsubscribe(@pubsub, @obs_events)
  end

  def unsubscribe_from_twitch_events do
    Phoenix.PubSub.unsubscribe(@pubsub, @twitch_events)
  end

  def unsubscribe_from_ironmon_events do
    Phoenix.PubSub.unsubscribe(@pubsub, @ironmon_events)
  end

  def unsubscribe_from_rainwave_events do
    Phoenix.PubSub.unsubscribe(@pubsub, @rainwave_events)
  end

  def unsubscribe_from_system_events do
    Phoenix.PubSub.unsubscribe(@pubsub, @system_events)
  end

  def unsubscribe_from_health_events do
    Phoenix.PubSub.unsubscribe(@pubsub, @health_events)
  end

  def unsubscribe_from_performance_events do
    Phoenix.PubSub.unsubscribe(@pubsub, @performance_events)
  end

  # Private helper functions

  defp get_correlation_id do
    # Use pool for high-frequency event generation, fallback to direct generation
    case Process.whereis(Server.CorrelationIdPool) do
      nil -> CorrelationId.generate()
      _pid -> Server.CorrelationIdPool.get()
    end
  end

  defp caller_info do
    case Process.info(self(), :current_stacktrace) do
      {:current_stacktrace, [_current | [caller | _rest]]} ->
        case caller do
          {module, function, arity, _} -> "#{module}.#{function}/#{arity}"
          _ -> "unknown"
        end

      _ ->
        "unknown"
    end
  end
end

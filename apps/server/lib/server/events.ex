defmodule Server.Events do
  @moduledoc """
  Central event system using Phoenix PubSub to replace the TypeScript Emittery system.

  This module provides a clean interface for publishing and subscribing to events
  across the application, maintaining the same event-driven architecture as the
  original TypeScript implementation.
  """

  require Logger

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
  """
  @spec publish_obs_event(binary(), map()) :: :ok
  def publish_obs_event(event_type, data) do
    event = %{
      type: event_type,
      data: data,
      timestamp: System.system_time(:second),
      correlation_id: UUID.uuid4()
    }

    Logger.debug("Publishing OBS event", event: event)
    Phoenix.PubSub.broadcast(@pubsub, @obs_events, {:obs_event, event})

    # Emit telemetry for published event
    Server.Telemetry.event_published(event_type, "obs:events")
  end

  # Twitch Event Publishing

  @doc """
  Publishes a Twitch EventSub event to all subscribers.

  ## Parameters
  - `event_type` - Type of Twitch event (e.g. "channel.update", "stream.online")
  - `data` - Event data payload from EventSub
  """
  @spec publish_twitch_event(binary(), map()) :: :ok
  def publish_twitch_event(event_type, data) do
    event = %{
      type: event_type,
      data: data,
      timestamp: System.system_time(:second),
      correlation_id: UUID.uuid4()
    }

    Logger.debug("Publishing Twitch event", event: event)
    Phoenix.PubSub.broadcast(@pubsub, @twitch_events, {:twitch_event, event})

    # Emit telemetry for published event
    Server.Telemetry.event_published(event_type, "twitch:events")
  end

  # IronMON Event Publishing

  @doc """
  Publishes an IronMON-related event to all subscribers.

  ## Parameters
  - `event_type` - Type of IronMON event (e.g. "run_started", "checkpoint_reached")
  - `data` - Event data payload
  """
  @spec publish_ironmon_event(binary(), map()) :: :ok
  def publish_ironmon_event(event_type, data) do
    event = %{
      type: event_type,
      data: data,
      timestamp: System.system_time(:second),
      correlation_id: UUID.uuid4()
    }

    Logger.debug("Publishing IronMON event", event: event)
    Phoenix.PubSub.broadcast(@pubsub, @ironmon_events, {:ironmon_event, event})

    # Emit telemetry for published event
    Server.Telemetry.event_published(event_type, "ironmon:events")
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
    publish_rainwave_event("update", data, correlation_id)
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
  - `correlation_id` - Optional correlation ID for tracking
  """
  @spec publish_rainwave_event(binary(), map(), binary() | nil) :: :ok
  def publish_rainwave_event(event_type, data, correlation_id \\ nil) do
    event = %{
      type: event_type,
      data: data,
      timestamp: System.system_time(:second),
      correlation_id: correlation_id || UUID.uuid4()
    }

    Logger.debug("Publishing Rainwave event", event: event)
    Phoenix.PubSub.broadcast(@pubsub, @rainwave_events, {:rainwave_event, event})

    # Emit telemetry for published event
    Server.Telemetry.event_published(event_type, "rainwave:events")
  end

  # System Event Publishing

  @doc """
  Publishes a system-level event to all subscribers.

  ## Parameters
  - `event_type` - Type of system event (e.g. "startup", "shutdown", "error")
  - `data` - Event data payload
  """
  @spec publish_system_event(binary(), map()) :: :ok
  def publish_system_event(event_type, data) do
    event = %{
      type: event_type,
      data: data,
      timestamp: System.system_time(:second),
      correlation_id: UUID.uuid4()
    }

    Logger.debug("Publishing system event", event: event)
    Phoenix.PubSub.broadcast(@pubsub, @system_events, {:system_event, event})

    # Emit telemetry for published event
    Server.Telemetry.event_published(event_type, "system:events")
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
      timestamp: System.system_time(:second)
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
      timestamp: System.system_time(:second)
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
end

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
  @system_events "system:events"
  @health_events "system:health"
  @performance_events "system:performance"

  # OBS Event Publishing
  def publish_obs_event(event_type, data) do
    event = %{
      type: event_type,
      data: data,
      timestamp: System.system_time(:second),
      correlation_id: UUID.uuid4()
    }

    Logger.debug("Publishing OBS event", event: event)
    Phoenix.PubSub.broadcast(@pubsub, @obs_events, {:obs_event, event})
  end

  # Twitch Event Publishing
  def publish_twitch_event(event_type, data) do
    event = %{
      type: event_type,
      data: data,
      timestamp: System.system_time(:second),
      correlation_id: UUID.uuid4()
    }

    Logger.debug("Publishing Twitch event", event: event)
    Phoenix.PubSub.broadcast(@pubsub, @twitch_events, {:twitch_event, event})
  end

  # IronMON Event Publishing
  def publish_ironmon_event(event_type, data) do
    event = %{
      type: event_type,
      data: data,
      timestamp: System.system_time(:second),
      correlation_id: UUID.uuid4()
    }

    Logger.debug("Publishing IronMON event", event: event)
    Phoenix.PubSub.broadcast(@pubsub, @ironmon_events, {:ironmon_event, event})
  end

  # System Event Publishing
  def publish_system_event(event_type, data) do
    event = %{
      type: event_type,
      data: data,
      timestamp: System.system_time(:second),
      correlation_id: UUID.uuid4()
    }

    Logger.debug("Publishing system event", event: event)
    Phoenix.PubSub.broadcast(@pubsub, @system_events, {:system_event, event})
  end

  # Health Monitoring Events
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
  def subscribe_to_obs_events do
    Phoenix.PubSub.subscribe(@pubsub, @obs_events)
  end

  def subscribe_to_twitch_events do
    Phoenix.PubSub.subscribe(@pubsub, @twitch_events)
  end

  def subscribe_to_ironmon_events do
    Phoenix.PubSub.subscribe(@pubsub, @ironmon_events)
  end

  def subscribe_to_system_events do
    Phoenix.PubSub.subscribe(@pubsub, @system_events)
  end

  def subscribe_to_health_events do
    Phoenix.PubSub.subscribe(@pubsub, @health_events)
  end

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
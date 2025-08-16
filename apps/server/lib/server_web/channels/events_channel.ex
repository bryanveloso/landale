defmodule ServerWeb.EventsChannel do
  @moduledoc """
  Phoenix channel for real-time event streaming with topic-specific filtering.

  ## Supported Topics

  - `events:all` - Receives all events from all sources
  - `events:twitch` - Receives all Twitch events
  - `events:chat` - Receives only chat-related events (channel.chat.*)
  - `events:interactions` - Receives only interaction events (follows, subs, cheers)
  - `events:goals` - Receives only goal-related events (channel.goal.*)
  - `events:dashboard` - Receives connection/status events relevant for dashboards
  - `events:obs` - Receives all OBS events
  - `events:system` - Receives all system events
  - `events:rainwave` or `events:music` - Receives all Rainwave events
  - `events:ironmon` - Receives all IronMON events

  ## Event Filtering

  The channel implements intelligent filtering to ensure clients only receive
  relevant events based on their subscription topic:

  - Chat topics only get chat messages, clears, and deletions
  - Interaction topics only get follows, subscriptions, and cheers
  - Goal topics only get goal begin/progress/end events
  - Dashboard topics get connection status and service health events
  """

  use ServerWeb.ChannelBase

  @impl true
  def join("events:" <> topic, _payload, socket) do
    socket =
      socket
      |> setup_correlation_id()
      |> assign(:event_topic, topic)

    # Subscribe to unified events stream for all topics
    # All events now flow through the unified "events" topic
    Phoenix.PubSub.subscribe(Server.PubSub, "events")

    # Emit telemetry for channel join
    emit_joined_telemetry("events:#{topic}", socket)

    {:ok, socket}
  end

  # Handle ping for connection health
  @impl true
  def handle_in("ping", payload, socket) do
    handle_ping(payload, socket)
  end

  # Catch-all - just log unhandled messages
  @impl true
  def handle_in(event, payload, socket) do
    log_unhandled_message(event, payload, socket)
    {:noreply, socket}
  end

  # Unified event handler - handles all events from unified topic
  @impl true
  def handle_info({:event, event}, socket) do
    topic = socket.assigns.event_topic
    event_source = Map.get(event, :source)
    event_type = Map.get(event, :type)

    if should_forward_event?(topic, event_source, event_type) do
      forward_event(socket, event_source, event)
    end

    {:noreply, socket}
  end

  # Catch-all handler to prevent crashes from unexpected messages
  @impl true
  def handle_info(unhandled_msg, socket) do
    Logger.warning("Unhandled message in #{__MODULE__}",
      message: inspect(unhandled_msg),
      event_topic: socket.assigns[:event_topic]
    )

    {:noreply, socket}
  end

  # Forward event to appropriate channel based on source
  defp forward_event(socket, :twitch, event) do
    event_name = get_twitch_event_name(event.type)
    push(socket, event_name, event)
  end

  defp forward_event(socket, :obs, event) do
    push(socket, "obs_event", event)
  end

  defp forward_event(socket, :ironmon, event) do
    push(socket, "ironmon_event", event)
  end

  defp forward_event(socket, :system, event) do
    push(socket, "system_event", event)
  end

  defp forward_event(socket, :rainwave, event) do
    push(socket, "rainwave_event", event)
  end

  defp forward_event(socket, _, event) do
    push(socket, "unknown_event", event)
  end

  # Map Twitch event types to channel event names
  defp get_twitch_event_name(event_type) do
    case event_type do
      "channel.chat.message" -> "chat_message"
      "channel.chat.clear" -> "chat_clear"
      "channel.chat.message_delete" -> "message_delete"
      "channel.follow" -> "follower"
      "channel.subscribe" -> "subscription"
      "channel.subscription.gift" -> "gift_subscription"
      "channel.cheer" -> "cheer"
      "channel.update" -> "channel_update"
      _ -> "twitch_event"
    end
  end

  # Enhanced event filtering that considers both topic and event type for specific subscriptions
  defp should_forward_event?(topic, event_source, event_type) do
    case {topic, event_source} do
      {"all", _} -> true
      {"twitch", :twitch} -> true
      {"obs", :obs} -> true
      {"ironmon", :ironmon} -> true
      {"system", :system} -> true
      {"rainwave", :rainwave} -> true
      {"music", :rainwave} -> true
      # Topic-specific filtering for Twitch events (only when event_type is available)
      {"chat", :twitch} when not is_nil(event_type) -> chat_event?(event_type)
      {"goals", :twitch} when not is_nil(event_type) -> goal_event?(event_type)
      {"interactions", :twitch} when not is_nil(event_type) -> interaction_event?(event_type)
      {"dashboard", _} when not is_nil(event_type) -> dashboard_relevant_event?(event_source, event_type)
      _ -> false
    end
  end

  # Helper functions to categorize event types

  defp chat_event?(event_type) do
    String.starts_with?(event_type, "channel.chat.")
  end

  defp goal_event?(event_type) do
    String.starts_with?(event_type, "channel.goal.")
  end

  defp interaction_event?(event_type) do
    event_type in [
      "channel.follow",
      "channel.subscribe",
      "channel.subscription.gift",
      "channel.cheer"
    ]
  end

  defp dashboard_relevant_event?(event_source, event_type) do
    case event_source do
      :twitch ->
        # Dashboard gets stream status and channel updates, but not chat/follows/etc
        event_type in [
          "stream.online",
          "stream.offline",
          "channel.update"
        ]

      :obs ->
        # Dashboard gets all OBS connection and status events
        true

      :system ->
        # Dashboard gets all system events for monitoring
        true

      :rainwave ->
        # Dashboard gets music service status
        true

      :ironmon ->
        # Dashboard gets game status
        true

      _ ->
        false
    end
  end
end

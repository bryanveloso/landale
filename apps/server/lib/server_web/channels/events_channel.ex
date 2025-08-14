defmodule ServerWeb.EventsChannel do
  @moduledoc "Phoenix channel for real-time event streaming."

  use ServerWeb.ChannelBase

  @impl true
  def join("events:" <> topic, _payload, socket) do
    socket =
      socket
      |> setup_correlation_id()
      |> assign(:event_topic, topic)

    # Subscribe to appropriate event streams
    case topic do
      "all" ->
        Phoenix.PubSub.subscribe(Server.PubSub, "events")

      "twitch" ->
        Phoenix.PubSub.subscribe(Server.PubSub, "events")

      "obs" ->
        Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")

      "ironmon" ->
        Phoenix.PubSub.subscribe(Server.PubSub, "ironmon:events")

      "system" ->
        Phoenix.PubSub.subscribe(Server.PubSub, "system:events")

      source when source in ["chat", "dashboard", "goals", "interactions"] ->
        Phoenix.PubSub.subscribe(Server.PubSub, "events")

      _ ->
        Phoenix.PubSub.subscribe(Server.PubSub, "events")
    end

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

  # Event handlers for different event sources
  @impl true
  def handle_info({:twitch_event, event}, socket) do
    # Route to appropriate channel event based on type
    case event.type do
      "channel.chat.message" -> push(socket, "chat_message", event)
      "channel.chat.clear" -> push(socket, "chat_clear", event)
      "channel.chat.message_delete" -> push(socket, "message_delete", event)
      "channel.follow" -> push(socket, "follower", event)
      "channel.subscribe" -> push(socket, "subscription", event)
      "channel.subscription.gift" -> push(socket, "gift_subscription", event)
      "channel.cheer" -> push(socket, "cheer", event)
      "channel.update" -> push(socket, "channel_update", event)
      _ -> push(socket, "twitch_event", event)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:obs_event, event}, socket) do
    push(socket, "obs_event", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:ironmon_event, event}, socket) do
    push(socket, "ironmon_event", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:system_event, event}, socket) do
    push(socket, "system_event", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:rainwave_event, event}, socket) do
    push(socket, "rainwave_event", event)
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
end

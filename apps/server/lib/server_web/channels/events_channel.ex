defmodule ServerWeb.EventsChannel do
  @moduledoc "Phoenix channel for real-time event streaming."

  use ServerWeb.ChannelBase

  alias Server.Events.{Event, Transformer}

  @impl true
  def join("events:" <> topic, _payload, socket) do
    socket =
      socket
      |> setup_correlation_id()
      |> assign(:event_topic, topic)

    # Subscribe to event topics
    case topic do
      "all" ->
        Phoenix.PubSub.subscribe(Server.PubSub, "events:all")

      "twitch" ->
        Phoenix.PubSub.subscribe(Server.PubSub, "events:twitch")

      "obs" ->
        Phoenix.PubSub.subscribe(Server.PubSub, "events:obs")

      "ironmon" ->
        Phoenix.PubSub.subscribe(Server.PubSub, "events:ironmon")

      "system" ->
        Phoenix.PubSub.subscribe(Server.PubSub, "events:system")

      source when source in ["chat", "dashboard", "goals", "interactions"] ->
        # Legacy support - subscribe to all events and filter client-side
        Phoenix.PubSub.subscribe(Server.PubSub, "events:all")

      _ ->
        Phoenix.PubSub.subscribe(Server.PubSub, "events:all")
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

  # Event handler for all events
  @impl true
  def handle_info({:event, %Event{} = event}, socket) do
    ws_event = Transformer.for_websocket(event)

    # Route to appropriate channel event based on type
    case event.type do
      "channel.chat.message" -> push(socket, "chat_message", ws_event)
      "channel.chat.clear" -> push(socket, "chat_clear", ws_event)
      "channel.chat.message_delete" -> push(socket, "message_delete", ws_event)
      "channel.follow" -> push(socket, "follower", ws_event)
      "channel.subscribe" -> push(socket, "subscription", ws_event)
      "channel.subscription.gift" -> push(socket, "gift_subscription", ws_event)
      "channel.cheer" -> push(socket, "cheer", ws_event)
      "channel.update" -> push(socket, "channel_update", ws_event)
      "obs." <> _ -> push(socket, "obs_event", ws_event)
      "ironmon." <> _ -> push(socket, "ironmon_event", ws_event)
      "system." <> _ -> push(socket, "system_event", ws_event)
      "goal." <> goal_type -> push(socket, "goal_#{goal_type}", ws_event)
      _ -> push(socket, "event", ws_event)
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
end

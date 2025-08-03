defmodule ServerWeb.EventsChannel do
  @moduledoc "Phoenix channel for real-time event streaming."

  use ServerWeb.ChannelBase

  @impl true
  def join("events:" <> topic, _payload, socket) do
    socket =
      socket
      |> setup_correlation_id()
      |> assign(:event_topic, topic)

    # Subscribe to the specific topic or all events
    topics_to_subscribe =
      case topic do
        "all" ->
          [
            "dashboard",
            "chat",
            "followers",
            "subscriptions",
            "cheers",
            "obs:events",
            "twitch:events",
            "ironmon:events",
            "rainwave:events",
            "system:events"
          ]

        "chat" ->
          ["chat"]

        "twitch" ->
          ["dashboard", "followers", "subscriptions", "cheers"]

        "interactions" ->
          ["chat", "followers", "subscriptions", "cheers"]

        specific_topic ->
          ["#{specific_topic}:events"]
      end

    subscribe_to_topics(topics_to_subscribe)
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

  @impl true
  def handle_info({:obs_event, event}, socket) do
    push(socket, "event", %{
      type: "obs",
      data: event,
      timestamp: System.system_time(:second)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:twitch_event, event}, socket) do
    push(socket, "event", %{
      type: "twitch",
      data: event,
      timestamp: System.system_time(:second)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:twitch_connected, event}, socket) do
    push(socket, "event", %{
      type: "twitch_connected",
      data: event,
      timestamp: System.system_time(:second)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:twitch_disconnected, event}, socket) do
    push(socket, "event", %{
      type: "twitch_disconnected",
      data: event,
      timestamp: System.system_time(:second)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:twitch_connection_changed, event}, socket) do
    push(socket, "event", %{
      type: "twitch_connection",
      data: event,
      timestamp: System.system_time(:second)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:ironmon_event, event}, socket) do
    push(socket, "event", %{
      type: "ironmon",
      data: event,
      timestamp: System.system_time(:second)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:rainwave_event, event}, socket) do
    push(socket, "event", %{
      type: "rainwave",
      data: event,
      timestamp: System.system_time(:second)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:system_event, event}, socket) do
    push(socket, "event", %{
      type: "system",
      data: event,
      timestamp: System.system_time(:second)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:chat_message, event}, socket) do
    push(socket, "chat_message", %{
      type: "chat_message",
      data: event,
      timestamp: event.timestamp
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:chat_clear, event}, socket) do
    push(socket, "chat_clear", %{
      type: "chat_clear",
      data: event,
      timestamp: event.timestamp
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:message_delete, event}, socket) do
    push(socket, "message_delete", %{
      type: "message_delete",
      data: event,
      timestamp: event.timestamp
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_follower, event}, socket) do
    push(socket, "follower", %{
      type: "follower",
      data: event,
      timestamp: event.timestamp
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_subscription, event}, socket) do
    push(socket, "subscription", %{
      type: "subscription",
      data: event,
      timestamp: event.timestamp
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:gift_subscription, event}, socket) do
    push(socket, "gift_subscription", %{
      type: "gift_subscription",
      data: event,
      timestamp: event.timestamp
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_cheer, event}, socket) do
    push(socket, "cheer", %{
      type: "cheer",
      data: event,
      timestamp: event.timestamp
    })

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

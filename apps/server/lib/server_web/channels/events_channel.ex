defmodule ServerWeb.EventsChannel do
  @moduledoc "Phoenix channel for real-time event streaming."

  use ServerWeb, :channel

  require Logger

  @impl true
  def join("events:" <> topic, _payload, socket) do
    Logger.info("Events channel joined",
      topic: topic,
      correlation_id: socket.assigns.correlation_id
    )

    socket = assign(socket, :topic, topic)

    # Subscribe to the specific topic or all events
    case topic do
      "all" ->
        Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")
        Phoenix.PubSub.subscribe(Server.PubSub, "twitch:events")
        Phoenix.PubSub.subscribe(Server.PubSub, "ironmon:events")
        Phoenix.PubSub.subscribe(Server.PubSub, "rainwave:events")
        Phoenix.PubSub.subscribe(Server.PubSub, "system:events")

      specific_topic ->
        Phoenix.PubSub.subscribe(Server.PubSub, "#{specific_topic}:events")
    end

    {:ok, socket}
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

  # Handle ping for connection health
  @impl true
  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{pong: true, timestamp: System.system_time(:second)}}, socket}
  end

  # Catch-all for unhandled messages
  @impl true
  def handle_in(event, payload, socket) do
    Logger.warning("Unhandled events channel message",
      event: event,
      payload: payload,
      correlation_id: socket.assigns.correlation_id
    )

    {:noreply, socket}
  end
end

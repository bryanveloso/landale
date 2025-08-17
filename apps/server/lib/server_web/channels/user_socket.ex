defmodule ServerWeb.UserSocket do
  @moduledoc "Phoenix socket configuration for WebSocket connections."

  use Phoenix.Socket
  require Logger
  alias Server.CorrelationId

  # Channels
  channel "dashboard:services", ServerWeb.ServicesChannel
  channel "dashboard:*", ServerWeb.DashboardChannel
  channel "events:*", ServerWeb.EventsChannel
  channel "overlay:*", ServerWeb.OverlayChannel
  channel "stream:*", ServerWeb.StreamChannel
  channel "transcription:*", ServerWeb.TranscriptionChannel
  channel "correlation:*", ServerWeb.CorrelationChannel

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  # To deny connection, return `:error` or `{:error, term}`.
  #
  # See `Phoenix.Token` documentation for examples in
  # performing token verification on connect.
  @impl true
  def connect(params, socket, _connect_info) do
    # Tailscale provides network security - no application auth needed
    # Generate a correlation ID for this connection
    correlation_id = CorrelationId.generate()

    # Extract environment from params (defaults to "production" if not provided)
    environment = Map.get(params, "environment", "production")

    socket =
      socket
      |> assign(:correlation_id, correlation_id)
      |> assign(:environment, environment)

    # Log the connection
    Logger.info("WebSocket connection established",
      correlation_id: correlation_id,
      environment: environment
    )

    # Track this socket with Phoenix.Tracker
    ServerWeb.WebSocketTracker.track_socket(correlation_id, self())

    {:ok, socket}
  end

  # Socket IDs are topics that allow you to identify all sockets for a given user:
  #
  #     def id(socket), do: "user_socket:#{socket.assigns.user_id}"
  #
  # Would allow you to broadcast a "disconnect" event and terminate
  # all active sockets and channels for a given user:
  #
  #     Elixir.ServerWeb.Endpoint.broadcast("user_socket:#{user.id}", "disconnect", %{})
  #
  # Returning `nil` makes this socket anonymous.
  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.correlation_id}"
end

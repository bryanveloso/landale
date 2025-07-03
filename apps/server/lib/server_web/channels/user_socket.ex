defmodule ServerWeb.UserSocket do
  @moduledoc "Phoenix socket configuration for WebSocket connections."

  use Phoenix.Socket
  require Logger
  alias Server.CorrelationId

  # Channels
  channel "dashboard:*", ServerWeb.DashboardChannel
  channel "events:*", ServerWeb.EventsChannel
  channel "overlay:*", ServerWeb.OverlayChannel
  channel "transcription:*", ServerWeb.TranscriptionChannel

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
  def connect(_params, socket, _connect_info) do
    # Generate a correlation ID for this connection
    correlation_id = CorrelationId.generate()

    socket = assign(socket, :correlation_id, correlation_id)

    # Log the connection
    Logger.info("WebSocket connected", correlation_id: correlation_id)

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

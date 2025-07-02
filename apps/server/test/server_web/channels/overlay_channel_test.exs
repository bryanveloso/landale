defmodule ServerWeb.OverlayChannelTest do
  use ServerWeb.ChannelCase

  alias ServerWeb.{OverlayChannel, UserSocket}

  setup do
    {:ok, _, socket} =
      UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(OverlayChannel, "overlay:obs")

    %{socket: socket}
  end

  test "ping replies with pong", %{socket: socket} do
    ref = push(socket, "ping", %{hello: "there"})
    assert_reply ref, :ok, %{pong: true, hello: "there", overlay_type: "obs"}
  end

  test "obs:status returns status", %{socket: socket} do
    ref = push(socket, "obs:status", %{})
    assert_reply ref, :ok, _status
  end

  test "obs:stats returns statistics", %{socket: socket} do
    ref = push(socket, "obs:stats", %{})
    assert_reply ref, :ok, _stats
  end

  test "obs:version returns version info", %{socket: socket} do
    ref = push(socket, "obs:version", %{})
    assert_reply ref, :ok, _version
  end

  test "twitch:status returns status", %{socket: socket} do
    ref = push(socket, "twitch:status", %{})
    assert_reply ref, :ok, _status
  end

  test "system:status returns system information", %{socket: socket} do
    ref = push(socket, "system:status", %{})
    assert_reply ref, :ok, %{status: _status, timestamp: _timestamp}
  end

  test "ironmon:status returns ironmon tcp status", %{socket: socket} do
    ref = push(socket, "ironmon:status", %{})
    assert_reply ref, :ok, _status
  end

  test "ironmon:challenges returns challenge list", %{socket: socket} do
    ref = push(socket, "ironmon:challenges", %{})
    assert_reply ref, :ok, _challenges
  end

  test "rainwave:status returns music status", %{socket: socket} do
    ref = push(socket, "rainwave:status", %{})
    assert_reply ref, :ok, _status
  end

  test "unknown command returns error", %{socket: socket} do
    ref = push(socket, "unknown:command", %{})
    assert_reply ref, :error, %{message: "Unknown command: unknown:command"}
  end

  test "receives initial state on join" do
    {:ok, _, _socket} =
      UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(OverlayChannel, "overlay:system")

    assert_push "initial_state", %{type: "system", data: %{connected: true}}
  end
end

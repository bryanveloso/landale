defmodule ServerWeb.OverlayChannelTest do
  use ServerWeb.ChannelCase
  import Hammox

  @moduletag :web

  alias ServerWeb.{OverlayChannel, UserSocket}
  alias Server.Mocks.{IronmonTCPMock, OBSMock, RainwaveMock, TwitchMock}

  setup do
    # Don't set default expectations here since tests join different overlay types
    :ok
  end

  test "ping replies with pong" do
    # Join the obs overlay
    expect(OBSMock, :get_status, fn -> {:ok, %{connected: true}} end)

    {:ok, _, socket} =
      UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(OverlayChannel, "overlay:obs")

    ref = push(socket, "ping", %{"hello" => "there"})
    assert_reply ref, :ok, response

    assert %{pong: true, overlay_type: "obs"} = response
    assert Map.get(response, "hello") == "there"
    assert is_integer(Map.get(response, :timestamp))
  end

  test "obs:status returns status" do
    # Set up expectations for join
    expect(OBSMock, :get_status, fn -> {:ok, %{connected: true}} end)

    {:ok, _, socket} =
      UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(OverlayChannel, "overlay:obs")

    expect(OBSMock, :get_status, fn -> {:ok, %{connected: true, streaming: false}} end)

    ref = push(socket, "obs:status", %{})
    assert_reply ref, :ok, %{connected: true, streaming: false}
  end

  test "obs:stats returns statistics" do
    # Set up expectations for join
    expect(OBSMock, :get_status, fn -> {:ok, %{connected: true}} end)

    {:ok, _, socket} =
      UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(OverlayChannel, "overlay:obs")

    expect(OBSMock, :get_stats, fn -> {:ok, %{cpu_usage: 5.2, memory_usage: 1024}} end)

    ref = push(socket, "obs:stats", %{})
    assert_reply ref, :ok, %{cpu_usage: 5.2, memory_usage: 1024}
  end

  test "obs:version returns version info" do
    # Set up expectations for join
    expect(OBSMock, :get_status, fn -> {:ok, %{connected: true}} end)

    {:ok, _, socket} =
      UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(OverlayChannel, "overlay:obs")

    expect(OBSMock, :get_version, fn -> {:ok, %{obs_version: "30.0.0", obs_web_socket_version: "5.0.0"}} end)

    ref = push(socket, "obs:version", %{})
    assert_reply ref, :ok, %{obs_version: "30.0.0", obs_web_socket_version: "5.0.0"}
  end

  test "twitch:status returns status" do
    # Join the twitch overlay
    # For initial state
    expect(TwitchMock, :get_status, fn -> {:ok, %{connected: true}} end)

    {:ok, _, socket} =
      UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(OverlayChannel, "overlay:twitch")

    expect(TwitchMock, :get_status, fn -> {:ok, %{connected: true, subscriptions: 6}} end)

    ref = push(socket, "twitch:status", %{})
    assert_reply ref, :ok, %{connected: true, subscriptions: 6}
  end

  test "system:status returns system information" do
    # Join the system overlay
    {:ok, _, socket} =
      UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(OverlayChannel, "overlay:system")

    # Mock all service calls that system:status makes (won't call OBS for system overlay)
    # Note: system overlay doesn't call get_status on join, only when system:status is called

    ref = push(socket, "system:status", %{})
    assert_reply ref, :ok, response

    assert %{status: status, timestamp: timestamp} = response
    assert is_binary(status)
    assert is_integer(timestamp)
  end

  test "ironmon:status returns ironmon tcp status" do
    # Join the ironmon overlay
    {:ok, _, socket} =
      UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(OverlayChannel, "overlay:ironmon")

    expect(IronmonTCPMock, :get_status, fn -> {:ok, %{port: 8080, connected: true}} end)

    ref = push(socket, "ironmon:status", %{})
    assert_reply ref, :ok, %{port: 8080, connected: true}
  end

  test "ironmon:challenges returns challenge list" do
    # Join the ironmon overlay
    {:ok, _, socket} =
      UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(OverlayChannel, "overlay:ironmon")

    expect(IronmonTCPMock, :list_challenges, fn -> {:ok, [%{id: 1, name: "Elite Four"}]} end)

    ref = push(socket, "ironmon:challenges", %{})
    assert_reply ref, :ok, [%{id: 1, name: "Elite Four"}]
  end

  test "rainwave:status returns music status" do
    # Join the music overlay, not obs
    {:ok, _, socket} =
      UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(OverlayChannel, "overlay:music")

    expect(RainwaveMock, :get_status, fn -> {:ok, %{playing: true, current_song: "Test Song"}} end)

    ref = push(socket, "rainwave:status", %{})
    assert_reply ref, :ok, %{playing: true, current_song: "Test Song"}
  end

  test "unknown command returns error" do
    # Set up expectations for join
    expect(OBSMock, :get_status, fn -> {:ok, %{connected: true}} end)

    {:ok, _, socket} =
      UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(OverlayChannel, "overlay:obs")

    ref = push(socket, "unknown:command", %{})
    assert_reply ref, :error, %{message: "Unknown command: unknown:command"}
  end

  test "receives initial state on join" do
    # System overlay doesn't call services, just sends static data
    {:ok, _, _socket} =
      UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(OverlayChannel, "overlay:system")

    assert_push "initial_state", %{type: "system", data: %{connected: true}}
  end
end

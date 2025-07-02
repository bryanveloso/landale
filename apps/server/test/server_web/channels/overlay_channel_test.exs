defmodule ServerWeb.OverlayChannelTest do
  use ServerWeb.ChannelCase
  import Hammox

  alias ServerWeb.{OverlayChannel, UserSocket}
  alias Server.Mocks.{OBSMock, TwitchMock, IronmonTCPMock, RainwaveMock}

  setup do
    # Stub the initial state call that happens on join
    expect(OBSMock, :get_status, fn -> {:ok, %{connected: true}} end)

    {:ok, _, socket} =
      UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(OverlayChannel, "overlay:obs")

    %{socket: socket}
  end

  test "ping replies with pong", %{socket: socket} do
    ref = push(socket, "ping", %{"hello" => "there"})
    assert_reply ref, :ok, response

    assert %{pong: true, overlay_type: "obs"} = response
    assert Map.get(response, "hello") == "there"
    assert is_integer(Map.get(response, :timestamp))
  end

  test "obs:status returns status", %{socket: socket} do
    expect(OBSMock, :get_status, fn -> {:ok, %{connected: true, streaming: false}} end)

    ref = push(socket, "obs:status", %{})
    assert_reply ref, :ok, %{connected: true, streaming: false}
  end

  test "obs:stats returns statistics", %{socket: socket} do
    expect(OBSMock, :get_stats, fn -> {:ok, %{cpu_usage: 5.2, memory_usage: 1024}} end)

    ref = push(socket, "obs:stats", %{})
    assert_reply ref, :ok, %{cpu_usage: 5.2, memory_usage: 1024}
  end

  test "obs:version returns version info", %{socket: socket} do
    expect(OBSMock, :get_version, fn -> {:ok, %{obs_version: "30.0.0", obs_web_socket_version: "5.0.0"}} end)

    ref = push(socket, "obs:version", %{})
    assert_reply ref, :ok, %{obs_version: "30.0.0", obs_web_socket_version: "5.0.0"}
  end

  test "twitch:status returns status", %{socket: socket} do
    expect(TwitchMock, :get_status, fn -> {:ok, %{connected: true, subscriptions: 6}} end)

    ref = push(socket, "twitch:status", %{})
    assert_reply ref, :ok, %{connected: true, subscriptions: 6}
  end

  test "system:status returns system information", %{socket: socket} do
    # Mock all service calls that system:status makes
    expect(OBSMock, :get_status, fn -> {:ok, %{connected: true}} end)
    expect(TwitchMock, :get_status, fn -> {:ok, %{connected: true}} end)

    ref = push(socket, "system:status", %{})
    assert_reply ref, :ok, response

    assert %{status: status, timestamp: timestamp} = response
    assert is_binary(status)
    assert is_integer(timestamp)
  end

  test "ironmon:status returns ironmon tcp status", %{socket: socket} do
    expect(IronmonTCPMock, :get_status, fn -> {:ok, %{port: 8080, connected: true}} end)

    ref = push(socket, "ironmon:status", %{})
    assert_reply ref, :ok, %{port: 8080, connected: true}
  end

  test "ironmon:challenges returns challenge list", %{socket: socket} do
    expect(IronmonTCPMock, :list_challenges, fn -> {:ok, [%{id: 1, name: "Elite Four"}]} end)

    ref = push(socket, "ironmon:challenges", %{})
    assert_reply ref, :ok, [%{id: 1, name: "Elite Four"}]
  end

  test "rainwave:status returns music status", %{socket: socket} do
    expect(RainwaveMock, :get_status, fn -> {:ok, %{playing: true, current_song: "Test Song"}} end)

    ref = push(socket, "rainwave:status", %{})
    assert_reply ref, :ok, %{playing: true, current_song: "Test Song"}
  end

  test "unknown command returns error", %{socket: socket} do
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

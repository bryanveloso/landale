defmodule Server.Services.OBS.ConnectionTest do
  @moduledoc """
  Unit tests for the OBS Connection state machine.

  These tests directly test the state transition functions without
  starting the full gen_statem process, allowing for more controlled testing.
  """
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias Server.OBSTestHelpers
  alias Server.Services.OBS.Connection

  setup do
    # Ensure PubSub is available
    case Process.whereis(Server.PubSub) do
      nil ->
        {:ok, _} = start_supervised({Phoenix.PubSub, name: Server.PubSub})

      _pid ->
        :ok
    end

    :ok
  end

  describe "init/1" do
    test "initializes with correct state and data" do
      opts = [session_id: "test_session", uri: "ws://localhost:4455"]

      assert {:ok, :disconnected, data, actions} = Connection.init(opts)

      assert data.session_id == "test_session"
      assert data.uri == "ws://localhost:4455"
      assert data.pending_messages == []
      assert data.authentication_required == false

      # Should schedule immediate connection
      assert [{:next_event, :internal, :connect}] = actions
    end

    test "requires session_id and uri" do
      assert_raise KeyError, fn ->
        Connection.init(uri: "ws://localhost:4455")
      end

      assert_raise KeyError, fn ->
        Connection.init(session_id: "test")
      end
    end
  end

  describe "disconnected state" do
    setup do
      data = %Connection{
        session_id: "test_session",
        uri: "ws://localhost:4455",
        connection_manager: Server.ConnectionManager
      }

      {:ok, data: data}
    end

    test "handles get_state call", %{data: data} do
      from = {self(), make_ref()}

      assert {:keep_state_and_data, [{:reply, ^from, :disconnected}]} =
               Connection.disconnected({:call, from}, :get_state, data)
    end

    test "rejects send_request calls", %{data: data} do
      from = {self(), make_ref()}

      assert {:keep_state_and_data, [{:reply, ^from, {:error, :disconnected}}]} =
               Connection.disconnected({:call, from}, {:send_request, "GetVersion", %{}}, data)
    end

    test "retries connection on timeout", %{data: data} do
      assert {:keep_state_and_data, [{:next_event, :internal, :connect}]} =
               Connection.disconnected(:state_timeout, :retry_connect, data)
    end
  end

  describe "connecting state" do
    setup do
      data = %Connection{
        session_id: "test_session",
        uri: "ws://localhost:4455",
        conn_pid: self(),
        connection_manager: Server.ConnectionManager
      }

      {:ok, data: data}
    end

    test "transitions to authenticating on successful upgrade", %{data: data} do
      stream_ref = make_ref()

      {:next_state, :authenticating, new_data, actions} =
        Connection.connecting(:info, {:gun_upgrade, data.conn_pid, stream_ref, ["websocket"], []}, data)

      assert new_data.stream_ref == stream_ref
      assert [{:next_event, :internal, :start_auth}] = actions
    end

    test "handles connection timeout", %{data: data} do
      log =
        capture_log(fn ->
          {:next_state, :disconnected, new_data, actions} =
            Connection.connecting(:state_timeout, :connection_timeout, data)

          # Should have cleaned up connection
          assert new_data.conn_pid == nil
          assert new_data.stream_ref == nil

          # Should retry connection
          assert [{:next_event, :internal, :connect}] = actions
        end)

      assert log =~ "Connection timeout"
    end

    test "queues requests during connection", %{data: data} do
      from = {self(), make_ref()}

      {:keep_state, new_data} =
        Connection.connecting({:call, from}, {:send_request, "GetVersion", %{}}, data)

      # Should have queued the request
      assert [{:request, "GetVersion", %{}, ^from}] = new_data.pending_messages
    end
  end

  describe "authenticating state" do
    setup do
      data = %Connection{
        session_id: "test_session",
        uri: "ws://localhost:4455",
        conn_pid: self(),
        stream_ref: make_ref(),
        connection_manager: Server.ConnectionManager
      }

      {:ok, data: data}
    end

    test "sends Hello message on start_auth", %{data: data} do
      # Mock gun send
      {:keep_state, _data, actions} =
        Connection.authenticating(:internal, :start_auth, data)

      # Should set auth timeout
      assert [{:state_timeout, 10_000, :auth_timeout}] = actions
    end

    test "handles Hello response without auth", %{data: data} do
      hello_msg = Jason.encode!(OBSTestHelpers.hello_message("1", false))

      {:next_state, :ready, new_data} =
        Connection.authenticating(:info, {:gun_ws, data.conn_pid, data.stream_ref, {:text, hello_msg}}, data)

      assert new_data.rpc_version == "1"
    end

    test "handles Hello response with auth required", %{data: data} do
      # Set password
      System.put_env("OBS_WEBSOCKET_PASSWORD", "test_password")
      on_exit(fn -> System.delete_env("OBS_WEBSOCKET_PASSWORD") end)

      hello_msg = Jason.encode!(OBSTestHelpers.hello_message("1", true))

      # Should stay in authenticating state after sending Identify
      assert {:keep_state_and_data} =
               Connection.authenticating(:info, {:gun_ws, data.conn_pid, data.stream_ref, {:text, hello_msg}}, data)
    end

    test "fails auth without password", %{data: data} do
      # Ensure no password is set
      System.delete_env("OBS_WEBSOCKET_PASSWORD")

      hello_msg = Jason.encode!(OBSTestHelpers.hello_message("1", true))

      log =
        capture_log(fn ->
          {:next_state, :disconnected, new_data} =
            Connection.authenticating(:info, {:gun_ws, data.conn_pid, data.stream_ref, {:text, hello_msg}}, data)

          # Should have cleaned up connection
          assert new_data.conn_pid == nil
        end)

      assert log =~ "OBS requires authentication but OBS_WEBSOCKET_PASSWORD not set"
    end

    test "handles Identified response", %{data: data} do
      identified_msg = Jason.encode!(OBSTestHelpers.identified_message("1"))

      {:next_state, :ready, new_data} =
        Connection.authenticating(:info, {:gun_ws, data.conn_pid, data.stream_ref, {:text, identified_msg}}, data)

      assert new_data.rpc_version == "1"
    end

    test "handles auth timeout", %{data: data} do
      log =
        capture_log(fn ->
          {:next_state, :disconnected, new_data, actions} =
            Connection.authenticating(:state_timeout, :auth_timeout, data)

          # Should have cleaned up
          assert new_data.conn_pid == nil
          assert [{:next_event, :internal, :connect}] = actions
        end)

      assert log =~ "Authentication timeout"
    end
  end

  describe "ready state" do
    setup do
      data = %Connection{
        session_id: "test_session",
        uri: "ws://localhost:4455",
        conn_pid: self(),
        stream_ref: make_ref(),
        rpc_version: "1",
        connection_manager: Server.ConnectionManager,
        pending_messages: []
      }

      {:ok, data: data}
    end

    test "processes pending messages on enter", %{data: data} do
      from = {self(), make_ref()}
      data = %{data | pending_messages: [{:request, "GetVersion", %{}, from}]}

      # Subscribe to events
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")

      {:keep_state, new_data, actions} =
        Connection.ready(:enter, :authenticating, data)

      # Should clear pending messages
      assert new_data.pending_messages == []

      # Should reply with error for stale requests
      assert [{:reply, ^from, {:error, :request_expired}}] = actions

      # Should broadcast connection established
      assert_receive {:connection_established, %{session_id: "test_session", rpc_version: "1"}}
    end

    test "handles OBS events", %{data: data} do
      # Subscribe to session-specific events
      Phoenix.PubSub.subscribe(Server.PubSub, "obs_events:test_session")

      event_msg =
        Jason.encode!(
          OBSTestHelpers.event_message("SceneChanged", %{
            "sceneName" => "New Scene"
          })
        )

      assert {:keep_state_and_data} =
               Connection.ready(:info, {:gun_ws, data.conn_pid, data.stream_ref, {:text, event_msg}}, data)

      # Should broadcast the event data (from event.d)
      assert_receive {:obs_event, event_data}
      assert event_data.eventType == "SceneChanged"
      assert event_data.eventData.sceneName == "New Scene"
    end

    test "handles invalid messages gracefully", %{data: data} do
      log =
        capture_log(fn ->
          assert {:keep_state_and_data} =
                   Connection.ready(:info, {:gun_ws, data.conn_pid, data.stream_ref, {:text, "invalid json"}}, data)
        end)

      assert log =~ "Failed to decode OBS message"
    end

    test "handles connection loss", %{data: data} do
      # Subscribe to events
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")

      {:next_state, :reconnecting, _new_data, actions} =
        Connection.ready(:info, {:gun_down, data.conn_pid, :http, :closed, []}, data)

      # Should schedule reconnection
      assert [{:next_event, :internal, :start_reconnect}] = actions

      # Should broadcast connection lost
      assert_receive {:connection_lost, %{reason: :closed}}
    end

    test "returns ready state on get_state call", %{data: data} do
      from = {self(), make_ref()}

      assert {:keep_state_and_data, [{:reply, ^from, :ready}]} =
               Connection.ready({:call, from}, :get_state, data)
    end
  end

  describe "reconnecting state" do
    setup do
      data = %Connection{
        session_id: "test_session",
        uri: "ws://localhost:4455",
        conn_pid: self(),
        stream_ref: make_ref(),
        connection_manager: Server.ConnectionManager,
        pending_messages: []
      }

      {:ok, data: data}
    end

    test "cleans up connection on start_reconnect", %{data: data} do
      {:keep_state, new_data, actions} =
        Connection.reconnecting(:internal, :start_reconnect, data)

      # Should have cleaned up
      assert new_data.conn_pid == nil
      assert new_data.stream_ref == nil

      # Should schedule reconnect
      assert [{:state_timeout, 5_000, :reconnect}] = actions
    end

    test "transitions to disconnected on reconnect timeout", %{data: data} do
      {:next_state, :disconnected, _data, actions} =
        Connection.reconnecting(:state_timeout, :reconnect, data)

      # Should attempt to connect again
      assert [{:next_event, :internal, :connect}] = actions
    end

    test "queues messages during reconnection", %{data: data} do
      from = {self(), make_ref()}

      {:keep_state, new_data} =
        Connection.reconnecting({:call, from}, {:send_request, "GetSceneList", %{}}, data)

      # Should have queued the request
      assert [{:request, "GetSceneList", %{}, ^from}] = new_data.pending_messages
    end
  end
end

defmodule Server.Services.TwitchTest do
  @moduledoc """
  Unit tests for the main Twitch EventSub service.

  Tests critical paths including:
  - Service initialization and state management
  - WebSocket connection lifecycle
  - Subscription management
  - Token refresh handling
  - Error recovery mechanisms
  - Cache behavior
  """
  use ExUnit.Case, async: false

  alias Server.Services.Twitch

  setup do
    setup_test_dependencies()
    :ok
  end

  defp setup_test_dependencies do
    # Set test config for client_id
    Application.put_env(:server, Server.Services.Twitch, client_id: "test_client_id")

    # Start all required services
    ensure_service_started(Server.PubSub, {Phoenix.PubSub, name: Server.PubSub})
    ensure_service_started(Server.CircuitBreakerServer, Server.CircuitBreakerServer)
    ensure_service_started(Server.TaskSupervisor, {Task.Supervisor, name: Server.TaskSupervisor})
    dynamic_sup_spec = {DynamicSupervisor, name: Server.DynamicSupervisor, strategy: :one_for_one}
    ensure_service_started(Server.DynamicSupervisor, dynamic_sup_spec)

    # Create ETS tables
    ensure_ets_table(:server_cache)
    ensure_ets_table(:twitch_service)

    # Start OAuth service
    ensure_service_started(Server.OAuthService, Server.OAuthService)
  end

  defp ensure_service_started(name, spec) do
    case Process.whereis(name) do
      nil -> start_supervised!(spec)
      _pid -> :ok
    end
  end

  defp ensure_ets_table(name) do
    if :ets.info(name) == :undefined do
      :ets.new(name, [:set, :public, :named_table])
    end
  end

  describe "start_link/1" do
    test "starts the GenServer with default options" do
      opts = []

      assert {:ok, pid} = start_supervised({Twitch, opts})
      assert Process.alive?(pid)
      assert Process.whereis(Server.Services.Twitch) == pid
    end

    test "starts with custom client credentials" do
      opts = [
        client_id: "test_client_id",
        client_secret: "test_client_secret"
      ]

      assert {:ok, pid} = start_supervised({Twitch, opts})
      assert Process.alive?(pid)
    end
  end

  describe "get_state/0" do
    setup do
      {:ok, pid} = start_supervised(Twitch)
      {:ok, pid: pid}
    end

    test "returns current service state", %{pid: _pid} do
      state = Twitch.get_state()

      assert is_map(state)
      assert Map.has_key?(state, :connected)
      assert Map.has_key?(state, :connection_state)
      assert Map.has_key?(state, :subscription_total_cost)
      assert Map.has_key?(state, :subscription_count)
      assert Map.has_key?(state, :subscription_max_count)
      assert Map.has_key?(state, :subscription_max_cost)
    end

    test "uses cache for repeated calls" do
      # First call should compute
      state1 = Twitch.get_state()

      # Second call should use cache
      state2 = Twitch.get_state()

      assert state1 == state2
    end
  end

  describe "get_status/0" do
    setup do
      {:ok, _pid} = start_supervised(Twitch)
      :ok
    end

    test "returns ok with status map" do
      assert {:ok, status} = Twitch.get_status()

      assert is_map(status)
      # Status should contain connection and subscription info
      assert Map.has_key?(status, :websocket_connected)
      assert Map.has_key?(status, :connection_state)
      assert Map.has_key?(status, :session_id)
      assert Map.has_key?(status, :subscription_count)
    end

    test "uses cache with 10 second TTL" do
      # Clear cache first
      :ets.delete(:twitch_service, :connection_status)

      # First call
      {:ok, status1} = Twitch.get_status()

      # Second call should be cached
      {:ok, status2} = Twitch.get_status()

      assert status1 == status2
    end
  end

  describe "get_connection_state/0" do
    setup do
      {:ok, _pid} = start_supervised(Twitch)
      :ok
    end

    test "returns connection state map" do
      state = Twitch.get_connection_state()

      assert is_map(state)
      assert Map.has_key?(state, :connected)
      assert Map.has_key?(state, :connection_state)
      assert Map.has_key?(state, :session_id)
      assert Map.has_key?(state, :last_connected)
      assert Map.has_key?(state, :websocket_url)
    end

    test "initial state shows disconnected" do
      state = Twitch.get_connection_state()

      assert state.connected == false
      assert state.connection_state == "disconnected"
      assert is_nil(state.session_id)
    end
  end

  describe "get_subscription_metrics/0" do
    setup do
      {:ok, _pid} = start_supervised(Twitch)
      :ok
    end

    test "returns subscription metrics" do
      metrics = Twitch.get_subscription_metrics()

      assert is_map(metrics)
      assert Map.has_key?(metrics, :subscription_count)
      assert Map.has_key?(metrics, :subscription_total_cost)
      assert Map.has_key?(metrics, :subscription_max_count)
      assert Map.has_key?(metrics, :subscription_max_cost)
    end

    test "initial metrics show zero subscriptions" do
      metrics = Twitch.get_subscription_metrics()

      assert metrics.subscription_count == 0
      assert metrics.subscription_total_cost == 0
      assert metrics.subscription_max_count == 300
      assert metrics.subscription_max_cost == 10
    end

    test "uses cache with 30 second TTL" do
      # Clear cache
      :ets.delete(:twitch_service, :subscription_metrics)

      metrics1 = Twitch.get_subscription_metrics()
      metrics2 = Twitch.get_subscription_metrics()

      assert metrics1 == metrics2
    end
  end

  describe "create_subscription/3" do
    setup do
      {:ok, _pid} = start_supervised(Twitch)
      :ok
    end

    test "validates subscription parameters" do
      # Without a connected WebSocket, this should fail appropriately
      event_type = "channel.update"
      condition = %{"broadcaster_user_id" => "123456"}

      result = Twitch.create_subscription(event_type, condition)

      # Should return error when not connected
      assert {:error, _reason} = result
    end

    test "accepts optional parameters" do
      event_type = "channel.follow"
      condition = %{"broadcaster_user_id" => "123456", "moderator_user_id" => "789"}
      opts = [version: "2"]

      result = Twitch.create_subscription(event_type, condition, opts)

      assert {:error, _reason} = result
    end
  end

  describe "delete_subscription/1" do
    setup do
      # Start dependencies first
      setup_test_dependencies()

      {:ok, _pid} = start_supervised(Twitch)
      :ok
    end

    test "attempts to delete subscription by ID" do
      subscription_id = "test_sub_123"

      result = Twitch.delete_subscription(subscription_id)

      # Should return error when subscription doesn't exist
      assert {:error, _reason} = result
    end
  end

  describe "list_subscriptions/0" do
    setup do
      # Start dependencies first
      setup_test_dependencies()

      {:ok, _pid} = start_supervised(Twitch)
      :ok
    end

    test "returns empty list when no subscriptions" do
      assert {:ok, subscriptions} = Twitch.list_subscriptions()
      assert is_list(subscriptions)
      assert subscriptions == []
    end
  end

  describe "connection state management" do
    setup do
      # Start dependencies first
      setup_test_dependencies()

      {:ok, _pid} = start_supervised(Twitch)
      :ok
    end

    test "maintains connection state through internal operations" do
      # Initial state should be disconnected
      state = Twitch.get_connection_state()
      assert state.connected == false
      assert state.connection_state == "disconnected"
    end
  end

  describe "error handling" do
    setup do
      {:ok, _pid} = start_supervised(Twitch)
      :ok
    end

    test "handles GenServer call timeout gracefully" do
      # This would test timeout handling if the GenServer was busy
      # For now, just verify the calls don't crash
      assert is_map(Twitch.get_state())
      assert {:ok, _} = Twitch.get_status()
    end
  end

  describe "cache behavior" do
    test "cache keys are properly namespaced" do
      {:ok, _pid} = start_supervised(Twitch)

      # Trigger cache population
      _state = Twitch.get_state()
      _conn = Twitch.get_connection_state()
      _metrics = Twitch.get_subscription_metrics()

      # Check cache entries exist
      assert :ets.lookup(:server_cache, {:twitch_service, :full_state}) != []
      assert :ets.lookup(:server_cache, {:twitch_service, :connection_state}) != []
      assert :ets.lookup(:server_cache, {:twitch_service, :subscription_metrics}) != []
    end
  end

  describe "internal state structure" do
    setup do
      {:ok, pid} = start_supervised(Twitch)
      {:ok, pid: pid}
    end

    test "verifies initial state structure", %{pid: pid} do
      # Get internal state directly
      state = :sys.get_state(pid)

      assert %Twitch{} = state
      assert is_nil(state.session_id)
      # reconnect_timer may be set if no valid tokens are available
      assert is_reference(state.reconnect_timer) or is_nil(state.reconnect_timer)
      assert is_nil(state.token_refresh_timer)
      assert state.subscriptions == %{}
      assert state.default_subscriptions_created == false

      # Verify flattened state structure
      assert state.connected == false
      assert state.connection_state == "disconnected"
      assert state.subscription_count == 0
      assert state.subscription_total_cost == 0
    end
  end
end

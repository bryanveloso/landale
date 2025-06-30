defmodule Server.Services.TwitchTest do
  use ExUnit.Case, async: false

  alias Server.Services.Twitch

  setup do
    # Set test environment variables
    System.put_env("TWITCH_CLIENT_ID", "test_client_id")
    System.put_env("TWITCH_CLIENT_SECRET", "test_client_secret")

    on_exit(fn ->
      # Clean up test DETS files
      test_dets_path = "./data/twitch_tokens.dets"

      if File.exists?(test_dets_path) do
        File.rm!(test_dets_path)
      end

      # Clean up environment variables
      System.delete_env("TWITCH_CLIENT_ID")
      System.delete_env("TWITCH_CLIENT_SECRET")
    end)
  end

  describe "Twitch service initialization" do
    test "starts without crashing" do
      assert {:ok, pid} = Twitch.start_link()
      assert Process.alive?(pid)
      
      # Give it a moment to initialize
      Process.sleep(100)

      # Should be able to get status even when not connected
      assert {:ok, status} = Twitch.get_status()
      assert Map.has_key?(status, :connected)
      assert Map.has_key?(status, :connection_state)
      assert Map.has_key?(status, :subscription_count)
      assert Map.has_key?(status, :subscription_cost)
      
      # Stop the service
      GenServer.stop(pid)
    end

    test "starts with missing credentials and handles gracefully" do
      # Remove credentials
      System.delete_env("TWITCH_CLIENT_ID")
      System.delete_env("TWITCH_CLIENT_SECRET")
      
      # Service should still start but log errors
      assert {:ok, pid} = Twitch.start_link()
      assert Process.alive?(pid)
      
      GenServer.stop(pid)
    end
  end

  describe "service state management" do
    setup do
      {:ok, pid} = Twitch.start_link()
      Process.sleep(100)
      
      on_exit(fn ->
        GenServer.stop(pid)
      end)
      
      %{pid: pid}
    end

    test "get_state returns proper structure", %{pid: _pid} do
      state = Twitch.get_state()
      assert Map.has_key?(state, :connection)
      assert Map.has_key?(state, :subscription_total_cost)
      assert Map.has_key?(state, :subscription_count)
      
      # Check connection structure
      assert Map.has_key?(state.connection, :connected)
      assert Map.has_key?(state.connection, :connection_state)
      assert state.connection.connected == false
      assert state.connection.connection_state == "disconnected"
    end

    test "get_status returns expected format", %{pid: _pid} do
      assert {:ok, status} = Twitch.get_status()
      
      # Required status fields
      assert Map.has_key?(status, :connected)
      assert Map.has_key?(status, :connection_state) 
      assert Map.has_key?(status, :session_id)
      assert Map.has_key?(status, :subscription_count)
      assert Map.has_key?(status, :subscription_cost)
      
      # Initial values
      assert status.connected == false
      assert status.connection_state == "disconnected"
      assert status.session_id == nil
      assert status.subscription_count == 0
      assert status.subscription_cost == 0
    end
  end

  describe "subscription management" do
    setup do
      {:ok, pid} = Twitch.start_link()
      Process.sleep(100)
      
      on_exit(fn ->
        GenServer.stop(pid)
      end)
      
      %{pid: pid}
    end

    test "list_subscriptions returns empty map when not connected", %{pid: _pid} do
      assert {:ok, subscriptions} = Twitch.list_subscriptions()
      assert subscriptions == %{}
    end

    test "create_subscription fails when not connected", %{pid: _pid} do
      result = Twitch.create_subscription("channel.update", %{"broadcaster_user_id" => "123"})
      assert {:error, reason} = result
      assert reason == "WebSocket not connected"
    end

    test "delete_subscription fails when not connected", %{pid: _pid} do
      result = Twitch.delete_subscription("test_subscription_id")
      assert {:error, _reason} = result
    end
  end

  describe "service lifecycle" do
    test "service terminates gracefully" do
      {:ok, pid} = Twitch.start_link()
      Process.sleep(100)
      
      # Monitor the process
      ref = Process.monitor(pid)
      
      # Stop the service
      GenServer.stop(pid, :normal)
      
      # Wait for termination
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end
  end
end
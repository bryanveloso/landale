defmodule Server.Services.TwitchTest do
  use ExUnit.Case, async: false

  alias Server.Services.Twitch

  setup do
    # Use test environment credentials (these should be dummy values)
    Application.put_env(:server, :twitch_client_id, "test_client_id")
    Application.put_env(:server, :twitch_client_secret, "test_client_secret")

    on_exit(fn ->
      # Clean up any test DETS files
      test_dets_path = "./test_data/twitch_tokens.dets"

      if File.exists?(test_dets_path) do
        File.rm!(test_dets_path)
      end
    end)
  end

  describe "Twitch service" do
    test "starts without crashing" do
      assert {:ok, _pid} = Twitch.start_link()
      # Give it a moment to initialize
      Process.sleep(100)

      # Should be able to get status even when not connected
      assert {:ok, status} = Twitch.get_status()
      assert Map.has_key?(status, :connected)
      assert Map.has_key?(status, :connection_state)
      assert Map.has_key?(status, :subscription_count)
      assert Map.has_key?(status, :subscription_cost)
    end

    test "get_state returns proper structure" do
      {:ok, _pid} = Twitch.start_link()
      Process.sleep(100)

      state = Twitch.get_state()
      assert Map.has_key?(state, :connection)
      assert Map.has_key?(state, :subscription_total_cost)
      assert Map.has_key?(state, :subscription_count)
    end

    test "list_subscriptions returns empty list when not connected" do
      {:ok, _pid} = Twitch.start_link()
      Process.sleep(100)

      assert {:ok, []} = Twitch.list_subscriptions()
    end

    test "create_subscription fails when not connected" do
      {:ok, _pid} = Twitch.start_link()
      Process.sleep(100)

      result = Twitch.create_subscription("channel.update", %{"broadcaster_user_id" => "123"})
      assert {:error, _reason} = result
    end
  end
end

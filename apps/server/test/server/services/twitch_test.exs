defmodule Server.Services.TwitchTest do
  use ExUnit.Case, async: true

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

  describe "GenServer lifecycle" do
    test "starts successfully with environment config" do
      assert {:ok, pid} = GenServer.start_link(Twitch, [])
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "public API functions" do
    setup do
      {:ok, pid} = GenServer.start_link(Twitch, [])
      on_exit(fn -> GenServer.stop(pid) end)
      %{pid: pid}
    end

    test "get_status/0 returns service status" do
      result = Twitch.get_status()
      assert {:ok, status} = result
      assert is_map(status)
      assert Map.has_key?(status, :connected)
    end
  end
end

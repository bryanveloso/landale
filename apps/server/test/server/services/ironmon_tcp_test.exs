defmodule Server.Services.IronmonTCPTest do
  use ExUnit.Case, async: true

  alias Server.Services.IronmonTCP

  describe "GenServer lifecycle" do
    test "starts successfully with default config" do
      assert {:ok, pid} = GenServer.start_link(IronmonTCP, [])
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "public API functions" do
    setup do
      {:ok, pid} = GenServer.start_link(IronmonTCP, [])
      on_exit(fn -> GenServer.stop(pid) end)
      %{pid: pid}
    end

    test "get_status/0 returns service status" do
      result = IronmonTCP.get_status()
      assert {:ok, status} = result
      assert is_map(status)
      assert Map.has_key?(status, :port)
    end

    test "list_challenges/0 returns challenges when disconnected" do
      result = IronmonTCP.list_challenges()
      # Should return error when no client connected
      assert {:error, _reason} = result
    end

    test "list_checkpoints/1 returns checkpoints when disconnected" do
      result = IronmonTCP.list_checkpoints(1)
      # Should return error when no client connected
      assert {:error, _reason} = result
    end

    test "get_checkpoint_stats/1 returns stats when disconnected" do
      result = IronmonTCP.get_checkpoint_stats(1)
      # Should return error when no client connected
      assert {:error, _reason} = result
    end

    test "get_recent_results/1 returns results when disconnected" do
      result = IronmonTCP.get_recent_results(10)
      # Should return error when no client connected
      assert {:error, _reason} = result
    end

    test "get_active_challenge/1 returns challenge when disconnected" do
      result = IronmonTCP.get_active_challenge(123)
      # Should return error when no client connected
      assert {:error, _reason} = result
    end
  end
end

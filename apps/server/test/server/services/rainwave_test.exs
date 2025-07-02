defmodule Server.Services.RainwaveTest do
  use ExUnit.Case, async: true

  alias Server.Services.Rainwave

  describe "GenServer lifecycle" do
    test "starts successfully with default config" do
      assert {:ok, pid} = GenServer.start_link(Rainwave, [])
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "public API functions" do
    setup do
      {:ok, pid} = GenServer.start_link(Rainwave, [])
      on_exit(fn -> GenServer.stop(pid) end)
      %{pid: pid}
    end

    test "get_status/0 returns service status" do
      result = Rainwave.get_status()
      assert {:ok, status} = result
      assert is_map(status)
      assert Map.has_key?(status, :connected)
    end
  end
end

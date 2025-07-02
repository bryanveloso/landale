defmodule Server.Services.OBSTest do
  use ExUnit.Case, async: true

  alias Server.Services.OBS

  describe "GenServer lifecycle" do
    test "starts successfully with default config" do
      assert {:ok, pid} = GenServer.start_link(OBS, [])
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with custom websocket URL" do
      config = [websocket_url: "ws://localhost:4455"]
      assert {:ok, pid} = GenServer.start_link(OBS, config)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "public API functions" do
    setup do
      {:ok, pid} = GenServer.start_link(OBS, [])
      on_exit(fn -> GenServer.stop(pid) end)
      %{pid: pid}
    end

    test "get_status/0 returns service status" do
      result = OBS.get_status()
      assert {:ok, status} = result
      assert is_map(status)
      assert Map.has_key?(status, :connected)
    end

    test "get_stats/0 returns OBS statistics when disconnected" do
      result = OBS.get_stats()
      # Should return error when not connected to OBS
      assert {:error, _reason} = result
    end

    test "get_version/0 returns version information when disconnected" do
      result = OBS.get_version()
      # Should return error when not connected to OBS
      assert {:error, _reason} = result
    end

    test "get_scene_list/0 returns scene information when disconnected" do
      result = OBS.get_scene_list()
      # Should return error when not connected to OBS
      assert {:error, _reason} = result
    end

    test "get_stream_status/0 returns streaming status when disconnected" do
      result = OBS.get_stream_status()
      # Should return error when not connected to OBS
      assert {:error, _reason} = result
    end

    test "get_record_status/0 returns recording status when disconnected" do
      result = OBS.get_record_status()
      # Should return error when not connected to OBS
      assert {:error, _reason} = result
    end

    test "get_virtual_cam_status/0 returns virtual camera status when disconnected" do
      result = OBS.get_virtual_cam_status()
      # Should return error when not connected to OBS
      assert {:error, _reason} = result
    end

    test "get_output_list/0 returns output configurations when disconnected" do
      result = OBS.get_output_list()
      # Should return error when not connected to OBS
      assert {:error, _reason} = result
    end
  end
end

defmodule Server.Services.OBSTest do
  use ExUnit.Case, async: false

  alias Server.Services.OBS

  describe "OBS service" do
    @tag :skip
    test "starts without crashing" do
      assert {:ok, _pid} = OBS.start_link()
      # Give it a moment to initialize
      Process.sleep(100)

      # Should be able to get status even when not connected
      assert {:ok, status} = OBS.get_status()
      assert Map.has_key?(status, :connected)
      assert Map.has_key?(status, :connection_state)
    end

    @tag :skip
    test "get_state returns proper structure" do
      {:ok, _pid} = OBS.start_link()
      Process.sleep(100)

      state = OBS.get_state()
      assert Map.has_key?(state, :connection)
      assert Map.has_key?(state, :scenes)
      assert Map.has_key?(state, :streaming)
      assert Map.has_key?(state, :recording)
    end

    @tag :skip
    test "commands return error when not connected" do
      {:ok, _pid} = OBS.start_link()
      Process.sleep(100)

      assert {:error, "OBS not connected"} = OBS.start_streaming()
      assert {:error, "OBS not connected"} = OBS.stop_streaming()
      assert {:error, "OBS not connected"} = OBS.start_recording()
      assert {:error, "OBS not connected"} = OBS.stop_recording()
    end
  end
end

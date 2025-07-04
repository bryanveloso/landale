defmodule NurvusTest do
  use ExUnit.Case
  doctest Nurvus

  @moduletag :unit

  test "add_process adds a process configuration" do
    config = %{
      "id" => "test_process",
      "name" => "Test Process",
      "command" => "echo",
      "args" => ["hello"]
    }

    assert :ok = Nurvus.add_process(config)
  end

  test "list_processes returns process list" do
    assert {:ok, processes} = Nurvus.list_processes()
    assert is_list(processes)
  end

  test "system_status returns system information" do
    assert {:ok, status} = Nurvus.system_status()
    assert Map.has_key?(status, :platform)
    assert Map.has_key?(status, :uptime)
  end
end

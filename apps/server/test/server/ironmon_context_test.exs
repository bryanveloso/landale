defmodule Server.IronmonContextTest do
  use Server.DataCase, async: false

  alias Server.Ironmon

  describe "StreamProducer context functions (without RunTracker)" do
    test "get_recent_checkpoint_clears/1 returns empty list when no clears" do
      assert Ironmon.get_recent_checkpoint_clears() == []
    end

    test "get_run_statistics/0 returns global stats even with no runs" do
      stats = Ironmon.get_run_statistics()

      assert stats.total_attempts == 0
      assert stats.total_checkpoint_attempts == 0
      assert stats.total_checkpoint_clears == 0
      assert stats.overall_clear_rate == 0.0
    end
  end

  describe "StreamProducer context functions (with test data)" do
    setup do
      # Create test data
      {:ok, challenge} = Ironmon.create_challenge(%{name: "Standard Ironmon", id: 1})

      {:ok, checkpoint1} =
        Ironmon.create_checkpoint(%{
          name: "Vs. 1st Trainer",
          trainer: "Youngster Joey",
          challenge_id: challenge.id,
          order: 1
        })

      {:ok, checkpoint2} =
        Ironmon.create_checkpoint(%{
          name: "Vs. Brock",
          trainer: "Brock",
          challenge_id: challenge.id,
          order: 2
        })

      {:ok, seed} = Ironmon.create_seed(%{id: 100, challenge_id: challenge.id})

      %{challenge: challenge, checkpoint1: checkpoint1, checkpoint2: checkpoint2, seed: seed}
    end

    test "get_recent_checkpoint_clears/1 returns clears when they exist", %{seed: seed, checkpoint1: checkpoint1} do
      # Create a successful clear
      {:ok, _result} = Ironmon.create_or_update_result(seed.id, checkpoint1.id, true)

      clears = Ironmon.get_recent_checkpoint_clears()
      assert length(clears) == 1
      assert hd(clears).checkpoint_name == "Vs. 1st Trainer"
      assert hd(clears).trainer == "Youngster Joey"
      assert hd(clears).seed_id == seed.id
    end
  end
end

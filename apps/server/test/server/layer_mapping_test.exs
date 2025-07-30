defmodule Server.LayerMappingTest do
  use ExUnit.Case

  alias Server.LayerMapping

  describe "get_layer/2" do
    test "returns correct layer for ironmon show events" do
      assert LayerMapping.get_layer("death_alert", "ironmon") == "foreground"
      assert LayerMapping.get_layer("level_up", "ironmon") == "midground"
      assert LayerMapping.get_layer("ironmon_run_stats", "ironmon") == "background"
    end

    test "returns correct layer for variety show events" do
      assert LayerMapping.get_layer("raid_alert", "variety") == "foreground"
      assert LayerMapping.get_layer("sub_train", "variety") == "midground"
      assert LayerMapping.get_layer("emote_stats", "variety") == "background"
    end

    test "returns correct layer for coding show events" do
      assert LayerMapping.get_layer("build_failure", "coding") == "foreground"
      assert LayerMapping.get_layer("pr_merged", "coding") == "midground"
      assert LayerMapping.get_layer("commit_stats", "coding") == "background"
    end

    test "handles atom show names" do
      assert LayerMapping.get_layer("death_alert", :ironmon) == "foreground"
    end

    test "returns background for unknown content types" do
      assert LayerMapping.get_layer("unknown_event", "ironmon") == "background"
    end

    test "uses default mapping for unknown shows" do
      assert LayerMapping.get_layer("alert", "unknown_show") == "foreground"
      assert LayerMapping.get_layer("sub_train", "unknown_show") == "midground"
    end
  end

  describe "get_mappings_for_show/1" do
    test "returns all mappings for a show" do
      mappings = LayerMapping.get_mappings_for_show("ironmon")
      assert is_map(mappings)
      assert mappings["death_alert"] == "foreground"
      assert mappings["level_up"] == "midground"
    end

    test "returns default mappings for unknown show" do
      mappings = LayerMapping.get_mappings_for_show("unknown")
      assert mappings["alert"] == "foreground"
    end
  end

  describe "get_show_types/0" do
    test "returns all available show types" do
      shows = LayerMapping.get_show_types()
      assert "ironmon" in shows
      assert "variety" in shows
      assert "coding" in shows
      assert length(shows) == 3
    end
  end

  describe "get_content_types_for_layer/2" do
    test "returns all content types for a layer" do
      foreground_types = LayerMapping.get_content_types_for_layer("foreground", "ironmon")
      assert "death_alert" in foreground_types
      assert "elite_four_alert" in foreground_types
      assert "shiny_encounter" in foreground_types
      assert "alert" in foreground_types
    end

    test "returns empty list for non-existent layer" do
      types = LayerMapping.get_content_types_for_layer("invalid_layer", "ironmon")
      assert types == []
    end
  end

  describe "should_display_on_layer?/3" do
    test "returns true when content matches layer" do
      assert LayerMapping.should_display_on_layer?("death_alert", "foreground", "ironmon")
      assert LayerMapping.should_display_on_layer?("level_up", "midground", "ironmon")
    end

    test "returns false when content doesn't match layer" do
      refute LayerMapping.should_display_on_layer?("death_alert", "background", "ironmon")
      refute LayerMapping.should_display_on_layer?("emote_stats", "foreground", "variety")
    end
  end
end

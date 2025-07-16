defmodule Server.Domains.LayerCoordinationTest do
  @moduledoc """
  TDD tests for pure layer coordination domain logic.

  These tests drive the implementation of pure functions for mapping content 
  to visual layer priorities across different show contexts.
  """

  use ExUnit.Case, async: true

  alias Server.Domains.LayerCoordination

  describe "determine_layer_for_content/2" do
    test "maps death_alert to foreground in ironmon context" do
      layer = LayerCoordination.determine_layer_for_content(:death_alert, :ironmon)
      assert layer == :foreground
    end

    test "maps elite_four_alert to foreground in ironmon context" do
      layer = LayerCoordination.determine_layer_for_content(:elite_four_alert, :ironmon)
      assert layer == :foreground
    end

    test "maps shiny_encounter to foreground in ironmon context" do
      layer = LayerCoordination.determine_layer_for_content(:shiny_encounter, :ironmon)
      assert layer == :foreground
    end

    test "maps generic alert to foreground across all show contexts" do
      assert LayerCoordination.determine_layer_for_content(:alert, :ironmon) == :foreground
      assert LayerCoordination.determine_layer_for_content(:alert, :variety) == :foreground
      assert LayerCoordination.determine_layer_for_content(:alert, :coding) == :foreground
    end

    test "maps sub_train to midground across all show contexts" do
      assert LayerCoordination.determine_layer_for_content(:sub_train, :ironmon) == :midground
      assert LayerCoordination.determine_layer_for_content(:sub_train, :variety) == :midground
      assert LayerCoordination.determine_layer_for_content(:sub_train, :coding) == :midground
    end

    test "maps level_up to midground in ironmon context" do
      layer = LayerCoordination.determine_layer_for_content(:level_up, :ironmon)
      assert layer == :midground
    end

    test "maps gym_badge to midground in ironmon context" do
      layer = LayerCoordination.determine_layer_for_content(:gym_badge, :ironmon)
      assert layer == :midground
    end

    test "maps cheer_celebration to midground across show contexts" do
      assert LayerCoordination.determine_layer_for_content(:cheer_celebration, :ironmon) == :midground
      assert LayerCoordination.determine_layer_for_content(:cheer_celebration, :variety) == :midground
      assert LayerCoordination.determine_layer_for_content(:cheer_celebration, :coding) == :midground
    end

    test "maps ironmon_run_stats to background in ironmon context" do
      layer = LayerCoordination.determine_layer_for_content(:ironmon_run_stats, :ironmon)
      assert layer == :background
    end

    test "maps ironmon_deaths to background in ironmon context" do
      layer = LayerCoordination.determine_layer_for_content(:ironmon_deaths, :ironmon)
      assert layer == :background
    end

    test "maps emote_stats to background across all show contexts" do
      assert LayerCoordination.determine_layer_for_content(:emote_stats, :ironmon) == :background
      assert LayerCoordination.determine_layer_for_content(:emote_stats, :variety) == :background
      assert LayerCoordination.determine_layer_for_content(:emote_stats, :coding) == :background
    end

    test "maps recent_follows to background across all show contexts" do
      assert LayerCoordination.determine_layer_for_content(:recent_follows, :ironmon) == :background
      assert LayerCoordination.determine_layer_for_content(:recent_follows, :variety) == :background
      assert LayerCoordination.determine_layer_for_content(:recent_follows, :coding) == :background
    end

    test "maps variety-specific content to correct layers" do
      assert LayerCoordination.determine_layer_for_content(:raid_alert, :variety) == :foreground
      assert LayerCoordination.determine_layer_for_content(:host_alert, :variety) == :foreground
      assert LayerCoordination.determine_layer_for_content(:follow_celebration, :variety) == :midground
      assert LayerCoordination.determine_layer_for_content(:stream_goals, :variety) == :background
      assert LayerCoordination.determine_layer_for_content(:daily_stats, :variety) == :background
    end

    test "maps coding-specific content to correct layers" do
      assert LayerCoordination.determine_layer_for_content(:build_failure, :coding) == :foreground
      assert LayerCoordination.determine_layer_for_content(:deployment_alert, :coding) == :foreground
      assert LayerCoordination.determine_layer_for_content(:commit_celebration, :coding) == :midground
      assert LayerCoordination.determine_layer_for_content(:pr_merged, :coding) == :midground
      assert LayerCoordination.determine_layer_for_content(:commit_stats, :coding) == :background
      assert LayerCoordination.determine_layer_for_content(:build_status, :coding) == :background
    end

    test "unknown content types default to background layer" do
      assert LayerCoordination.determine_layer_for_content(:unknown_content, :ironmon) == :background
      assert LayerCoordination.determine_layer_for_content(:new_feature, :variety) == :background
      assert LayerCoordination.determine_layer_for_content(:custom_type, :coding) == :background
    end

    test "unknown show contexts use default mapping" do
      assert LayerCoordination.determine_layer_for_content(:alert, :unknown_show) == :foreground
      assert LayerCoordination.determine_layer_for_content(:sub_train, :unknown_show) == :midground
      assert LayerCoordination.determine_layer_for_content(:emote_stats, :unknown_show) == :background
    end
  end

  describe "resolve_layer_conflicts/1" do
    test "higher priority content wins layer conflicts" do
      content_list = [
        %{type: :emote_stats, priority: 10, data: %{}, layer: :background},
        %{type: :alert, priority: 100, data: %{message: "Breaking"}, layer: :background}
      ]

      resolved = LayerCoordination.resolve_layer_conflicts(content_list)

      assert length(resolved) == 1
      assert List.first(resolved).type == :alert
      assert List.first(resolved).priority == 100
    end

    test "FIFO resolution for same priority content" do
      content_list = [
        %{
          type: :alert,
          priority: 100,
          data: %{message: "First"},
          layer: :foreground,
          started_at: "2024-01-01T00:00:01Z"
        },
        %{
          type: :death_alert,
          priority: 100,
          data: %{message: "Second"},
          layer: :foreground,
          started_at: "2024-01-01T00:00:02Z"
        }
      ]

      resolved = LayerCoordination.resolve_layer_conflicts(content_list)

      assert length(resolved) == 1
      assert List.first(resolved).type == :alert
      assert List.first(resolved).data.message == "First"
    end

    test "multiple layers with different content types" do
      content_list = [
        %{type: :alert, priority: 100, data: %{}, layer: :foreground},
        %{type: :sub_train, priority: 50, data: %{}, layer: :midground},
        %{type: :emote_stats, priority: 10, data: %{}, layer: :background}
      ]

      resolved = LayerCoordination.resolve_layer_conflicts(content_list)

      assert length(resolved) == 3

      foreground = Enum.find(resolved, &(&1.layer == :foreground))
      midground = Enum.find(resolved, &(&1.layer == :midground))
      background = Enum.find(resolved, &(&1.layer == :background))

      assert foreground.type == :alert
      assert midground.type == :sub_train
      assert background.type == :emote_stats
    end

    test "handles empty content list gracefully" do
      resolved = LayerCoordination.resolve_layer_conflicts([])
      assert resolved == []
    end

    test "handles content without layer assignment" do
      content_list = [
        %{type: :alert, priority: 100, data: %{}}
      ]

      resolved = LayerCoordination.resolve_layer_conflicts(content_list)
      assert resolved == []
    end
  end

  describe "assign_content_to_layers/2" do
    test "assigns single piece of content to correct layer" do
      content_list = [
        %{type: :alert, priority: 100, data: %{message: "Test alert"}}
      ]

      assignments = LayerCoordination.assign_content_to_layers(content_list, :ironmon)

      assert assignments[:foreground].type == :alert
      assert assignments[:foreground].data.message == "Test alert"
      assert assignments[:midground] == nil
      assert assignments[:background] == nil
    end

    test "assigns multiple content types to different layers" do
      content_list = [
        %{type: :alert, priority: 100, data: %{message: "Alert"}},
        %{type: :sub_train, priority: 50, data: %{count: 3}},
        %{type: :emote_stats, priority: 10, data: %{top_emote: "Kappa"}}
      ]

      assignments = LayerCoordination.assign_content_to_layers(content_list, :ironmon)

      assert assignments[:foreground].type == :alert
      assert assignments[:midground].type == :sub_train
      assert assignments[:background].type == :emote_stats
    end

    test "resolves priority conflicts within same layer" do
      content_list = [
        %{type: :emote_stats, priority: 10, data: %{stats: "low"}},
        %{type: :alert, priority: 100, data: %{message: "high"}}
      ]

      # Both would normally go to different layers, but let's verify normal behavior
      # The alert should win due to higher priority, but in normal ironmon context they go to different layers
      assignments_ironmon = LayerCoordination.assign_content_to_layers(content_list, :ironmon)

      assert assignments_ironmon[:foreground].type == :alert
      assert assignments_ironmon[:background].type == :emote_stats
    end

    test "handles empty content list" do
      assignments = LayerCoordination.assign_content_to_layers([], :ironmon)

      assert assignments[:foreground] == nil
      assert assignments[:midground] == nil
      assert assignments[:background] == nil
    end

    test "show context affects layer assignments" do
      content_list = [
        %{type: :build_failure, priority: 100, data: %{error: "Compile error"}}
      ]

      # build_failure should be foreground in coding context
      coding_assignments = LayerCoordination.assign_content_to_layers(content_list, :coding)
      assert coding_assignments[:foreground].type == :build_failure

      # but should fall back to background in other contexts
      ironmon_assignments = LayerCoordination.assign_content_to_layers(content_list, :ironmon)
      assert ironmon_assignments[:foreground] == nil
      assert ironmon_assignments[:background].type == :build_failure
    end

    test "includes original content properties in assignments" do
      content_list = [
        %{
          type: :alert,
          priority: 100,
          data: %{message: "Test"},
          id: "alert-123",
          started_at: "2024-01-01T00:00:00Z",
          duration: 10_000
        }
      ]

      assignments = LayerCoordination.assign_content_to_layers(content_list, :ironmon)

      alert = assignments[:foreground]
      assert alert.id == "alert-123"
      assert alert.started_at == "2024-01-01T00:00:00Z"
      assert alert.duration == 10_000
      assert alert.priority == 100
      assert alert.data.message == "Test"
    end
  end

  describe "get_layer_mapping_config/1" do
    test "returns ironmon layer mappings" do
      config = LayerCoordination.get_layer_mapping_config(:ironmon)

      assert config[:death_alert] == :foreground
      assert config[:elite_four_alert] == :foreground
      assert config[:shiny_encounter] == :foreground
      assert config[:alert] == :foreground

      assert config[:level_up] == :midground
      assert config[:gym_badge] == :midground
      assert config[:sub_train] == :midground
      assert config[:cheer_celebration] == :midground

      assert config[:ironmon_run_stats] == :background
      assert config[:ironmon_deaths] == :background
      assert config[:recent_follows] == :background
      assert config[:emote_stats] == :background
    end

    test "returns variety layer mappings" do
      config = LayerCoordination.get_layer_mapping_config(:variety)

      assert config[:raid_alert] == :foreground
      assert config[:host_alert] == :foreground
      assert config[:alert] == :foreground

      assert config[:sub_train] == :midground
      assert config[:cheer_celebration] == :midground
      assert config[:follow_celebration] == :midground

      assert config[:emote_stats] == :background
      assert config[:recent_follows] == :background
      assert config[:stream_goals] == :background
      assert config[:daily_stats] == :background
    end

    test "returns coding layer mappings" do
      config = LayerCoordination.get_layer_mapping_config(:coding)

      assert config[:build_failure] == :foreground
      assert config[:deployment_alert] == :foreground
      assert config[:alert] == :foreground

      assert config[:commit_celebration] == :midground
      assert config[:pr_merged] == :midground
      assert config[:sub_train] == :midground

      assert config[:commit_stats] == :background
      assert config[:build_status] == :background
      assert config[:recent_follows] == :background
      assert config[:emote_stats] == :background
    end

    test "returns default mappings for unknown show" do
      config = LayerCoordination.get_layer_mapping_config(:unknown_show)

      assert config[:alert] == :foreground
      assert config[:sub_train] == :midground
      assert config[:emote_stats] == :background
      assert config[:recent_follows] == :background
      assert config[:daily_stats] == :background
    end
  end
end

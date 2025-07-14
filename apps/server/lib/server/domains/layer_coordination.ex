defmodule Server.Domains.LayerCoordination do
  @moduledoc """
  Pure functional core for layer coordination logic.

  Contains no side effects - all functions are pure and deterministic.
  Maps content types to visual layer priorities based on show context.

  Business rules:
  - Content types are mapped to layer priorities (foreground/midground/background)
  - Show context affects layer assignments (ironmon/variety/coding)
  - Higher priority content wins layer conflicts
  - FIFO resolution for same priority content within layers
  """

  # Layer priority mapping configurations for each show type
  @ironmon_layer_mappings %{
    # Foreground - Critical interrupts
    death_alert: :foreground,
    elite_four_alert: :foreground,
    shiny_encounter: :foreground,
    alert: :foreground,

    # Midground - Celebrations and notifications
    level_up: :midground,
    gym_badge: :midground,
    sub_train: :midground,
    cheer_celebration: :midground,

    # Background - Stats and ambient info
    ironmon_run_stats: :background,
    ironmon_deaths: :background,
    recent_follows: :background,
    emote_stats: :background
  }

  @variety_layer_mappings %{
    # Foreground - Breaking alerts
    raid_alert: :foreground,
    host_alert: :foreground,
    alert: :foreground,

    # Midground - Community interactions
    sub_train: :midground,
    cheer_celebration: :midground,
    follow_celebration: :midground,

    # Background - Community stats
    emote_stats: :background,
    recent_follows: :background,
    stream_goals: :background,
    daily_stats: :background
  }

  @coding_layer_mappings %{
    # Foreground - Critical development alerts
    build_failure: :foreground,
    deployment_alert: :foreground,
    alert: :foreground,

    # Midground - Development celebrations
    commit_celebration: :midground,
    pr_merged: :midground,
    sub_train: :midground,
    cheer_celebration: :midground,

    # Background - Development stats
    commit_stats: :background,
    build_status: :background,
    recent_follows: :background,
    emote_stats: :background
  }

  @default_layer_mappings %{
    alert: :foreground,
    sub_train: :midground,
    emote_stats: :background,
    recent_follows: :background,
    daily_stats: :background
  }

  @doc """
  Returns the layer mapping configuration for a specific show context.
  """
  def get_layer_mapping_config(show_context) do
    case show_context do
      :ironmon -> @ironmon_layer_mappings
      :variety -> @variety_layer_mappings
      :coding -> @coding_layer_mappings
      _ -> @default_layer_mappings
    end
  end

  @doc """
  Determines which layer a content type should be displayed on for a given show context.

  Returns :foreground, :midground, or :background.
  Unknown content types default to :background.
  """
  def determine_layer_for_content(content_type, show_context) do
    mapping = get_layer_mapping_config(show_context)
    Map.get(mapping, content_type, :background)
  end

  @doc """
  Resolves conflicts when multiple content items are assigned to the same layer.

  Resolution rules:
  1. Higher priority content wins
  2. FIFO for same priority (earliest started_at wins)
  3. Only keeps one item per layer
  """
  def resolve_layer_conflicts(content_list) do
    content_list
    |> Enum.filter(&Map.has_key?(&1, :layer))
    |> Enum.group_by(& &1.layer)
    |> Enum.map(fn {_layer, items} -> resolve_single_layer_conflict(items) end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Assigns content items to their appropriate layers based on show context.

  Returns a map with :foreground, :midground, and :background keys.
  Each key contains either the assigned content item or nil.
  """
  def assign_content_to_layers(content_list, show_context) do
    # Add layer assignments to each content item
    content_with_layers =
      content_list
      |> Enum.map(fn content ->
        layer = determine_layer_for_content(content.type, show_context)
        Map.put(content, :layer, layer)
      end)

    # Resolve conflicts and build final assignments
    resolved_content = resolve_layer_conflicts(content_with_layers)

    # Build the layer assignments map
    %{
      foreground: find_content_for_layer(resolved_content, :foreground),
      midground: find_content_for_layer(resolved_content, :midground),
      background: find_content_for_layer(resolved_content, :background)
    }
  end

  # Private helper functions

  defp resolve_single_layer_conflict([]), do: nil
  defp resolve_single_layer_conflict([single_item]), do: single_item

  defp resolve_single_layer_conflict(items) do
    items
    |> Enum.sort_by(fn item ->
      {-item.priority, Map.get(item, :started_at, "1970-01-01T00:00:00Z")}
    end)
    |> List.first()
  end

  defp find_content_for_layer(content_list, target_layer) do
    Enum.find(content_list, &(&1.layer == target_layer))
  end
end

defmodule Server.LayerMapping do
  @moduledoc """
  Central layer mapping configuration for stream events.
  Maps event types to animation layers based on current show context.

  This module serves as the single source of truth for layer assignments,
  eliminating duplication between frontend applications.
  """

  @layer_mappings %{
    "ironmon" => %{
      # Foreground - Critical interrupts
      "death_alert" => "foreground",
      "elite_four_alert" => "foreground",
      "shiny_encounter" => "foreground",
      "alert" => "foreground",

      # Midground - Celebrations and notifications
      "level_up" => "midground",
      "gym_badge" => "midground",
      "sub_train" => "midground",
      "cheer_celebration" => "midground",

      # Background - Stats and ambient info
      "ironmon_run_stats" => "background",
      "ironmon_deaths" => "background",
      "recent_follows" => "background",
      "emote_stats" => "background"
    },
    "variety" => %{
      # Foreground - Breaking alerts
      "raid_alert" => "foreground",
      "host_alert" => "foreground",
      "alert" => "foreground",

      # Midground - Community interactions
      "sub_train" => "midground",
      "cheer_celebration" => "midground",
      "follow_celebration" => "midground",

      # Background - Community stats
      "emote_stats" => "background",
      "recent_follows" => "background",
      "stream_goals" => "background",
      "daily_stats" => "background"
    },
    "coding" => %{
      # Foreground - Critical development alerts
      "build_failure" => "foreground",
      "deployment_alert" => "foreground",
      "alert" => "foreground",

      # Midground - Development celebrations
      "commit_celebration" => "midground",
      "pr_merged" => "midground",
      "sub_train" => "midground",

      # Background - Development stats
      "commit_stats" => "background",
      "build_status" => "background",
      "recent_follows" => "background",
      "emote_stats" => "background"
    }
  }

  @default_layer_mapping %{
    "alert" => "foreground",
    "sub_train" => "midground",
    "emote_stats" => "background",
    "recent_follows" => "background",
    "daily_stats" => "background"
  }

  @doc """
  Get the layer priority for a given content type and show.

  ## Examples
      iex> Server.LayerMapping.get_layer("death_alert", "ironmon")
      "foreground"
      
      iex> Server.LayerMapping.get_layer("unknown_type", "variety")
      "background"
  """
  @spec get_layer(String.t(), String.t()) :: String.t()
  def get_layer(content_type, show) when is_binary(content_type) and is_binary(show) do
    show_mappings = Map.get(@layer_mappings, show, @default_layer_mapping)
    Map.get(show_mappings, content_type, "background")
  end

  # Handle atom inputs for convenience
  def get_layer(content_type, show) when is_atom(show) do
    get_layer(content_type, Atom.to_string(show))
  end

  @doc """
  Get all mappings for a specific show.

  ## Examples
      iex> Server.LayerMapping.get_mappings_for_show("ironmon")
      %{"death_alert" => "foreground", ...}
  """
  @spec get_mappings_for_show(String.t()) :: map()
  def get_mappings_for_show(show) when is_binary(show) do
    Map.get(@layer_mappings, show, @default_layer_mapping)
  end

  def get_mappings_for_show(show) when is_atom(show) do
    get_mappings_for_show(Atom.to_string(show))
  end

  @doc """
  Get all available show types.

  ## Examples
      iex> Server.LayerMapping.get_show_types()
      ["ironmon", "variety", "coding"]
  """
  @spec get_show_types() :: [String.t()]
  def get_show_types do
    Map.keys(@layer_mappings)
  end

  @doc """
  Get all content types that map to a specific layer for a show.

  ## Examples
      iex> Server.LayerMapping.get_content_types_for_layer("foreground", "ironmon")
      ["death_alert", "elite_four_alert", "shiny_encounter", "alert"]
  """
  @spec get_content_types_for_layer(String.t(), String.t()) :: [String.t()]
  def get_content_types_for_layer(layer, show) when is_binary(layer) and is_binary(show) do
    show_mappings = Map.get(@layer_mappings, show, @default_layer_mapping)

    show_mappings
    |> Enum.filter(fn {_content_type, content_layer} -> content_layer == layer end)
    |> Enum.map(fn {content_type, _} -> content_type end)
    |> Enum.sort()
  end

  @doc """
  Check if a content type should be displayed on a specific layer for a show.

  ## Examples
      iex> Server.LayerMapping.should_display_on_layer?("death_alert", "foreground", "ironmon")
      true
  """
  @spec should_display_on_layer?(String.t(), String.t(), String.t()) :: boolean()
  def should_display_on_layer?(content_type, layer, show) do
    get_layer(content_type, show) == layer
  end
end

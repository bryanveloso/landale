defmodule Server.ContentFallbacks do
  @moduledoc """
  Centralized content fallback system for graceful degradation.

  Provides fallback content when external services fail or are unavailable.
  Ensures overlays never go blank and always have sensible default content.
  """

  @doc """
  Get fallback content for a given content type.

  Returns static fallback data that's safe to display when services fail.
  """
  def get_fallback_content(:recent_follows) do
    %{
      recent_followers: [],
      message: "Follower data temporarily unavailable"
    }
  end

  def get_fallback_content(:daily_stats) do
    %{
      total_messages: 0,
      total_follows: 0,
      started_at: DateTime.utc_now(),
      message: "Stats temporarily unavailable"
    }
  end

  def get_fallback_content(:emote_stats) do
    %{
      top_emotes: [],
      total_emotes: 0,
      message: "Emote stats temporarily unavailable"
    }
  end

  def get_fallback_content(:ironmon_run_stats) do
    %{
      run_number: nil,
      checkpoints_cleared: 0,
      current_checkpoint: "Unknown",
      clear_rate: 0.0,
      message: "IronMON data temporarily unavailable"
    }
  end

  def get_fallback_content(:ironmon_progression) do
    %{
      has_active_run: false,
      current_checkpoint: "Unknown",
      trainer: "Unknown",
      clear_rate_percentage: 0.0,
      last_cleared_seed: nil,
      message: "IronMON progression temporarily unavailable"
    }
  end

  def get_fallback_content(:stream_goals) do
    %{
      follower_goal: %{current: 0, target: 0},
      sub_goal: %{current: 0, target: 0},
      message: "Goal tracking temporarily unavailable"
    }
  end

  def get_fallback_content(:sub_train) do
    %{
      subscribers: [],
      total_subs: 0,
      train_active: false,
      message: "Sub train data temporarily unavailable"
    }
  end

  def get_fallback_content(:alert) do
    %{
      type: "system",
      message: "Alert system temporarily unavailable",
      priority: 1
    }
  end

  # Generic fallback for unknown content types
  def get_fallback_content(content_type) do
    %{
      message: "Content temporarily unavailable",
      type: content_type,
      fallback: true
    }
  end

  @doc """
  Get fallback layer state when the entire system is unavailable.
  """
  def get_fallback_layer_state do
    %{
      current_show: :variety,
      current: nil,
      base: nil,
      priority_level: :ticker,
      alerts: [],
      ticker: [],
      metadata: %{
        last_updated: DateTime.utc_now(),
        state_version: 0,
        fallback_mode: true
      }
    }
  end

  @doc """
  Get fallback queue state when queue system is unavailable.
  """
  def get_fallback_queue_state do
    %{
      queue: [],
      current: nil,
      metrics: %{
        total_items: 0,
        active_items: 0,
        pending_items: 0,
        average_wait_time: 0,
        last_processed: nil
      },
      is_processing: false,
      fallback_mode: true
    }
  end

  @doc """
  Check if content is in fallback mode.
  """
  def fallback_mode?(content) when is_map(content) do
    Map.get(content, :fallback_mode, false) or
      Map.get(content, :fallback, false) or
      Map.has_key?(content, :message)
  end

  def fallback_mode?(_), do: false
end

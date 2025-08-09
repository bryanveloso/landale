defmodule Server.StreamProducer.TickerRotation do
  @moduledoc """
  Manages ticker content rotation for StreamProducer.

  Handles cycling through different content types based on the current
  show context (IronMON, variety, coding, etc.) with configurable
  rotation intervals.
  """

  require Logger

  @type content_item :: %{
          type: atom(),
          data: map(),
          weight: integer()
        }

  @type t :: %{
          items: [content_item()],
          current_index: integer(),
          last_rotation: DateTime.t() | nil
        }

  @doc """
  Creates a new ticker rotation state.
  """
  @spec new() :: t()
  def new do
    %{
      items: [],
      current_index: 0,
      last_rotation: nil
    }
  end

  @doc """
  Updates the rotation items based on show context.
  """
  @spec update_items(t(), [content_item()]) :: t()
  def update_items(state, items) do
    # Expand items based on weight
    expanded_items =
      Enum.flat_map(items, fn item ->
        List.duplicate(item, item[:weight] || 1)
      end)

    %{state | items: expanded_items, current_index: 0}
  end

  @doc """
  Gets the next item in rotation.
  """
  @spec next(t()) :: {content_item() | nil, t()}
  def next(state) do
    case state.items do
      [] ->
        {nil, state}

      items ->
        current_item = Enum.at(items, state.current_index)
        new_index = rem(state.current_index + 1, length(items))

        new_state = %{
          state
          | current_index: new_index,
            last_rotation: DateTime.utc_now()
        }

        {current_item, new_state}
    end
  end

  @doc """
  Gets the current item without advancing.
  """
  @spec current(t()) :: content_item() | nil
  def current(state) do
    case state.items do
      [] -> nil
      items -> Enum.at(items, state.current_index)
    end
  end

  @doc """
  Builds ticker content for a specific show context.
  """
  @spec build_content_for_show(atom(), map()) :: [content_item()]
  def build_content_for_show(show, metadata \\ %{}) do
    case show do
      :ironmon ->
        build_ironmon_content(metadata)

      :variety ->
        build_variety_content(metadata)

      :coding ->
        build_coding_content(metadata)

      _ ->
        build_default_content(metadata)
    end
  end

  # Private functions

  defp build_ironmon_content(metadata) do
    base_content = [
      %{type: :seed_progress, data: %{}, weight: 3},
      %{type: :checkpoint_stats, data: %{}, weight: 2},
      %{type: :recent_clears, data: %{}, weight: 1}
    ]

    # Add stream goals if active
    if metadata[:has_goals] do
      base_content ++ [%{type: :stream_goals, data: %{}, weight: 2}]
    else
      base_content
    end
  end

  defp build_variety_content(metadata) do
    base_content = [
      %{type: :recent_followers, data: %{}, weight: 2},
      %{type: :stream_stats, data: %{}, weight: 2},
      %{type: :now_playing, data: %{}, weight: 1}
    ]

    # Add game-specific content if available
    if metadata[:game_id] do
      base_content ++ [%{type: :game_stats, data: %{game_id: metadata[:game_id]}, weight: 1}]
    else
      base_content
    end
  end

  defp build_coding_content(metadata) do
    [
      %{type: :project_info, data: metadata[:project] || %{}, weight: 2},
      %{type: :git_stats, data: %{}, weight: 1},
      %{type: :recent_commits, data: %{}, weight: 1},
      %{type: :stream_stats, data: %{}, weight: 1}
    ]
  end

  defp build_default_content(_metadata) do
    [
      %{type: :stream_stats, data: %{}, weight: 1},
      %{type: :recent_followers, data: %{}, weight: 1}
    ]
  end
end

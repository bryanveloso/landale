defmodule Server.Domains.StreamState do
  @moduledoc """
  Pure functional core for stream state management.

  Contains no side effects - all functions are pure and deterministic.

  Business rules:
  - Interrupts are prioritized by numeric priority (higher = more important)
  - Within same priority, earlier items win (FIFO)
  - Content expires based on duration + started_at timestamp
  - State version increments on any change for optimistic updates
  """

  # Priority constants
  @priority_alert 100
  @priority_sub_train 50
  @priority_ticker 10

  # Default durations (milliseconds)
  @default_alert_duration 10_000
  @default_sub_train_duration 300_000
  @default_manual_override_duration 30_000

  @doc """
  Determines which content should be actively displayed.

  Algorithm:
  1. Return highest priority interrupt if available
  2. Among same priority, return first item (FIFO)
  3. Fall back to ticker content if no interrupts
  4. Return nil if nothing available
  """
  def determine_active_content(interrupt_stack, ticker_rotation) do
    case get_highest_priority_interrupt(interrupt_stack) do
      nil -> get_ticker_content(ticker_rotation)
      interrupt -> interrupt
    end
  end

  @doc """
  Adds an interrupt to the stack with proper priority and sorting.

  Options:
  - id: Custom ID (generates UUID if not provided)
  - duration: Custom duration in milliseconds
  """
  def add_interrupt(state, interrupt_type, interrupt_data, options \\ []) do
    interrupt = %{
      id: Keyword.get(options, :id, generate_id()),
      type: interrupt_type,
      priority: get_priority_for_type(interrupt_type),
      data: interrupt_data,
      duration: Keyword.get(options, :duration, get_default_duration(interrupt_type)),
      started_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    new_stack =
      [interrupt | state.interrupt_stack]
      |> Enum.sort_by(fn item -> -item.priority end)

    %{
      state
      | interrupt_stack: new_stack,
        version: state.version + 1,
        last_updated: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Updates show context and adjusts ticker rotation accordingly.
  """
  def update_show_context(state, new_show) do
    new_ticker_rotation = get_ticker_rotation_for_show(new_show)

    %{
      state
      | current_show: new_show,
        ticker_rotation: new_ticker_rotation,
        version: state.version + 1,
        last_updated: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Removes expired content from interrupt stack based on current time.
  """
  def expire_content(state, current_time) do
    initial_count = length(state.interrupt_stack)

    new_stack =
      state.interrupt_stack
      |> Enum.filter(&content_active?(&1, current_time))

    new_count = length(new_stack)

    if new_count < initial_count do
      # Something was removed, increment version
      %{
        state
        | interrupt_stack: new_stack,
          version: state.version + 1,
          last_updated: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    else
      # Nothing changed
      state
    end
  end

  @doc """
  Removes interrupt by ID from the stack.
  """
  def remove_interrupt(state, interrupt_id) do
    initial_count = length(state.interrupt_stack)

    new_stack =
      state.interrupt_stack
      |> Enum.reject(&(&1.id == interrupt_id))

    new_count = length(new_stack)

    if new_count < initial_count do
      # Something was removed, increment version
      %{
        state
        | interrupt_stack: new_stack,
          version: state.version + 1,
          last_updated: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    else
      # Nothing found/changed
      state
    end
  end

  # Private helper functions

  defp get_highest_priority_interrupt([]), do: nil

  defp get_highest_priority_interrupt(interrupt_stack) do
    # Sort by priority descending, then by original order (FIFO within same priority)
    interrupt_stack
    |> Enum.with_index()
    |> Enum.sort_by(fn {interrupt, index} -> {-interrupt.priority, index} end)
    |> List.first()
    |> elem(0)
  end

  defp get_ticker_content([]), do: nil

  defp get_ticker_content(ticker_rotation) do
    %{
      type: List.first(ticker_rotation),
      priority: @priority_ticker,
      data: %{},
      started_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp get_priority_for_type(:alert), do: @priority_alert
  defp get_priority_for_type(:sub_train), do: @priority_sub_train
  defp get_priority_for_type(_), do: @priority_ticker

  defp get_default_duration(:alert), do: @default_alert_duration
  defp get_default_duration(:sub_train), do: @default_sub_train_duration
  defp get_default_duration(:manual_override), do: @default_manual_override_duration
  defp get_default_duration(_), do: @default_alert_duration

  defp get_ticker_rotation_for_show(:ironmon) do
    [:ironmon_run_stats, :recent_follows, :emote_stats]
  end

  defp get_ticker_rotation_for_show(:coding) do
    [:build_status, :commit_stats, :recent_follows, :emote_stats]
  end

  defp get_ticker_rotation_for_show(:variety) do
    [:emote_stats, :recent_follows, :stream_goals, :daily_stats]
  end

  defp get_ticker_rotation_for_show(_), do: get_ticker_rotation_for_show(:variety)

  defp content_active?(interrupt, current_time) do
    case DateTime.from_iso8601(interrupt.started_at) do
      {:ok, started_at, _} ->
        expires_at = DateTime.add(started_at, interrupt.duration, :millisecond)
        DateTime.compare(current_time, expires_at) == :lt

      {:error, _} ->
        # If we can't parse the timestamp, assume it's expired for safety
        false
    end
  end

  defp generate_id do
    # Simple UUID-like ID generation
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 12)
  end
end

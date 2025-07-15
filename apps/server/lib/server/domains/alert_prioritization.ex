defmodule Server.Domains.AlertPrioritization do
  @moduledoc """
  Pure functional core for alert prioritization logic.

  Contains no side effects - all functions are pure and deterministic.
  Maps alert types to numeric priorities and manages interrupt stack ordering.

  Business rules:
  - Alert types are mapped to numeric priorities (higher = more important)
  - Within same priority, earlier alerts win (FIFO)
  - Active alert determination follows priority then FIFO order
  - Falls back to ticker alerts when interrupt stack is empty
  """

  # Priority constants
  @priority_alert 100
  @priority_sub_train 50
  @priority_manual_override 50
  @priority_ticker 10

  # Default durations (milliseconds)
  @default_alert_duration 10_000
  @default_sub_train_duration 300_000
  @default_manual_override_duration 30_000
  @default_ticker_duration 15_000

  @doc """
  Returns the numeric priority for a given alert type.

  Priority levels:
  - 100: High priority alerts (breaking news, critical interrupts)
  - 50: Medium priority alerts (celebrations, notifications)
  - 10: Low priority alerts (ticker content, ambient information)

  Unknown alert types default to ticker priority (10).
  """
  def get_priority_for_alert_type(alert_type) do
    case alert_type do
      :alert -> @priority_alert
      :sub_train -> @priority_sub_train
      :manual_override -> @priority_manual_override
      _ -> @priority_ticker
    end
  end

  @doc """
  Determines which alert should be actively displayed.

  Algorithm:
  1. Return highest priority alert from interrupt_stack if available
  2. Among same priority, return first alert (FIFO)
  3. Fall back to ticker alert if no interrupts
  4. Return nil if nothing available
  """
  def determine_active_alert(interrupt_stack, ticker_rotation) do
    case get_highest_priority_alert(interrupt_stack) do
      nil -> get_ticker_alert(ticker_rotation)
      alert -> alert
    end
  end

  @doc """
  Sorts alerts by priority descending, then by timestamp ascending (FIFO).

  Higher priority alerts appear first in the list.
  For same priority alerts, earlier started_at timestamps appear first.
  """
  def sort_alerts_by_priority(alert_list) do
    alert_list
    |> Enum.sort_by(fn alert ->
      started_at = Map.get(alert, :started_at, "1970-01-01T00:00:00Z")
      {-alert.priority, started_at}
    end)
  end

  @doc """
  Creates an alert struct with proper priority and metadata.

  Options:
  - id: Custom ID (generates UUID if not provided)
  - duration: Custom duration in milliseconds
  """
  def create_alert(alert_type, alert_data, options \\ []) do
    %{
      id: Keyword.get(options, :id, generate_id()),
      type: alert_type,
      priority: get_priority_for_alert_type(alert_type),
      data: alert_data,
      duration: Keyword.get(options, :duration, get_default_duration(alert_type)),
      started_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Determines the overall priority level classification for an interrupt stack.

  Returns :alert, :sub_train, or :ticker based on the highest priority
  alert present in the interrupt stack.
  """
  def get_priority_level(interrupt_stack) do
    cond do
      has_alerts_with_priority?(interrupt_stack, @priority_alert) -> :alert
      has_alerts_with_priority?(interrupt_stack, @priority_sub_train) -> :sub_train
      true -> :ticker
    end
  end

  # Private helper functions

  defp get_highest_priority_alert([]), do: nil

  defp get_highest_priority_alert(interrupt_stack) do
    interrupt_stack
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        nil

      alerts ->
        alerts
        |> sort_alerts_by_priority()
        |> List.first()
    end
  end

  defp get_ticker_alert([]), do: nil

  defp get_ticker_alert(ticker_rotation) do
    %{
      type: List.first(ticker_rotation),
      priority: @priority_ticker,
      data: %{},
      started_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp has_alerts_with_priority?(interrupt_stack, target_priority) do
    Enum.any?(interrupt_stack, fn alert ->
      alert && alert.priority >= target_priority
    end)
  end

  defp get_default_duration(:alert), do: @default_alert_duration
  defp get_default_duration(:sub_train), do: @default_sub_train_duration
  defp get_default_duration(:manual_override), do: @default_manual_override_duration
  defp get_default_duration(_), do: @default_ticker_duration

  defp generate_id do
    # Simple UUID-like ID generation
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 12)
  end
end

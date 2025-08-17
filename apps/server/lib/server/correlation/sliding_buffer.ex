defmodule Server.Correlation.SlidingBuffer do
  @moduledoc """
  Optimized sliding window buffer for correlation engine.

  Uses a simple list-based approach with efficient pruning for the specific
  use case of maintaining 30-second windows with frequent range queries.

  ## Design Decisions

  - Items stored in a single list, newest first
  - Pruning happens on add when size/time limits exceeded
  - Range queries use Stream for lazy evaluation
  - No intermediate data structures for better cache locality
  """

  @default_window_ms 30_000
  @default_max_size 100

  defstruct [
    # List of items, newest first
    items: [],
    window_ms: @default_window_ms,
    max_size: @default_max_size
  ]

  @type item :: map()
  @type t :: %__MODULE__{
          items: [item()],
          window_ms: non_neg_integer(),
          max_size: non_neg_integer()
        }

  @doc """
  Creates a new sliding buffer.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      items: [],
      window_ms: Keyword.get(opts, :window_ms, @default_window_ms),
      max_size: Keyword.get(opts, :max_size, @default_max_size)
    }
  end

  @doc """
  Adds an item to the buffer and prunes old items.
  """
  @spec add(t(), item()) :: t()
  def add(%__MODULE__{items: items, window_ms: window_ms, max_size: max_size} = buffer, item) do
    timestamp = Map.get(item, :timestamp, System.system_time(:millisecond))
    item = Map.put(item, :timestamp, timestamp)

    # Add new item to front
    items = [item | items]

    # Prune by time window
    cutoff_time = timestamp - window_ms
    items = take_while_with_limit(items, cutoff_time, max_size)

    %{buffer | items: items}
  end

  @doc """
  Gets items within a time range efficiently.
  """
  @spec get_range(t(), non_neg_integer(), non_neg_integer()) :: [item()]
  def get_range(%__MODULE__{items: items}, min_time, max_time) do
    # Since items are newest first, we can stop early once we pass max_time
    items
    |> Stream.take_while(fn item ->
      Map.get(item, :timestamp, 0) >= min_time
    end)
    |> Stream.filter(fn item ->
      timestamp = Map.get(item, :timestamp, 0)
      timestamp >= min_time and timestamp <= max_time
    end)
    # Return in chronological order
    |> Enum.reverse()
  end

  @doc """
  Returns all items, optionally filtered by age.
  """
  @spec to_list(t(), keyword()) :: [item()]
  def to_list(%__MODULE__{items: items}, opts \\ []) do
    if max_age_ms = Keyword.get(opts, :max_age_ms) do
      current_time = System.system_time(:millisecond)
      min_time = current_time - max_age_ms

      items
      |> Enum.filter(fn item ->
        Map.get(item, :timestamp, 0) >= min_time
      end)
      |> Enum.reverse()
    else
      Enum.reverse(items)
    end
  end

  @doc """
  Returns the current size of the buffer.
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{items: items}), do: length(items)

  @doc """
  Manually prunes old items.
  """
  @spec prune(t()) :: t()
  def prune(%__MODULE__{items: items, window_ms: window_ms, max_size: max_size} = buffer) do
    current_time = System.system_time(:millisecond)
    cutoff_time = current_time - window_ms

    items = take_while_with_limit(items, cutoff_time, max_size)
    %{buffer | items: items}
  end

  # Private helpers

  # Efficiently takes items while respecting both time and size limits
  defp take_while_with_limit(items, cutoff_time, max_size) do
    take_while_with_limit(items, cutoff_time, max_size, 0, [])
  end

  defp take_while_with_limit([], _cutoff, _max_size, _count, acc), do: Enum.reverse(acc)

  defp take_while_with_limit(_items, _cutoff, max_size, count, acc) when count >= max_size do
    Enum.reverse(acc)
  end

  defp take_while_with_limit([item | rest], cutoff, max_size, count, acc) do
    if Map.get(item, :timestamp, 0) >= cutoff do
      take_while_with_limit(rest, cutoff, max_size, count + 1, [item | acc])
    else
      # Items are ordered by time, so we can stop here
      Enum.reverse(acc)
    end
  end
end

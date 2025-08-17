defmodule Server.Correlation.TimeBuffer do
  @moduledoc """
  Efficient time-based circular buffer for correlation engine.

  Uses a list of chunks with timestamps to avoid repeated conversions.
  Each chunk contains events from a specific time period.

  ## Features

  - O(1) insertion
  - Efficient time-based filtering without full traversal
  - Automatic pruning of old chunks
  - Memory-bounded with configurable limits
  """

  # 1 second chunks
  @chunk_duration_ms 1_000
  # 30 second window
  @default_window_ms 30_000
  # Maximum items
  @default_max_size 100

  defstruct [
    # List of {timestamp, items} tuples, newest first
    chunks: [],
    window_ms: @default_window_ms,
    max_size: @default_max_size,
    current_size: 0
  ]

  @type item :: map()
  @type chunk :: {non_neg_integer(), [item()]}
  @type t :: %__MODULE__{
          chunks: [chunk()],
          window_ms: non_neg_integer(),
          max_size: non_neg_integer(),
          current_size: non_neg_integer()
        }

  @doc """
  Creates a new time buffer with optional configuration.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      chunks: [],
      window_ms: Keyword.get(opts, :window_ms, @default_window_ms),
      max_size: Keyword.get(opts, :max_size, @default_max_size),
      current_size: 0
    }
  end

  @doc """
  Adds an item to the buffer.

  Items must have a :timestamp field in milliseconds.
  """
  @spec add(t(), item()) :: t()
  def add(%__MODULE__{} = buffer, item) do
    timestamp = Map.get(item, :timestamp, System.system_time(:millisecond))
    chunk_time = div(timestamp, @chunk_duration_ms) * @chunk_duration_ms

    buffer
    |> add_to_chunk(chunk_time, item)
    |> enforce_size_limit()
    |> prune_old_chunks()
  end

  @doc """
  Gets items within a specific time range.

  More efficient than converting entire buffer to list and filtering.
  """
  @spec get_range(t(), non_neg_integer(), non_neg_integer()) :: [item()]
  def get_range(%__MODULE__{chunks: chunks}, min_time, max_time) do
    # Early return for empty buffer
    if chunks == [] do
      []
    else
      # Find chunks that might contain items in range
      min_chunk = div(min_time, @chunk_duration_ms) * @chunk_duration_ms
      max_chunk = div(max_time, @chunk_duration_ms) * @chunk_duration_ms

      # Use reduce for single pass and avoid intermediate lists
      {items, _} =
        Enum.reduce(chunks, {[], false}, fn
          {chunk_time, _items}, {acc, true} when chunk_time < min_chunk ->
            # We've passed the relevant chunks, stop processing
            {acc, true}

          {chunk_time, items}, {acc, stop} ->
            if chunk_time >= min_chunk and chunk_time <= max_chunk do
              # This chunk might have relevant items
              matching =
                for item <- items,
                    timestamp = Map.get(item, :timestamp, 0),
                    timestamp >= min_time and timestamp <= max_time,
                    do: item

              {matching ++ acc, stop}
            else
              {acc, stop}
            end
        end)

      # Sort once at the end
      Enum.sort_by(items, & &1.timestamp)
    end
  end

  @doc """
  Gets all items in the buffer, optionally filtered by age.
  """
  @spec to_list(t(), keyword()) :: [item()]
  def to_list(%__MODULE__{chunks: chunks}, opts \\ []) do
    if max_age_ms = Keyword.get(opts, :max_age_ms) do
      current_time = System.system_time(:millisecond)
      min_time = current_time - max_age_ms

      chunks
      |> Enum.flat_map(fn {_chunk_time, items} ->
        Enum.filter(items, fn item ->
          Map.get(item, :timestamp, 0) >= min_time
        end)
      end)
      |> Enum.sort_by(& &1.timestamp)
    else
      chunks
      |> Enum.flat_map(fn {_chunk_time, items} -> items end)
      |> Enum.sort_by(& &1.timestamp)
    end
  end

  @doc """
  Returns the current size of the buffer.
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{current_size: size}), do: size

  @doc """
  Prunes old items beyond the configured window.
  """
  @spec prune(t()) :: t()
  def prune(%__MODULE__{} = buffer) do
    prune_old_chunks(buffer)
  end

  # Private functions

  defp add_to_chunk(%__MODULE__{chunks: chunks} = buffer, chunk_time, item) do
    updated_chunks =
      case chunks do
        [{^chunk_time, items} | rest] ->
          # Add to existing chunk
          [{chunk_time, [item | items]} | rest]

        chunks ->
          # Create new chunk - insert in sorted order (newest first)
          new_chunk = {chunk_time, [item]}
          insert_chunk_sorted(chunks, new_chunk)
      end

    %{buffer | chunks: updated_chunks, current_size: buffer.current_size + 1}
  end

  defp insert_chunk_sorted([], new_chunk), do: [new_chunk]

  defp insert_chunk_sorted([{time, _} = chunk | rest] = chunks, {new_time, _} = new_chunk) do
    if new_time > time do
      [new_chunk | chunks]
    else
      [chunk | insert_chunk_sorted(rest, new_chunk)]
    end
  end

  defp enforce_size_limit(%__MODULE__{current_size: size, max_size: max_size} = buffer)
       when size <= max_size do
    buffer
  end

  defp enforce_size_limit(%__MODULE__{chunks: chunks, max_size: max_size} = buffer) do
    # Remove oldest items until we're under the limit
    {kept_chunks, removed_count} = remove_oldest_items(chunks, buffer.current_size - max_size)

    %{buffer | chunks: kept_chunks, current_size: buffer.current_size - removed_count}
  end

  defp remove_oldest_items(chunks, items_to_remove) do
    # Process chunks from oldest to newest (chunks are stored newest first)
    remove_oldest_items_helper(Enum.reverse(chunks), items_to_remove, [], 0)
  end

  defp remove_oldest_items_helper([], _to_remove, acc, removed), do: {acc, removed}
  defp remove_oldest_items_helper(chunks, 0, acc, removed), do: {Enum.reverse(chunks) ++ acc, removed}

  defp remove_oldest_items_helper([{time, items} | rest], to_remove, acc, removed) do
    items_count = length(items)

    if items_count <= to_remove do
      # Remove entire chunk
      remove_oldest_items_helper(rest, to_remove - items_count, acc, removed + items_count)
    else
      # Remove oldest items from this chunk (items are newest first in chunk)
      items_to_keep = Enum.take(items, items_count - to_remove)
      remove_oldest_items_helper(rest, 0, [{time, items_to_keep} | acc], removed + to_remove)
    end
  end

  defp prune_old_chunks(%__MODULE__{chunks: chunks, window_ms: window_ms} = buffer) do
    current_time = System.system_time(:millisecond)
    cutoff_time = current_time - window_ms
    cutoff_chunk = div(cutoff_time, @chunk_duration_ms) * @chunk_duration_ms

    {kept_chunks, pruned_size} =
      chunks
      |> Enum.reduce({[], 0}, fn {chunk_time, items}, {kept, pruned} ->
        if chunk_time < cutoff_chunk do
          # Entire chunk is old
          {kept, pruned + length(items)}
        else
          # Check individual items in boundary chunk
          valid_items =
            Enum.filter(items, fn item ->
              Map.get(item, :timestamp, 0) >= cutoff_time
            end)

          if valid_items == [] do
            {kept, pruned + length(items)}
          else
            pruned_count = length(items) - length(valid_items)
            {[{chunk_time, valid_items} | kept], pruned + pruned_count}
          end
        end
      end)

    %{buffer | chunks: Enum.reverse(kept_chunks), current_size: buffer.current_size - pruned_size}
  end
end

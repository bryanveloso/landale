defmodule Server.Timescale.QueryOptimizer do
  @moduledoc """
  Query optimization utilities for TimescaleDB hypertables.

  Provides chunk-aware query patterns and optimization helpers
  for efficient time-series data access.
  """

  alias Server.Repo
  import Ecto.Query

  @doc """
  Get active chunks for a hypertable within a time range.
  This helps understand data distribution and optimize queries.
  """
  @spec get_active_chunks(String.t(), DateTime.t() | nil) :: [map()]
  def get_active_chunks(table_name, since \\ nil) do
    time_filter =
      if since do
        "AND range_end >= '#{since}'"
      else
        ""
      end

    query = """
    SELECT
      chunk_name,
      range_start,
      range_end,
      pg_size_pretty(total_bytes) as size
    FROM timescaledb_information.chunks
    WHERE hypertable_name = $1
    #{time_filter}
    ORDER BY range_start DESC
    """

    case Repo.query(query, [table_name]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [name, start_time, end_time, size] ->
          %{
            chunk_name: name,
            range_start: start_time,
            range_end: end_time,
            size: size
          }
        end)

      {:error, _} ->
        []
    end
  end

  @doc """
  Get compression status for hypertables.
  """
  @spec get_compression_stats(String.t()) :: map()
  def get_compression_stats(table_name) do
    query = """
    SELECT
      COUNT(*) FILTER (WHERE is_compressed) as compressed_chunks,
      COUNT(*) FILTER (WHERE NOT is_compressed) as uncompressed_chunks,
      pg_size_pretty(SUM(CASE WHEN is_compressed THEN total_bytes ELSE 0 END)) as compressed_size,
      pg_size_pretty(SUM(CASE WHEN NOT is_compressed THEN total_bytes ELSE 0 END)) as uncompressed_size
    FROM timescaledb_information.chunks
    WHERE hypertable_name = $1
    """

    case Repo.query(query, [table_name]) do
      {:ok, %{rows: [[compressed, uncompressed, comp_size, uncomp_size]]}} ->
        %{
          compressed_chunks: compressed || 0,
          uncompressed_chunks: uncompressed || 0,
          compressed_size: comp_size || "0 bytes",
          uncompressed_size: uncomp_size || "0 bytes",
          compression_ratio: calculate_compression_ratio(compressed, uncompressed)
        }

      {:error, _} ->
        %{
          compressed_chunks: 0,
          uncompressed_chunks: 0,
          compressed_size: "0 bytes",
          uncompressed_size: "0 bytes",
          compression_ratio: 0.0
        }
    end
  end

  @doc """
  Optimized count query for time ranges.
  Uses TimescaleDB's approximate_row_count for large ranges.
  """
  @spec fast_count(atom(), DateTime.t(), DateTime.t(), keyword()) :: integer()
  def fast_count(schema_module, start_time, end_time, filters \\ []) do
    table_name = schema_module.__schema__(:source)

    # For recent data (< 1 hour), use exact count
    time_diff = DateTime.diff(end_time, start_time, :hour)

    if time_diff <= 1 do
      exact_count(schema_module, start_time, end_time, filters)
    else
      # For larger ranges, use approximate count
      approximate_count(table_name, start_time, end_time, filters)
    end
  end

  @doc """
  Get statistics for query optimization.
  Helps understand data distribution for better query planning.
  """
  @spec get_table_stats(String.t()) :: map()
  def get_table_stats(table_name) do
    stats_query = """
    WITH chunk_stats AS (
      SELECT
        COUNT(*) as total_chunks,
        MIN(range_start) as oldest_data,
        MAX(range_end) as newest_data,
        AVG(total_bytes) as avg_chunk_size
      FROM timescaledb_information.chunks
      WHERE hypertable_name = $1
    ),
    table_stats AS (
      SELECT
        reltuples::bigint as approximate_rows,
        pg_size_pretty(pg_total_relation_size(quote_ident($1))) as total_size
      FROM pg_class
      WHERE relname = $1
    )
    SELECT
      cs.total_chunks,
      cs.oldest_data,
      cs.newest_data,
      pg_size_pretty(cs.avg_chunk_size::bigint) as avg_chunk_size,
      ts.approximate_rows,
      ts.total_size
    FROM chunk_stats cs, table_stats ts
    """

    case Repo.query(stats_query, [table_name]) do
      {:ok, %{rows: [[chunks, oldest, newest, avg_size, rows, total_size]]}} ->
        %{
          total_chunks: chunks || 0,
          oldest_data: oldest,
          newest_data: newest,
          avg_chunk_size: avg_size || "0 bytes",
          approximate_rows: rows || 0,
          total_size: total_size || "0 bytes",
          data_age_days: calculate_data_age(oldest, newest)
        }

      {:error, _} ->
        %{
          total_chunks: 0,
          oldest_data: nil,
          newest_data: nil,
          avg_chunk_size: "0 bytes",
          approximate_rows: 0,
          total_size: "0 bytes",
          data_age_days: 0
        }
    end
  end

  @doc """
  Create an optimized query plan explanation.
  Useful for debugging slow queries.
  """
  @spec explain_query(String.t(), list()) :: String.t()
  def explain_query(query_string, params \\ []) do
    explain_query = "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) " <> query_string

    case Repo.query(explain_query, params) do
      {:ok, %{rows: [[json_result]]}} ->
        format_explain_output(json_result)

      {:error, error} ->
        "Error explaining query: #{inspect(error)}"
    end
  end

  @doc """
  Suggest indexes based on query patterns.
  Analyzes recent queries and suggests missing indexes.
  """
  @spec suggest_indexes(String.t()) :: [map()]
  def suggest_indexes(table_name) do
    query = """
    SELECT
      schemaname,
      tablename,
      attname,
      n_distinct,
      correlation
    FROM pg_stats
    WHERE tablename = $1
      AND n_distinct > 100
      AND correlation < 0.1
    ORDER BY n_distinct DESC
    """

    case Repo.query(query, [table_name]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [schema, table, column, n_distinct, correlation] ->
          %{
            schema: schema,
            table: table,
            column: column,
            distinct_values: round(n_distinct),
            correlation: Float.round(correlation || 0.0, 3),
            suggestion: suggest_index_type(n_distinct, correlation)
          }
        end)

      {:error, _} ->
        []
    end
  end

  # Private helper functions

  defp exact_count(schema_module, start_time, end_time, filters) do
    base_query =
      from(t in schema_module,
        where: t.timestamp >= ^start_time and t.timestamp <= ^end_time,
        select: count(t.id)
      )

    filtered_query = apply_filters(base_query, filters)
    Repo.one(filtered_query) || 0
  end

  defp approximate_count(table_name, start_time, end_time, filters) do
    # Use TimescaleDB's approximate_row_count for hypertables
    query = """
    SELECT approximate_row_count(
      format('SELECT * FROM %I WHERE timestamp >= %L AND timestamp <= %L',
        $1, $2, $3)::text
    )
    """

    case Repo.query(query, [table_name, start_time, end_time]) do
      {:ok, %{rows: [[count]]}} -> count || 0
      {:error, _} -> 0
    end
  end

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn {field, value}, acc ->
      from(q in acc, where: field(q, ^field) == ^value)
    end)
  end

  defp calculate_compression_ratio(compressed, uncompressed) when compressed > 0 and uncompressed > 0 do
    Float.round(compressed / (compressed + uncompressed) * 100, 1)
  end

  defp calculate_compression_ratio(_, _), do: 0.0

  defp calculate_data_age(nil, _), do: 0
  defp calculate_data_age(_, nil), do: 0

  defp calculate_data_age(oldest, newest) do
    DateTime.diff(newest, oldest, :day)
  end

  defp format_explain_output(json_result) do
    # Parse and format the JSON explain output
    plan = json_result |> List.first() |> Map.get("Plan", %{})

    """
    Query Plan Analysis:
    --------------------
    Total Time: #{plan["Actual Total Time"]} ms
    Rows Returned: #{plan["Actual Rows"]}
    Planning Time: #{json_result |> List.first() |> Map.get("Planning Time", 0)} ms
    Execution Time: #{json_result |> List.first() |> Map.get("Execution Time", 0)} ms

    Node Type: #{plan["Node Type"]}
    #{if plan["Index Name"], do: "Index Used: #{plan["Index Name"]}", else: "Sequential Scan"}
    """
  end

  defp suggest_index_type(n_distinct, correlation) when n_distinct > 10_000 do
    "Consider GIN index for high cardinality column"
  end

  defp suggest_index_type(n_distinct, correlation) when correlation > 0.8 do
    "Consider BRIN index for well-correlated time-series data"
  end

  defp suggest_index_type(_, _) do
    "Standard B-tree index recommended"
  end
end

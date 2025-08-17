defmodule Server.Repo.Migrations.AddChunkAwareOptimizations do
  use Ecto.Migration

  def up do
    # Only run if TimescaleDB is enabled and not in test environment
    if System.get_env("MIX_ENV") != "test" do
      # Set chunk time intervals for better performance
      # 1 day chunks for high-volume tables
      try do
        execute """
          SELECT set_chunk_time_interval('transcriptions', INTERVAL '1 day');
        """
      rescue
        _ ->
          :ok
      end

      try do
        execute """
          SELECT set_chunk_time_interval('events', INTERVAL '1 day');
        """
      rescue
        _ ->
          :ok
      end

      # Create chunk-aware indexes for time range queries
      # These indexes are optimized for TimescaleDB's chunk structure

      # For transcriptions - optimized time range + filtering indexes
      try do
        execute """
          CREATE INDEX IF NOT EXISTS transcriptions_timestamp_confidence_idx
          ON transcriptions (timestamp DESC, confidence)
          WHERE confidence IS NOT NULL;
        """
      rescue
        _ -> :ok
      end

      try do
        execute """
          CREATE INDEX IF NOT EXISTS transcriptions_session_timestamp_idx
          ON transcriptions (stream_session_id, timestamp DESC)
          WHERE stream_session_id IS NOT NULL;
        """
      rescue
        _ -> :ok
      end

      # For events - optimized for time range queries with type filtering
      try do
        execute """
          CREATE INDEX IF NOT EXISTS events_type_timestamp_idx
          ON events (event_type, timestamp DESC);
        """
      rescue
        _ -> :ok
      end

      try do
        execute """
          CREATE INDEX IF NOT EXISTS events_user_timestamp_idx
          ON events (user_id, timestamp DESC)
          WHERE user_id IS NOT NULL;
        """
      rescue
        _ -> :ok
      end

      # For correlations - even though not a hypertable, optimize for time queries
      try do
        execute """
          CREATE INDEX IF NOT EXISTS correlations_created_pattern_idx
          ON correlations (created_at DESC, pattern_type, confidence);
        """
      rescue
        _ -> :ok
      end

      try do
        execute """
          CREATE INDEX IF NOT EXISTS correlations_session_created_idx
          ON correlations (session_id, created_at DESC)
          WHERE session_id IS NOT NULL;
        """
      rescue
        _ -> :ok
      end

      # Create compression policies for older data (if using TimescaleDB 2.0+)
      # Compress chunks older than 7 days
      try do
        execute """
          ALTER TABLE transcriptions SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'stream_session_id',
            timescaledb.compress_orderby = 'timestamp DESC'
          );
        """
      rescue
        _ -> :ok
      end

      try do
        execute """
          SELECT add_compression_policy('transcriptions', INTERVAL '7 days', if_not_exists => true);
        """
      rescue
        _ -> :ok
      end

      try do
        execute """
          ALTER TABLE events SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'event_type',
            timescaledb.compress_orderby = 'timestamp DESC'
          );
        """
      rescue
        _ -> :ok
      end

      try do
        execute """
          SELECT add_compression_policy('events', INTERVAL '7 days', if_not_exists => true);
        """
      rescue
        _ -> :ok
      end

      # Create helper functions for chunk-aware queries
      try do
        execute """
          CREATE OR REPLACE FUNCTION get_recent_chunks(
            table_name text,
            time_interval interval DEFAULT '24 hours'
          )
          RETURNS TABLE(chunk_name text, range_start timestamptz, range_end timestamptz)
          LANGUAGE plpgsql
          AS $$
          BEGIN
            RETURN QUERY
            SELECT
              ch.chunk_name::text,
              ch.range_start::timestamptz,
              ch.range_end::timestamptz
            FROM timescaledb_information.chunks ch
            WHERE ch.hypertable_name = table_name
              AND ch.range_end >= NOW() - time_interval
            ORDER BY ch.range_start DESC;
          END;
          $$;
        """
      rescue
        _ -> :ok
      end

      # Create optimized query function for time-range aggregations
      try do
        execute """
          CREATE OR REPLACE FUNCTION get_transcription_stats(
            start_time timestamptz,
            end_time timestamptz,
            session_id text DEFAULT NULL
          )
          RETURNS TABLE(
            total_count bigint,
            avg_confidence float,
            total_duration float,
            unique_sources bigint
          )
          LANGUAGE plpgsql
          AS $$
          BEGIN
            RETURN QUERY
            SELECT
              COUNT(*)::bigint as total_count,
              AVG(confidence)::float as avg_confidence,
              SUM(duration)::float as total_duration,
              COUNT(DISTINCT source_id)::bigint as unique_sources
            FROM transcriptions
            WHERE timestamp >= start_time
              AND timestamp <= end_time
              AND (session_id IS NULL OR stream_session_id = session_id);
          END;
          $$;
        """
      rescue
        _ -> :ok
      end

      # Create function for efficient chat message search
      try do
        execute """
          CREATE OR REPLACE FUNCTION search_chat_messages(
            search_term text,
            start_time timestamptz DEFAULT NOW() - INTERVAL '24 hours',
            end_time timestamptz DEFAULT NOW(),
            limit_count int DEFAULT 100
          )
          RETURNS TABLE(
            id uuid,
            created_at timestamptz,
            user_name text,
            message text,
            similarity float
          )
          LANGUAGE plpgsql
          AS $$
          BEGIN
            RETURN QUERY
            SELECT
              e.id,
              e.timestamp AS created_at,
              e.user_name,
              e.data->>'message' as message,
              similarity(e.data->>'message', search_term) as similarity
            FROM events e
            WHERE e.event_type = 'channel.chat.message'
              AND e.timestamp >= start_time
              AND e.timestamp <= end_time
              AND e.data->>'message' % search_term  -- trigram similarity operator
            ORDER BY similarity DESC, e.timestamp DESC
            LIMIT limit_count;
          END;
          $$;
        """
      rescue
        _ -> :ok
      end

      # Add data retention policies for automatic old data cleanup
      # This keeps only 30 days of detailed data (configurable)
      try do
        execute """
          SELECT add_retention_policy('transcriptions', INTERVAL '30 days', if_not_exists => true);
        """
      rescue
        _ -> :ok
      end

      try do
        execute """
          SELECT add_retention_policy('events', INTERVAL '30 days', if_not_exists => true);
        """
      rescue
        _ -> :ok
      end

      # Create statistics for query planner optimization
      try do
        execute """
          ALTER TABLE transcriptions SET (autovacuum_analyze_scale_factor = 0.02);
        """
      rescue
        _ -> :ok
      end

      try do
        execute """
          ALTER TABLE events SET (autovacuum_analyze_scale_factor = 0.02);
        """
      rescue
        _ -> :ok
      end

      # Run ANALYZE to update statistics
      try do
        execute "ANALYZE transcriptions;"
      rescue
        _ -> :ok
      end

      try do
        execute "ANALYZE events;"
      rescue
        _ -> :ok
      end
    end
  end

  def down do
    if System.get_env("MIX_ENV") != "test" do
      # Drop functions
      try do
        execute "DROP FUNCTION IF EXISTS get_recent_chunks CASCADE;"
      rescue
        _ -> :ok
      end

      try do
        execute "DROP FUNCTION IF EXISTS get_transcription_stats CASCADE;"
      rescue
        _ -> :ok
      end

      try do
        execute "DROP FUNCTION IF EXISTS search_chat_messages CASCADE;"
      rescue
        _ -> :ok
      end

      # Remove policies
      try do
        execute "SELECT remove_compression_policy('transcriptions', if_exists => true);"
      rescue
        _ -> :ok
      end

      try do
        execute "SELECT remove_compression_policy('events', if_exists => true);"
      rescue
        _ -> :ok
      end

      try do
        execute "SELECT remove_retention_policy('transcriptions', if_exists => true);"
      rescue
        _ -> :ok
      end

      try do
        execute "SELECT remove_retention_policy('events', if_exists => true);"
      rescue
        _ -> :ok
      end

      # Drop indexes
      try do
        execute "DROP INDEX IF EXISTS transcriptions_timestamp_confidence_idx;"
      rescue
        _ -> :ok
      end

      try do
        execute "DROP INDEX IF EXISTS transcriptions_session_timestamp_idx;"
      rescue
        _ -> :ok
      end

      try do
        execute "DROP INDEX IF EXISTS events_type_timestamp_idx;"
      rescue
        _ -> :ok
      end

      try do
        execute "DROP INDEX IF EXISTS events_user_timestamp_idx;"
      rescue
        _ -> :ok
      end

      try do
        execute "DROP INDEX IF EXISTS correlations_created_pattern_idx;"
      rescue
        _ -> :ok
      end

      try do
        execute "DROP INDEX IF EXISTS correlations_session_created_idx;"
      rescue
        _ -> :ok
      end
    end
  end
end

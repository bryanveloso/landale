defmodule Server.Repo.Migrations.AddTemporalCorrelationFields do
  use Ecto.Migration

  def up do
    # Add temporal analysis fields to existing correlations table
    alter table(:correlations) do
      add :temporal_pattern_type, :string, null: true
      add :temporal_pattern_description, :text, null: true
      add :expected_delay_ms, :integer, null: true
      add :timing_deviation_ms, :integer, null: true
      add :delay_confidence, :float, null: true
    end

    # Create indexes for temporal pattern queries
    create index(:correlations, [:temporal_pattern_type])
    create index(:correlations, [:timing_deviation_ms])
    create index(:correlations, [:delay_confidence])

    # Create temporal delay estimation table for tracking delay history
    create table(:stream_delay_estimates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, :binary_id, null: true
      add :estimated_delay_ms, :integer, null: false
      add :confidence, :float, null: false
      add :correlation_peak, :float, null: false
      add :transcription_buckets, :integer, null: false
      add :chat_buckets, :integer, null: false
      add :algorithm_version, :string, null: false, default: "v1"

      timestamps(type: :utc_datetime_usec)
    end

    # Create hypertable for delay estimates if TimescaleDB is available
    execute_if_timescale("""
    SELECT create_hypertable('stream_delay_estimates', 'inserted_at',
      chunk_time_interval => INTERVAL '1 day',
      if_not_exists => TRUE
    );
    """)

    # Add indexes for delay estimates
    create index(:stream_delay_estimates, [:session_id])
    create index(:stream_delay_estimates, [:inserted_at])
    create index(:stream_delay_estimates, [:confidence])

    # Create temporal pattern statistics table
    create table(:temporal_pattern_stats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, :binary_id, null: true
      add :pattern_type, :string, null: false
      add :temporal_pattern_type, :string, null: false
      add :count, :integer, null: false, default: 1
      add :avg_confidence, :float, null: false
      add :avg_timing_deviation_ms, :integer, null: false
      add :min_timing_deviation_ms, :integer, null: false
      add :max_timing_deviation_ms, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Create hypertable for pattern stats if TimescaleDB is available
    execute_if_timescale("""
    SELECT create_hypertable('temporal_pattern_stats', 'inserted_at',
      chunk_time_interval => INTERVAL '1 day',
      if_not_exists => TRUE
    );
    """)

    # Add indexes for pattern statistics
    create index(:temporal_pattern_stats, [:session_id, :pattern_type])
    create index(:temporal_pattern_stats, [:temporal_pattern_type])
    create index(:temporal_pattern_stats, [:inserted_at])

    create unique_index(:temporal_pattern_stats, [
             :session_id,
             :pattern_type,
             :temporal_pattern_type,
             :inserted_at
           ])

    # Create view for temporal analysis dashboard
    execute("""
    CREATE OR REPLACE VIEW temporal_correlation_summary AS
    SELECT
      session_id,
      pattern_type,
      temporal_pattern_type,
      COUNT(*) as correlation_count,
      AVG(confidence) as avg_confidence,
      AVG(timing_deviation_ms) as avg_timing_deviation,
      AVG(delay_confidence) as avg_delay_confidence,
      MIN(created_at) as first_occurrence,
      MAX(created_at) as last_occurrence
    FROM correlations
    WHERE temporal_pattern_type IS NOT NULL
      AND created_at >= NOW() - INTERVAL '24 hours'
    GROUP BY session_id, pattern_type, temporal_pattern_type
    ORDER BY correlation_count DESC;
    """)

    # Create function for temporal pattern aggregation
    execute("""
    CREATE OR REPLACE FUNCTION aggregate_temporal_patterns(
      session_uuid UUID DEFAULT NULL,
      hours_back INTEGER DEFAULT 1
    )
    RETURNS TABLE(
      pattern_type TEXT,
      temporal_pattern_type TEXT,
      correlation_count BIGINT,
      avg_confidence FLOAT,
      avg_timing_deviation INTEGER,
      timing_stability FLOAT
    )
    LANGUAGE SQL
    AS $$
      SELECT
        c.pattern_type::TEXT,
        c.temporal_pattern_type::TEXT,
        COUNT(*) as correlation_count,
        AVG(c.confidence)::FLOAT as avg_confidence,
        AVG(c.timing_deviation_ms)::INTEGER as avg_timing_deviation,
        (1.0 - STDDEV(c.timing_deviation_ms) / GREATEST(AVG(ABS(c.timing_deviation_ms)), 1.0))::FLOAT as timing_stability
      FROM correlations c
      WHERE c.temporal_pattern_type IS NOT NULL
        AND c.created_at >= NOW() - (hours_back || ' hours')::INTERVAL
        AND (session_uuid IS NULL OR c.session_id = session_uuid)
      GROUP BY c.pattern_type, c.temporal_pattern_type
      HAVING COUNT(*) >= 3  -- Minimum observations for stability calculation
      ORDER BY correlation_count DESC, avg_confidence DESC;
    $$;
    """)
  end

  def down do
    # Drop temporal analysis objects
    execute("DROP FUNCTION IF EXISTS aggregate_temporal_patterns(UUID, INTEGER);")
    execute("DROP VIEW IF EXISTS temporal_correlation_summary;")

    # Drop temporal tables
    drop table(:temporal_pattern_stats)
    drop table(:stream_delay_estimates)

    # Remove temporal fields from correlations
    alter table(:correlations) do
      remove :temporal_pattern_type
      remove :temporal_pattern_description
      remove :expected_delay_ms
      remove :timing_deviation_ms
      remove :delay_confidence
    end
  end

  # Helper function to execute TimescaleDB commands only if extension is available
  defp execute_if_timescale(sql) do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN
        #{sql}
      END IF;
    END
    $$;
    """)
  end
end

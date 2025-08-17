defmodule Server.Repo.Migrations.AddTimescaledbContinuousAggregates do
  use Ecto.Migration

  def up do
    # Only run if TimescaleDB is enabled and not in test environment
    if System.get_env("MIX_ENV") != "test" do
      # Enable TimescaleDB if not already enabled
      execute "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;"

      # Create hourly aggregation for transcriptions
      # This aggregates data every hour for fast analytics queries
      execute """
        CREATE MATERIALIZED VIEW IF NOT EXISTS transcriptions_hourly
        WITH (timescaledb.continuous) AS
        SELECT
          time_bucket('1 hour', timestamp) AS hour,
          COUNT(*) AS count,
          AVG(confidence)::FLOAT AS avg_confidence,
          MIN(confidence)::FLOAT AS min_confidence,
          MAX(confidence)::FLOAT AS max_confidence,
          AVG(duration)::FLOAT AS avg_duration,
          SUM(duration)::FLOAT AS total_duration,
          COUNT(CASE WHEN confidence >= 0.8 THEN 1 END) AS high_confidence_count,
          COUNT(CASE WHEN confidence >= 0.6 AND confidence < 0.8 THEN 1 END) AS medium_confidence_count,
          COUNT(CASE WHEN confidence < 0.6 THEN 1 END) AS low_confidence_count,
          stream_session_id
        FROM transcriptions
        GROUP BY hour, stream_session_id
        WITH NO DATA;
      """

      # Create daily aggregation for transcriptions
      execute """
        CREATE MATERIALIZED VIEW IF NOT EXISTS transcriptions_daily
        WITH (timescaledb.continuous) AS
        SELECT
          time_bucket('1 day', timestamp) AS day,
          COUNT(*) AS count,
          AVG(confidence)::FLOAT AS avg_confidence,
          MIN(confidence)::FLOAT AS min_confidence,
          MAX(confidence)::FLOAT AS max_confidence,
          AVG(duration)::FLOAT AS avg_duration,
          SUM(duration)::FLOAT AS total_duration,
          SUM(LENGTH(text)) AS total_text_length,
          stream_session_id
        FROM transcriptions
        GROUP BY day, stream_session_id
        WITH NO DATA;
      """

      # Create hourly aggregation for events (chat messages included)
      execute """
        CREATE MATERIALIZED VIEW IF NOT EXISTS events_hourly
        WITH (timescaledb.continuous) AS
        SELECT
          time_bucket('1 hour', timestamp) AS hour,
          event_type,
          COUNT(*) AS count,
          COUNT(DISTINCT user_id) AS unique_users
        FROM events
        GROUP BY hour, event_type
        WITH NO DATA;
      """

      # Create daily aggregation for events
      execute """
        CREATE MATERIALIZED VIEW IF NOT EXISTS events_daily
        WITH (timescaledb.continuous) AS
        SELECT
          time_bucket('1 day', timestamp) AS day,
          event_type,
          COUNT(*) AS count,
          COUNT(DISTINCT user_id) AS unique_users
        FROM events
        GROUP BY day, event_type
        WITH NO DATA;
      """

      # Add refresh policies for continuous aggregates
      # These automatically refresh the aggregates as new data arrives

      # Refresh hourly aggregates every 30 minutes with 2 hour lag
      execute """
        SELECT add_continuous_aggregate_policy('transcriptions_hourly',
          start_offset => INTERVAL '3 hours',
          end_offset => INTERVAL '1 hour',
          schedule_interval => INTERVAL '30 minutes',
          if_not_exists => true);
      """

      execute """
        SELECT add_continuous_aggregate_policy('events_hourly',
          start_offset => INTERVAL '3 hours',
          end_offset => INTERVAL '1 hour',
          schedule_interval => INTERVAL '30 minutes',
          if_not_exists => true);
      """

      # Refresh daily aggregates every 2 hours with 1 day lag
      execute """
        SELECT add_continuous_aggregate_policy('transcriptions_daily',
          start_offset => INTERVAL '3 days',
          end_offset => INTERVAL '1 day',
          schedule_interval => INTERVAL '2 hours',
          if_not_exists => true);
      """

      execute """
        SELECT add_continuous_aggregate_policy('events_daily',
          start_offset => INTERVAL '3 days',
          end_offset => INTERVAL '1 day',
          schedule_interval => INTERVAL '2 hours',
          if_not_exists => true);
      """

      # Create indexes on continuous aggregates for fast queries
      execute "CREATE INDEX ON transcriptions_hourly (hour DESC, stream_session_id);"
      execute "CREATE INDEX ON transcriptions_daily (day DESC, stream_session_id);"
      execute "CREATE INDEX ON events_hourly (hour DESC, event_type);"
      execute "CREATE INDEX ON events_daily (day DESC, event_type);"

      # Note: Continuous aggregates will be refreshed automatically by the policies
      # refresh_continuous_aggregate() cannot run inside a transaction block
    end
  end

  def down do
    if System.get_env("MIX_ENV") != "test" do
      # Drop continuous aggregates
      execute "DROP MATERIALIZED VIEW IF EXISTS transcriptions_hourly CASCADE;"
      execute "DROP MATERIALIZED VIEW IF EXISTS transcriptions_daily CASCADE;"
      execute "DROP MATERIALIZED VIEW IF EXISTS events_hourly CASCADE;"
      execute "DROP MATERIALIZED VIEW IF EXISTS events_daily CASCADE;"
    end
  end
end

defmodule Server.Repo.Migrations.CreateTranscriptionTables do
  use Ecto.Migration

  def up do
    # Create transcriptions table with composite primary key for TimescaleDB
    create table(:transcriptions, primary_key: false) do
      add :id, :binary_id, null: false
      add :timestamp, :utc_datetime_usec, null: false
      add :duration, :float, null: false
      add :text, :text, null: false
      add :source_id, :string
      add :stream_session_id, :string
      add :confidence, :float
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    # Create composite primary key (id, timestamp) required by TimescaleDB
    execute "ALTER TABLE transcriptions ADD PRIMARY KEY (id, timestamp);"

    # Create indexes for common queries
    create index(:transcriptions, [:timestamp])
    create index(:transcriptions, [:stream_session_id])
    create index(:transcriptions, [:source_id])

    # Enable TimescaleDB and pg_trgm extensions if available
    try do
      execute "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;"
      execute "SELECT create_hypertable('transcriptions', 'timestamp');"
    rescue
      Postgrex.Error ->
        # TimescaleDB not available, continue without hypertable
        :ok
    end

    try do
      execute "CREATE EXTENSION IF NOT EXISTS pg_trgm;"

      execute "CREATE INDEX transcriptions_text_gin_idx ON transcriptions USING gin (text gin_trgm_ops);"
    rescue
      Postgrex.Error ->
        # pg_trgm not available, continue without text search index
        :ok
    end
  end

  def down do
    drop table(:transcriptions)

    # Extensions will be dropped automatically when table is dropped
    # No need for conditional logic here
  end
end

defmodule Server.Repo.Migrations.CreateTranscriptionTables do
  use Ecto.Migration

  def up do
    # Enable TimescaleDB extension
    execute "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;"

    # Create transcriptions table
    create table(:transcriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :timestamp, :utc_datetime_usec, null: false
      add :duration, :float, null: false
      add :text, :text, null: false
      add :source_id, :string
      add :stream_session_id, :string
      add :confidence, :float
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    # Create hypertable (time-series optimization)
    execute "SELECT create_hypertable('transcriptions', 'timestamp');"

    # Create indexes for common queries
    create index(:transcriptions, [:timestamp])
    create index(:transcriptions, [:stream_session_id])
    create index(:transcriptions, [:source_id])
    create index(:transcriptions, [:text], using: :gin, prefix: :gin_trgm_ops)

    # Enable pg_trgm extension for text search
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
  end

  def down do
    drop table(:transcriptions)
    execute "DROP EXTENSION IF EXISTS timescaledb CASCADE;"
    execute "DROP EXTENSION IF EXISTS pg_trgm;"
  end
end

defmodule Server.Repo.Migrations.CreateContextsTable do
  use Ecto.Migration

  def up do
    # Create contexts table
    create table(:contexts, primary_key: false) do
      add :started, :utc_datetime_usec, null: false
      add :ended, :utc_datetime_usec, null: false
      add :session, :string, null: false
      add :transcript, :text, null: false
      add :duration, :float, null: false
      add :chat, :map
      add :interactions, :map
      add :emotes, :map
      add :patterns, :map
      add :sentiment, :string
      add :topics, {:array, :string}

      timestamps(type: :utc_datetime_usec)
    end

    # Create indexes for common queries
    create index(:contexts, [:started])
    create index(:contexts, [:session])
    create index(:contexts, [:sentiment])
    create index(:contexts, [:topics], using: :gin)

    # Skip TimescaleDB and pg_trgm features in test environment
    # These features are only needed in production
    if System.get_env("MIX_ENV") != "test" do
      # Enable TimescaleDB hypertable if available
      try do
        execute "SELECT create_hypertable('contexts', 'started');"
      rescue
        Postgrex.Error ->
          # TimescaleDB not available, continue without hypertable
          :ok
      end

      # Create GIN index for text search in transcripts if pg_trgm available
      try do
        execute "CREATE INDEX contexts_transcript_gin_idx ON contexts USING gin (transcript gin_trgm_ops);"
      rescue
        Postgrex.Error ->
          # pg_trgm not available, continue without text search index
          :ok
      end
    end
  end

  def down do
    drop table(:contexts)
  end
end

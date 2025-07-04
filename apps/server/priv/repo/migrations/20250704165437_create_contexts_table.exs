defmodule Server.Repo.Migrations.CreateContextsTable do
  use Ecto.Migration

  def up do
    # Create contexts table
    create table(:contexts, primary_key: [name: :id, type: :binary_id]) do
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

    # Only enable TimescaleDB in production
    if Mix.env() == :prod do
      # Create hypertable (time-series optimization)
      execute "SELECT create_hypertable('contexts', 'started');"

      # Create GIN index for text search in transcripts
      create index(:contexts, [:transcript], using: :gin, prefix: :gin_trgm_ops)
    end
  end

  def down do
    drop table(:contexts)
  end
end

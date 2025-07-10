defmodule Server.Repo.Migrations.CreateEventsTable do
  use Ecto.Migration

  def up do
    # Create events table for activity log
    create table(:events, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :timestamp, :utc_datetime_usec, null: false
      add :event_type, :text, null: false
      add :user_id, :text
      add :user_login, :text
      add :user_name, :text
      add :data, :map, null: false
      add :correlation_id, :text

      timestamps(type: :utc_datetime_usec)
    end

    # Create indexes for common queries
    create index(:events, [:timestamp])
    create index(:events, [:event_type])
    create index(:events, [:user_id])
    create index(:events, [:correlation_id])

    # Only enable TimescaleDB and advanced features in production
    if Mix.env() == :prod do
      # Create hypertable (time-series optimization)
      execute "SELECT create_hypertable('events', 'timestamp');"

      # Create GIN index for JSONB data search
      create index(:events, [:data], using: :gin)
    end
  end

  def down do
    drop table(:events)
  end
end

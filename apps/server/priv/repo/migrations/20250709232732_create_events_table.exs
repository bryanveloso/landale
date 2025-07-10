defmodule Server.Repo.Migrations.CreateEventsTable do
  use Ecto.Migration

  def up do
    # Create events table for activity log with composite primary key for TimescaleDB
    create table(:events, primary_key: false) do
      add :id, :binary_id, null: false
      add :timestamp, :utc_datetime_usec, null: false
      add :event_type, :text, null: false
      add :user_id, :text
      add :user_login, :text
      add :user_name, :text
      add :data, :map, null: false
      add :correlation_id, :text

      timestamps(type: :utc_datetime_usec)
    end

    # Create composite primary key (id, timestamp) required by TimescaleDB
    execute "ALTER TABLE events ADD PRIMARY KEY (id, timestamp);"
    
    # Create indexes for common queries
    create index(:events, [:timestamp])
    create index(:events, [:event_type])
    create index(:events, [:user_id])
    create index(:events, [:correlation_id])

    # Enable TimescaleDB hypertable if extension is available
    # This will silently fail if TimescaleDB is not installed (e.g., in development)
    try do
      execute "SELECT create_hypertable('events', 'timestamp');"
    rescue
      Postgrex.Error ->
        # TimescaleDB not available, continue without hypertable
        :ok
    end

    # Create GIN index for JSONB data search
    create index(:events, [:data], using: :gin)
  end

  def down do
    drop table(:events)
  end
end

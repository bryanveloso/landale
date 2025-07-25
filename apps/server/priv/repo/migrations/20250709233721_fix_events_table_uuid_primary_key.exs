defmodule Server.Repo.Migrations.FixEventsTableUuidPrimaryKey do
  use Ecto.Migration

  def up do
    # Drop the existing events table and recreate with UUID primary key
    # This is safe since we haven't deployed yet and have no production data
    drop table(:events)

    # Recreate events table with UUID and composite primary key for TimescaleDB
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

    # Skip TimescaleDB features in test environment
    # These features are only needed in production
    if System.get_env("MIX_ENV") != "test" do
      # Enable TimescaleDB hypertable if extension is available
      try do
        execute "SELECT create_hypertable('events', 'timestamp');"
      rescue
        Postgrex.Error ->
          # TimescaleDB not available, continue without hypertable
          :ok
      end
    end

    # Create GIN index for JSONB data search
    create index(:events, [:data], using: :gin)
  end

  def down do
    # Drop the UUID version and recreate with autoincrement
    drop table(:events)

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

    create index(:events, [:timestamp])
    create index(:events, [:event_type])
    create index(:events, [:user_id])
    create index(:events, [:correlation_id])

    # Skip TimescaleDB features in test environment
    if System.get_env("MIX_ENV") != "test" do
      try do
        execute "SELECT create_hypertable('events', 'timestamp');"
      rescue
        Postgrex.Error ->
          :ok
      end
    end

    create index(:events, [:data], using: :gin)
  end
end

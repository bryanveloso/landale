defmodule Server.Repo.Migrations.CreateUsersTable do
  use Ecto.Migration

  def up do
    # Create users table for user metadata (nicknames, pronouns, notes)
    create table(:users, primary_key: false) do
      add :twitch_id, :text, primary_key: true
      add :login, :text, null: false
      add :display_name, :text
      add :nickname, :text
      add :pronouns, :text
      add :notes, :text

      timestamps(type: :utc_datetime_usec)
    end

    # Create indexes for common queries
    create index(:users, [:display_name])
    create unique_index(:users, [:login])
  end

  def down do
    drop table(:users)
  end
end
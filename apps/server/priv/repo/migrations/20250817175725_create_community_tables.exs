defmodule Server.Repo.Migrations.CreateCommunityTables do
  use Ecto.Migration

  def change do
    # Community members table
    create table(:community_members, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :username, :text, null: false
      add :display_name, :text
      add :first_seen, :utc_datetime_usec, null: false
      add :last_seen, :utc_datetime_usec, null: false
      add :message_count, :integer, default: 0
      add :active, :boolean, default: true
      add :pronunciation_guide, :text
      add :notes, :text
      add :preferred_name, :text

      timestamps(type: :utc_datetime_usec)
    end

    # Pronunciation overrides table
    create table(:pronunciation_overrides, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :username, :text, null: false
      add :phonetic, :text, null: false
      add :confidence, :float, default: 1.0
      add :created_by, :text
      add :active, :boolean, default: true

      timestamps(type: :utc_datetime_usec)
    end

    # Community vocabulary table (inside jokes, memes, etc.)
    create table(:community_vocabulary, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :phrase, :text, null: false
      # "meme", "inside_joke", "catchphrase", "emote_phrase"
      add :category, :text, null: false
      add :definition, :text
      add :context, :text
      add :first_used, :utc_datetime_usec
      add :usage_count, :integer, default: 1
      add :tags, {:array, :string}, default: []
      add :active, :boolean, default: true

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes for performance
    create unique_index(:community_members, [:username])
    create index(:community_members, [:active])
    create index(:community_members, [:last_seen])

    create unique_index(:pronunciation_overrides, [:username])
    create index(:pronunciation_overrides, [:active])

    create unique_index(:username_aliases, [:canonical_username, :alias])
    create index(:username_aliases, [:canonical_username])
    create index(:username_aliases, [:alias])
    create index(:username_aliases, [:active])

    create unique_index(:community_vocabulary, [:phrase])
    create index(:community_vocabulary, [:category])
    create index(:community_vocabulary, [:active])
    create index(:community_vocabulary, [:first_used])

    # GIN index for tag search on community vocabulary
    create index(:community_vocabulary, [:tags], using: :gin)
  end
end

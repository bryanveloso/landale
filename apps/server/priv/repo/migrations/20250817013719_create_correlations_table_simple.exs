defmodule Server.Repo.Migrations.CreateCorrelationsTableSimple do
  use Ecto.Migration

  def up do
    # Create correlations table
    create table(:correlations, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :transcription_id, :uuid, null: false
      add :transcription_text, :text, null: false
      add :chat_message_id, :string, null: false
      add :chat_user, :string, null: false
      add :chat_text, :text, null: false
      add :pattern_type, :string, null: false
      add :confidence, :float, null: false
      add :time_offset_ms, :integer, null: false
      add :detected_keywords, {:array, :string}, default: []
      # To group correlations by stream session
      add :session_id, :uuid
      add :created_at, :timestamptz, null: false, default: fragment("NOW()")
    end

    # Indexes for efficient querying
    create index(:correlations, [:created_at, :confidence],
             comment: "Time-based queries with confidence filtering"
           )

    create index(:correlations, [:pattern_type, :confidence], comment: "Pattern analysis queries")

    create index(:correlations, [:session_id, :created_at],
             comment: "Session-specific correlation queries"
           )

    create index(:correlations, [:transcription_id],
             comment: "Find correlations for specific transcriptions"
           )

    # Create hot phrases aggregation table
    create table(:hot_phrases) do
      add :phrase, :text, null: false
      add :pattern_type, :string, null: false
      add :occurrence_count, :integer, default: 0
      add :total_confidence, :float, default: 0.0
      add :avg_confidence, :float, default: 0.0
      add :last_seen_at, :timestamptz
      add :session_id, :uuid

      timestamps()
    end

    create unique_index(:hot_phrases, [:phrase, :session_id])
    create index(:hot_phrases, [:occurrence_count], comment: "Top phrases queries")
    create index(:hot_phrases, [:session_id, :occurrence_count], comment: "Session top phrases")

    # Create stream sessions table to group correlations
    create table(:stream_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :started_at, :timestamptz, null: false
      add :ended_at, :timestamptz
      add :total_transcriptions, :integer, default: 0
      add :total_chat_messages, :integer, default: 0
      add :total_correlations, :integer, default: 0
      add :top_patterns, :jsonb, default: "{}"
      add :ai_summary, :text

      timestamps()
    end

    create index(:stream_sessions, [:started_at, :ended_at])
  end

  def down do
    # Drop tables
    drop table(:hot_phrases)
    drop table(:stream_sessions)
    drop table(:correlations)
  end
end

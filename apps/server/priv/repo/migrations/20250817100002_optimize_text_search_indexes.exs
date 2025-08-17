defmodule Server.Repo.Migrations.OptimizeTextSearchIndexes do
  use Ecto.Migration

  def up do
    # Only run if not in test environment
    if System.get_env("MIX_ENV") != "test" do
      # Enable required extensions
      execute "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
      execute "CREATE EXTENSION IF NOT EXISTS btree_gin;"

      # Drop existing text search indexes if they exist to recreate with better configuration
      execute "DROP INDEX IF EXISTS transcriptions_text_gin_idx;"

      # Create optimized GIN index for transcriptions text search
      # Using gin_trgm_ops for similarity searches and partial matching
      execute """
        CREATE INDEX transcriptions_text_trgm_gin_idx
        ON transcriptions
        USING gin (text gin_trgm_ops)
        WHERE text IS NOT NULL;
      """

      # Create combined index for timestamp + text search
      # This is efficient for time-bounded text searches
      execute """
        CREATE INDEX transcriptions_timestamp_text_idx
        ON transcriptions
        USING gin (timestamp, text gin_trgm_ops);
      """

      # Create index for source_id + text search (common query pattern)
      execute """
        CREATE INDEX transcriptions_source_text_idx
        ON transcriptions
        USING gin (source_id, text gin_trgm_ops)
        WHERE source_id IS NOT NULL;
      """

      # For events table - optimize chat message searches
      # Create partial index only for chat messages
      execute """
        CREATE INDEX events_chat_message_text_idx
        ON events
        USING gin ((data->>'message') gin_trgm_ops)
        WHERE event_type = 'channel.chat.message'
        AND data->>'message' IS NOT NULL;
      """

      # Create index for user + chat message searches
      execute """
        CREATE INDEX events_user_chat_idx
        ON events
        USING gin (user_id, (data->>'message') gin_trgm_ops)
        WHERE event_type = 'channel.chat.message';
      """

      # For correlations table - optimize keyword and text searches
      execute """
        CREATE INDEX correlations_transcription_text_idx
        ON correlations
        USING gin (transcription_text gin_trgm_ops);
      """

      execute """
        CREATE INDEX correlations_chat_text_idx
        ON correlations
        USING gin (chat_text gin_trgm_ops);
      """

      # Create index for detected keywords array
      execute """
        CREATE INDEX correlations_keywords_idx
        ON correlations
        USING gin (detected_keywords);
      """

      # Create combined index for pattern type + text search
      execute """
        CREATE INDEX correlations_pattern_text_idx
        ON correlations
        USING gin (pattern_type, transcription_text gin_trgm_ops, chat_text gin_trgm_ops);
      """

      # Add text search configuration for better ranking
      # Create custom text search configuration for streaming content
      execute """
        DO $$
        BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_ts_config WHERE cfgname = 'streaming_english') THEN
            CREATE TEXT SEARCH CONFIGURATION streaming_english (COPY = english);
          END IF;
        END
        $$;
      """

      # Add full text search columns with proper weighting
      execute """
        ALTER TABLE transcriptions
        ADD COLUMN IF NOT EXISTS text_search_vector tsvector
        GENERATED ALWAYS AS (to_tsvector('english', coalesce(text, ''))) STORED;
      """

      execute """
        CREATE INDEX transcriptions_text_search_vector_idx
        ON transcriptions
        USING gin (text_search_vector);
      """

      # For events table - add text search vector for chat messages
      execute """
        ALTER TABLE events
        ADD COLUMN IF NOT EXISTS message_search_vector tsvector
        GENERATED ALWAYS AS (
          CASE
            WHEN event_type = 'channel.chat.message'
            THEN to_tsvector('english', coalesce(data->>'message', ''))
            ELSE NULL
          END
        ) STORED;
      """

      execute """
        CREATE INDEX events_message_search_vector_idx
        ON events
        USING gin (message_search_vector)
        WHERE message_search_vector IS NOT NULL;
      """

      # Update table statistics for query planner
      execute "ANALYZE transcriptions;"
      execute "ANALYZE events;"
      execute "ANALYZE correlations;"
    end
  end

  def down do
    if System.get_env("MIX_ENV") != "test" do
      # Drop text search columns
      execute "ALTER TABLE transcriptions DROP COLUMN IF EXISTS text_search_vector;"
      execute "ALTER TABLE events DROP COLUMN IF EXISTS message_search_vector;"

      # Drop all created indexes
      execute "DROP INDEX IF EXISTS transcriptions_text_trgm_gin_idx;"
      execute "DROP INDEX IF EXISTS transcriptions_timestamp_text_idx;"
      execute "DROP INDEX IF EXISTS transcriptions_source_text_idx;"
      execute "DROP INDEX IF EXISTS transcriptions_text_search_vector_idx;"
      execute "DROP INDEX IF EXISTS events_chat_message_text_idx;"
      execute "DROP INDEX IF EXISTS events_user_chat_idx;"
      execute "DROP INDEX IF EXISTS events_message_search_vector_idx;"
      execute "DROP INDEX IF EXISTS correlations_transcription_text_idx;"
      execute "DROP INDEX IF EXISTS correlations_chat_text_idx;"
      execute "DROP INDEX IF EXISTS correlations_keywords_idx;"
      execute "DROP INDEX IF EXISTS correlations_pattern_text_idx;"

      # Drop custom text search configuration
      execute "DROP TEXT SEARCH CONFIGURATION IF EXISTS streaming_english CASCADE;"
    end
  end
end

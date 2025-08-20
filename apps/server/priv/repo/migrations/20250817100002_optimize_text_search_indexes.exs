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
      execute """
        CREATE INDEX IF NOT EXISTS transcriptions_text_trgm_gin_idx
        ON transcriptions
        USING gin (text gin_trgm_ops)
        WHERE text IS NOT NULL;
      """

      # Create combined index for timestamp + text search
      execute """
        CREATE INDEX IF NOT EXISTS transcriptions_timestamp_text_idx
        ON transcriptions
        USING gin (timestamp, text gin_trgm_ops);
      """

      # Create index for source_id + text search
      execute """
        CREATE INDEX IF NOT EXISTS transcriptions_source_text_idx
        ON transcriptions
        USING gin (source_id, text gin_trgm_ops)
        WHERE source_id IS NOT NULL;
      """

      # For events table - optimize chat message searches
      execute """
        CREATE INDEX IF NOT EXISTS events_chat_message_text_idx
        ON events
        USING gin ((data->>'message') gin_trgm_ops)
        WHERE event_type = 'channel.chat.message'
        AND data->>'message' IS NOT NULL;
      """

      # Create index for user + chat message searches
      execute """
        CREATE INDEX IF NOT EXISTS events_user_chat_idx
        ON events
        USING gin (user_id, (data->>'message') gin_trgm_ops)
        WHERE event_type = 'channel.chat.message';
      """

      # Add regular tsvector column (not generated) for transcriptions
      execute "ALTER TABLE transcriptions ADD COLUMN IF NOT EXISTS text_search_vector tsvector;"

      # Create index for text search vector
      execute """
        CREATE INDEX IF NOT EXISTS transcriptions_text_search_vector_idx
        ON transcriptions
        USING gin (text_search_vector);
      """

      # Update table statistics for query planner
      execute "ANALYZE transcriptions;"
      execute "ANALYZE events;"
    end
  end

  def down do
    if System.get_env("MIX_ENV") != "test" do
      # Drop text search column
      execute "ALTER TABLE transcriptions DROP COLUMN IF EXISTS text_search_vector;"

      # Drop all created indexes
      execute "DROP INDEX IF EXISTS transcriptions_text_trgm_gin_idx;"
      execute "DROP INDEX IF EXISTS transcriptions_timestamp_text_idx;"
      execute "DROP INDEX IF EXISTS transcriptions_source_text_idx;"
      execute "DROP INDEX IF EXISTS transcriptions_text_search_vector_idx;"
      execute "DROP INDEX IF EXISTS events_chat_message_text_idx;"
      execute "DROP INDEX IF EXISTS events_user_chat_idx;"
    end
  end
end

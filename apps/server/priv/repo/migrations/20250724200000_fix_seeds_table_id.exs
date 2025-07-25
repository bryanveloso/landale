defmodule Server.Repo.Migrations.FixSeedsTableId do
  use Ecto.Migration

  def up do
    # CRITICAL: This only removes the DEFAULT, preserving all existing seed IDs
    execute "ALTER TABLE seeds ALTER COLUMN id DROP DEFAULT;"

    # Drop the sequence that was auto-created (safe - not used after removing DEFAULT)
    execute "DROP SEQUENCE IF EXISTS seeds_id_seq CASCADE;"
  end

  def down do
    # Find the max ID to restart sequence from correct position
    execute """
    DO $$
    DECLARE
      max_id INTEGER;
    BEGIN
      SELECT COALESCE(MAX(id), 0) INTO max_id FROM seeds;
      
      CREATE SEQUENCE seeds_id_seq START WITH (max_id + 1);
      ALTER TABLE seeds ALTER COLUMN id SET DEFAULT nextval('seeds_id_seq'::regclass);
    END $$;
    """
  end
end

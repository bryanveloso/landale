# Import IronMON data from old database export
# Usage: mix run priv/repo/seeds/import_ironmon_data.exs

alias Server.Repo
alias Server.Ironmon.{Challenge, Checkpoint, Seed, Result}
import Ecto.Query

# First, truncate existing data
Repo.delete_all(Result)
Repo.delete_all(Checkpoint)
Repo.delete_all(Seed)
Repo.delete_all(Challenge)

# Reset sequences to match import data
Repo.query!("SELECT setval('challenges_id_seq', 1, false);")
Repo.query!("SELECT setval('checkpoints_id_seq', 1, false);")
Repo.query!("SELECT setval('results_id_seq', 1, false);")

IO.puts "Reading ironmon_export.sql..."

# Read and execute the SQL file, transforming column names
sql_content = File.read!("ironmon_export.sql")

# Transform column names from camelCase to snake_case
transformed_sql = sql_content
|> String.replace(~r/"challengeId"/, "challenge_id")
|> String.replace(~r/"checkpointId"/, "checkpoint_id") 
|> String.replace(~r/"seedId"/, "seed_id")

IO.puts "Importing IronMON data..."

# Execute the transformed SQL
case Repo.query(transformed_sql) do
  {:ok, _} ->
    IO.puts "✅ IronMON data imported successfully!"
    
    # Show import summary
    challenges_count = Repo.aggregate(Challenge, :count, :id)
    checkpoints_count = Repo.aggregate(Checkpoint, :count, :id)
    seeds_count = Repo.aggregate(Seed, :count, :id)
    results_count = Repo.aggregate(Result, :count, :id)
    
    IO.puts """
    
    Import Summary:
    - Challenges: #{challenges_count}
    - Checkpoints: #{checkpoints_count}
    - Seeds: #{seeds_count}
    - Results: #{results_count}
    """
    
  {:error, error} ->
    IO.puts "❌ Error importing data:"
    IO.puts inspect(error)
end
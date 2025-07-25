# IronMON Challenge Seeds
# Run with: mix run priv/repo/seeds_ironmon.exs

alias Server.Repo
alias Server.Ironmon.{Challenge, Checkpoint}

# Create the Kaizo IronMON challenge if it doesn't exist
kaizo_challenge = case Repo.get_by(Challenge, name: "Kaizo IronMON") do
  nil ->
    {:ok, challenge} = Repo.insert!(%Challenge{
      name: "Kaizo IronMON"
    })
    IO.puts("Created Kaizo IronMON challenge")
    challenge
  challenge ->
    IO.puts("Kaizo IronMON challenge already exists")
    challenge
end

# Define checkpoint data - these correspond to the IronMON Connect plugin checkpoints
# Based on the TypeScript checkpoints for FireRed/LeafGreen
checkpoints = [
  %{id: 1, name: "LAB", trainer: "None", order: 1},
  %{id: 2, name: "RIVAL1", trainer: "Rival", order: 2},
  %{id: 3, name: "FIRSTTRAINER", trainer: "Trainer", order: 3},
  %{id: 4, name: "RIVAL2", trainer: "Rival", order: 4},
  %{id: 5, name: "BROCK", trainer: "Brock", order: 5},
  %{id: 6, name: "RIVAL3", trainer: "Rival", order: 6},
  %{id: 7, name: "RIVAL4", trainer: "Rival", order: 7},
  %{id: 8, name: "MISTY", trainer: "Misty", order: 8},
  %{id: 9, name: "SURGE", trainer: "Surge", order: 9},
  %{id: 10, name: "RIVAL5", trainer: "Rival", order: 10},
  %{id: 11, name: "ROCKETHIDEOUT", trainer: "Giovanni", order: 11},
  %{id: 12, name: "ERIKA", trainer: "Erika", order: 12},
  %{id: 13, name: "KOGA", trainer: "Koga", order: 13},
  %{id: 14, name: "RIVAL6", trainer: "Rival", order: 14},
  %{id: 15, name: "SILPHCO", trainer: "Giovanni", order: 15},
  %{id: 16, name: "SABRINA", trainer: "Sabrina", order: 16},
  %{id: 17, name: "BLAINE", trainer: "Blaine", order: 17},
  %{id: 18, name: "GIOVANNI", trainer: "Giovanni", order: 18},
  %{id: 19, name: "RIVAL7", trainer: "Rival", order: 19},
  %{id: 20, name: "LORELAI", trainer: "Lorelai", order: 20},
  %{id: 21, name: "BRUNO", trainer: "Bruno", order: 21},
  %{id: 22, name: "AGATHA", trainer: "Agatha", order: 22},
  %{id: 23, name: "LANCE", trainer: "Lance", order: 23},
  %{id: 24, name: "CHAMP", trainer: "Champ", order: 24}
]

# Insert checkpoints if they don't exist
Enum.each(checkpoints, fn checkpoint_data ->
  case Repo.get_by(Checkpoint, name: checkpoint_data.name) do
    nil ->
      Repo.insert!(%Checkpoint{
        name: checkpoint_data.name,
        trainer: checkpoint_data.trainer,
        order: checkpoint_data.order,
        challenge_id: kaizo_challenge.id
      })
      IO.puts("Created checkpoint: #{checkpoint_data.name}")
    _existing ->
      IO.puts("Checkpoint already exists: #{checkpoint_data.name}")
  end
end)

IO.puts("\nIronMON data seeded successfully!")
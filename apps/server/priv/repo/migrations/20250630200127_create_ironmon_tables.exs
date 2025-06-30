defmodule Server.Repo.Migrations.CreateIronmonTables do
  use Ecto.Migration

  def change do
    # Create challenges table
    create table(:challenges) do
      add :name, :text, null: false
    end

    create unique_index(:challenges, [:name])

    # Create checkpoints table
    create table(:checkpoints) do
      add :name, :text, null: false
      add :trainer, :text, null: false
      add :order, :integer, null: false
      add :challenge_id, references(:challenges, on_delete: :restrict), null: false
    end

    create unique_index(:checkpoints, [:name])
    create index(:checkpoints, [:challenge_id])
    create index(:checkpoints, [:order])

    # Create seeds table
    create table(:seeds) do
      add :challenge_id, references(:challenges, on_delete: :restrict), null: false
    end

    create index(:seeds, [:challenge_id])

    # Create results table
    create table(:results) do
      add :seed_id, references(:seeds, on_delete: :restrict), null: false
      add :checkpoint_id, references(:checkpoints, on_delete: :restrict), null: false
      add :result, :boolean, null: false
    end

    create unique_index(:results, [:seed_id, :checkpoint_id])
    create index(:results, [:seed_id])
    create index(:results, [:checkpoint_id])
    create index(:results, [:result])
  end
end

defmodule Server.Ironmon.Result do
  @moduledoc """
  Ecto schema for IronMON challenge checkpoint results.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "results" do
    field :result, :boolean

    belongs_to :seed, Server.Ironmon.Seed
    belongs_to :checkpoint, Server.Ironmon.Checkpoint
  end

  def changeset(result, attrs) do
    result
    |> cast(attrs, [:result, :seed_id, :checkpoint_id])
    |> validate_required([:result, :seed_id, :checkpoint_id])
    |> unique_constraint([:seed_id, :checkpoint_id])
    |> foreign_key_constraint(:seed_id)
    |> foreign_key_constraint(:checkpoint_id)
  end
end

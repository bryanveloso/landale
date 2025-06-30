defmodule Server.Ironmon.Challenge do
  @moduledoc """
  Ecto schema for IronMON challenges.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "challenges" do
    field :name, :string

    has_many :checkpoints, Server.Ironmon.Checkpoint
    has_many :seeds, Server.Ironmon.Seed
  end

  def changeset(challenge, attrs) do
    challenge
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end

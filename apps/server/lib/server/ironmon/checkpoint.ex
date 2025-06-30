defmodule Server.Ironmon.Checkpoint do
  @moduledoc """
  Ecto schema for IronMON challenge checkpoints.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "checkpoints" do
    field :name, :string
    field :trainer, :string
    field :order, :integer

    belongs_to :challenge, Server.Ironmon.Challenge
    has_many :results, Server.Ironmon.Result
  end

  def changeset(checkpoint, attrs) do
    checkpoint
    |> cast(attrs, [:name, :trainer, :order, :challenge_id])
    |> validate_required([:name, :trainer, :order, :challenge_id])
    |> unique_constraint(:name)
    |> foreign_key_constraint(:challenge_id)
  end
end

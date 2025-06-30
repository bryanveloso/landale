defmodule Server.Ironmon.Seed do
  @moduledoc """
  Ecto schema for IronMON challenge seeds/runs.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "seeds" do
    belongs_to :challenge, Server.Ironmon.Challenge
    has_many :results, Server.Ironmon.Result
  end

  def changeset(seed, attrs) do
    seed
    |> cast(attrs, [:challenge_id])
    |> validate_required([:challenge_id])
    |> foreign_key_constraint(:challenge_id)
  end
end

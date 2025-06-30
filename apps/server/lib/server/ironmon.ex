defmodule Server.Ironmon do
  @moduledoc """
  The Ironmon context for managing Pokemon IronMON challenges and results.
  """

  import Ecto.Query, warn: false
  alias Server.Repo
  alias Server.Ironmon.{Challenge, Checkpoint, Result, Seed}

  ## Challenges

  def list_challenges do
    Repo.all(Challenge)
  end

  def get_challenge!(id), do: Repo.get!(Challenge, id)

  def get_challenge_by_name(name) do
    Repo.get_by(Challenge, name: name)
  end

  def create_challenge(attrs \\ %{}) do
    %Challenge{}
    |> Challenge.changeset(attrs)
    |> Repo.insert()
  end

  ## Checkpoints

  def list_checkpoints_for_challenge(challenge_id) do
    from(c in Checkpoint,
      where: c.challenge_id == ^challenge_id,
      order_by: [asc: c.order]
    )
    |> Repo.all()
  end

  def get_checkpoint!(id), do: Repo.get!(Checkpoint, id)

  def create_checkpoint(attrs \\ %{}) do
    %Checkpoint{}
    |> Checkpoint.changeset(attrs)
    |> Repo.insert()
  end

  ## Seeds

  def list_seeds_for_challenge(challenge_id) do
    from(s in Seed,
      where: s.challenge_id == ^challenge_id
    )
    |> Repo.all()
  end

  def get_seed!(id), do: Repo.get!(Seed, id)

  def create_seed(attrs \\ %{}) do
    %Seed{}
    |> Seed.changeset(attrs)
    |> Repo.insert()
  end

  ## Results

  def get_result(seed_id, checkpoint_id) do
    Repo.get_by(Result, seed_id: seed_id, checkpoint_id: checkpoint_id)
  end

  def create_or_update_result(seed_id, checkpoint_id, result_value) do
    case get_result(seed_id, checkpoint_id) do
      nil ->
        %Result{}
        |> Result.changeset(%{
          seed_id: seed_id,
          checkpoint_id: checkpoint_id,
          result: result_value
        })
        |> Repo.insert()

      existing_result ->
        existing_result
        |> Result.changeset(%{result: result_value})
        |> Repo.update()
    end
  end

  ## Statistics

  def get_checkpoint_stats(checkpoint_id) do
    from(r in Result,
      where: r.checkpoint_id == ^checkpoint_id,
      group_by: r.result,
      select: {r.result, count(r.id)}
    )
    |> Repo.all()
    |> Enum.into(%{})
    |> then(fn stats ->
      wins = Map.get(stats, true, 0)
      losses = Map.get(stats, false, 0)
      total = wins + losses

      %{
        wins: wins,
        losses: losses,
        total: total,
        win_rate: if(total > 0, do: wins / total, else: 0.0)
      }
    end)
  end

  def get_recent_results(limit \\ 10, cursor \\ nil) do
    query =
      from(r in Result,
        join: s in Seed,
        on: r.seed_id == s.id,
        join: c in Checkpoint,
        on: r.checkpoint_id == c.id,
        join: ch in Challenge,
        on: s.challenge_id == ch.id,
        select: %{
          id: r.id,
          seed_id: s.id,
          checkpoint_name: c.name,
          trainer: c.trainer,
          challenge_name: ch.name,
          result: r.result
        },
        order_by: [desc: r.id],
        limit: ^limit
      )

    query =
      if cursor do
        from(q in query, where: q.id < ^cursor)
      else
        query
      end

    Repo.all(query)
  end

  def get_active_challenge(seed_id) do
    from(s in Seed,
      join: ch in Challenge,
      on: s.challenge_id == ch.id,
      left_join: r in Result,
      on: r.seed_id == s.id,
      left_join: c in Checkpoint,
      on: r.checkpoint_id == c.id,
      where: s.id == ^seed_id,
      select: %{
        seed_id: s.id,
        challenge_name: ch.name,
        completed_checkpoints: count(r.id, :distinct),
        last_result: max(r.result)
      },
      group_by: [s.id, ch.name]
    )
    |> Repo.one()
  end
end

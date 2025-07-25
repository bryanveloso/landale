defmodule Server.Ironmon do
  @moduledoc """
  The Ironmon context for managing Pokemon IronMON challenges and results.
  """

  import Ecto.Query, warn: false
  alias Server.Repo
  alias Server.Ironmon.{Challenge, Checkpoint, Result, Seed}

  @typedoc "Statistics for a checkpoint"
  @type checkpoint_stats :: %{
          wins: integer(),
          losses: integer(),
          total: integer(),
          win_rate: float()
        }

  @typedoc "Recent result with joined data"
  @type recent_result :: %{
          id: integer(),
          seed_id: integer(),
          checkpoint_name: String.t(),
          trainer: String.t(),
          challenge_name: String.t(),
          result: boolean()
        }

  @typedoc "Active challenge information"
  @type active_challenge :: %{
          seed_id: integer(),
          challenge_name: String.t(),
          completed_checkpoints: integer(),
          last_result: boolean() | nil
        }

  ## Challenges

  @doc """
  Lists all challenges in the database.

  ## Returns
  - List of `Challenge` structs
  """
  @spec list_challenges() :: [Challenge.t()]
  def list_challenges do
    Repo.all(Challenge)
  end

  @doc """
  Gets a challenge by ID, raising if not found.

  ## Parameters
  - `id` - The challenge ID

  ## Returns
  - `Challenge` struct

  ## Raises
  - `Ecto.NoResultsError` if challenge not found
  """
  @spec get_challenge!(integer()) :: Challenge.t()
  def get_challenge!(id), do: Repo.get!(Challenge, id)

  @doc """
  Gets a challenge by name.

  ## Parameters
  - `name` - The challenge name

  ## Returns
  - `Challenge` struct or `nil` if not found
  """
  @spec get_challenge_by_name(String.t()) :: Challenge.t() | nil
  def get_challenge_by_name(name) do
    Repo.get_by(Challenge, name: name)
  end

  @doc """
  Creates a new challenge.

  ## Parameters
  - `attrs` - Map of challenge attributes (optional)

  ## Returns
  - `{:ok, challenge}` on success
  - `{:error, changeset}` on validation error
  """
  @spec create_challenge(map()) :: {:ok, Challenge.t()} | {:error, Ecto.Changeset.t()}
  def create_challenge(attrs \\ %{}) do
    %Challenge{}
    |> Challenge.changeset(attrs)
    |> Repo.insert()
  end

  ## Checkpoints

  @doc """
  Lists all checkpoints for a specific challenge, ordered by order field.

  ## Parameters
  - `challenge_id` - The ID of the challenge

  ## Returns
  - List of `Checkpoint` structs ordered by order field
  """
  @spec list_checkpoints_for_challenge(integer()) :: [Checkpoint.t()]
  def list_checkpoints_for_challenge(challenge_id) do
    from(c in Checkpoint,
      where: c.challenge_id == ^challenge_id,
      order_by: [asc: c.order]
    )
    |> Repo.all()
  end

  @doc """
  Gets a checkpoint by ID, raising if not found.

  ## Parameters
  - `id` - The checkpoint ID

  ## Returns
  - `Checkpoint` struct

  ## Raises
  - `Ecto.NoResultsError` if checkpoint not found
  """
  @spec get_checkpoint!(integer()) :: Checkpoint.t()
  def get_checkpoint!(id), do: Repo.get!(Checkpoint, id)

  @doc """
  Creates a new checkpoint.

  ## Parameters
  - `attrs` - Map of checkpoint attributes (optional)

  ## Returns
  - `{:ok, checkpoint}` on success
  - `{:error, changeset}` on validation error
  """
  @spec create_checkpoint(map()) :: {:ok, Checkpoint.t()} | {:error, Ecto.Changeset.t()}
  def create_checkpoint(attrs \\ %{}) do
    %Checkpoint{}
    |> Checkpoint.changeset(attrs)
    |> Repo.insert()
  end

  ## Seeds

  @doc """
  Lists all seeds for a specific challenge.

  ## Parameters
  - `challenge_id` - The ID of the challenge

  ## Returns
  - List of `Seed` structs
  """
  @spec list_seeds_for_challenge(integer()) :: [Seed.t()]
  def list_seeds_for_challenge(challenge_id) do
    from(s in Seed,
      where: s.challenge_id == ^challenge_id
    )
    |> Repo.all()
  end

  @doc """
  Gets a seed by ID, raising if not found.

  ## Parameters
  - `id` - The seed ID

  ## Returns
  - `Seed` struct

  ## Raises
  - `Ecto.NoResultsError` if seed not found
  """
  @spec get_seed!(integer()) :: Seed.t()
  def get_seed!(id), do: Repo.get!(Seed, id)

  @doc """
  Creates a new seed.

  ## Parameters
  - `attrs` - Map of seed attributes (optional)

  ## Returns
  - `{:ok, seed}` on success
  - `{:error, changeset}` on validation error
  """
  @spec create_seed(map()) :: {:ok, Seed.t()} | {:error, Ecto.Changeset.t()}
  def create_seed(attrs \\ %{}) do
    %Seed{}
    |> Seed.changeset(attrs)
    |> Repo.insert()
  end

  ## Results

  @doc """
  Gets a result for a specific seed and checkpoint combination.

  ## Parameters
  - `seed_id` - The ID of the seed
  - `checkpoint_id` - The ID of the checkpoint

  ## Returns
  - `Result` struct or `nil` if not found
  """
  @spec get_result(integer(), integer()) :: Result.t() | nil
  def get_result(seed_id, checkpoint_id) do
    Repo.get_by(Result, seed_id: seed_id, checkpoint_id: checkpoint_id)
  end

  @doc """
  Creates a new result or updates an existing one.

  ## Parameters
  - `seed_id` - The ID of the seed
  - `checkpoint_id` - The ID of the checkpoint
  - `result_value` - The result value (boolean)

  ## Returns
  - `{:ok, result}` on success
  - `{:error, changeset}` on validation error
  """
  @spec create_or_update_result(integer(), integer(), boolean()) :: {:ok, Result.t()} | {:error, Ecto.Changeset.t()}
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

  @doc """
  Gets statistics for a specific checkpoint.

  ## Parameters
  - `checkpoint_id` - The ID of the checkpoint

  ## Returns
  - Map containing wins, losses, total, and win_rate
  """
  @spec get_checkpoint_stats(integer()) :: checkpoint_stats()
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

  @doc """
  Gets recent results with pagination support.

  ## Parameters
  - `limit` - Maximum number of results to return (default: 10)
  - `cursor` - ID to start pagination from (optional)

  ## Returns
  - List of result maps with joined challenge/checkpoint data
  """
  @spec get_recent_results(integer(), integer() | nil) :: [recent_result()]
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

  @doc """
  Gets active challenge information for a specific seed.

  ## Parameters
  - `seed_id` - The ID of the seed

  ## Returns
  - `{:ok, challenge_info}` if found
  - `{:error, message}` if not found
  """
  @spec get_active_challenge(integer()) :: {:ok, active_challenge()} | {:error, String.t()}
  def get_active_challenge(seed_id) do
    case from(s in Seed,
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
             last_result: fragment("bool_or(?)", r.result)
           },
           group_by: [s.id, ch.name]
         )
         |> Repo.one() do
      nil -> {:error, "No active challenge found"}
      challenge -> {:ok, challenge}
    end
  end

  ## StreamProducer Context Functions

  @doc """
  Gets the current active seed (latest run).
  Delegates to RunTracker which maintains the authoritative state.

  ## Returns
  - Map with seed info if active run exists
  - `nil` if no active run
  """
  @spec get_current_seed() :: map() | nil
  def get_current_seed do
    case Server.Ironmon.RunTracker.current_seed() do
      nil ->
        nil

      seed_id ->
        seed = Repo.get(Seed, seed_id)

        if seed do
          %{
            id: seed.id,
            challenge_id: seed.challenge_id,
            created_at: seed.inserted_at
          }
        else
          nil
        end
    end
  end

  @doc """
  Gets current checkpoint progress for the active run.
  Shows which checkpoint we're on and its historical clear rate.

  ## Returns
  - Map with checkpoint progress info
  - `nil` if no active run
  """
  @spec get_current_checkpoint_progress() :: map() | nil
  def get_current_checkpoint_progress do
    with seed_id when not is_nil(seed_id) <- Server.Ironmon.RunTracker.current_seed(),
         stats <- Server.Ironmon.RunTracker.current_stats(),
         seed <- Repo.get!(Seed, seed_id) do
      # Get the next uncompleted checkpoint
      cleared_checkpoint_ids =
        from(r in Result,
          where: r.seed_id == ^seed_id and r.result == true,
          select: r.checkpoint_id
        )
        |> Repo.all()

      next_checkpoint =
        from(c in Checkpoint,
          where: c.challenge_id == ^seed.challenge_id and c.id not in ^cleared_checkpoint_ids,
          order_by: [asc: c.order],
          limit: 1
        )
        |> Repo.one()

      if next_checkpoint do
        checkpoint_stats = get_checkpoint_stats(next_checkpoint.id)

        %{
          current_checkpoint: next_checkpoint.name,
          trainer: next_checkpoint.trainer,
          clear_rate: checkpoint_stats.win_rate,
          attempts: checkpoint_stats.total,
          checkpoints_cleared: stats.checkpoints_cleared,
          total_checkpoints: stats.total_checkpoints
        }
      else
        # All checkpoints cleared
        %{
          current_checkpoint: "Complete!",
          trainer: nil,
          clear_rate: 1.0,
          attempts: 0,
          checkpoints_cleared: stats.checkpoints_cleared,
          total_checkpoints: stats.total_checkpoints
        }
      end
    else
      _ -> nil
    end
  end

  @doc """
  Gets recent checkpoint clears across all runs.

  ## Parameters
  - `limit` - Number of recent clears to return (default: 5)

  ## Returns
  - List of checkpoint clear maps
  """
  @spec get_recent_checkpoint_clears(integer()) :: [map()]
  def get_recent_checkpoint_clears(limit \\ 5) do
    from(r in Result,
      join: c in Checkpoint,
      on: r.checkpoint_id == c.id,
      join: s in Seed,
      on: r.seed_id == s.id,
      where: r.result == true,
      order_by: [desc: r.id],
      limit: ^limit,
      select: %{
        checkpoint_name: c.name,
        trainer: c.trainer,
        seed_id: s.id,
        # No timestamp data available
        cleared_at: nil
      }
    )
    |> Repo.all()
  end

  @doc """
  Gets aggregated run statistics for a seed or globally.

  ## Parameters
  - `seed_id` - Specific seed ID or `nil` for global stats

  ## Returns
  - Map with run statistics
  """
  @spec get_run_statistics(integer() | nil) :: map()
  def get_run_statistics(seed_id \\ nil) do
    if seed_id do
      # Stats for specific seed
      stats = Server.Ironmon.RunTracker.current_stats()

      %{
        seed_id: seed_id,
        attempt_number: seed_id,
        checkpoints_cleared: stats.checkpoints_cleared,
        total_checkpoints: stats.total_checkpoints,
        last_checkpoint: stats.last_checkpoint,
        progress_percentage:
          if stats.total_checkpoints > 0 do
            Float.round(stats.checkpoints_cleared / stats.total_checkpoints * 100, 1)
          else
            0.0
          end
      }
    else
      # Global stats
      total_seeds = Repo.aggregate(Seed, :count)

      # Get checkpoint clear rates across all runs
      checkpoint_stats =
        from(c in Checkpoint,
          left_join: r in Result,
          on: c.id == r.checkpoint_id,
          group_by: c.id,
          select: %{
            checkpoint_id: c.id,
            total_attempts: count(r.id),
            successful_attempts: sum(fragment("CASE WHEN ? THEN 1 ELSE 0 END", r.result))
          }
        )
        |> Repo.all()
        |> Enum.reduce({0, 0}, fn stat, {total, successful} ->
          {total + (stat.total_attempts || 0),
           successful + (stat.successful_attempts || Decimal.new(0) |> Decimal.to_integer())}
        end)

      {total_attempts, successful_clears} = checkpoint_stats

      %{
        total_attempts: total_seeds,
        total_checkpoint_attempts: total_attempts,
        total_checkpoint_clears: successful_clears,
        overall_clear_rate:
          if total_attempts > 0 do
            Float.round(successful_clears / total_attempts * 100, 1)
          else
            0.0
          end
      }
    end
  end
end
